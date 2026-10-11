param(
    [string]$Endpoint = 'https://chatgpt.com/backend-api/wham/remote/control/server',
    [string]$ProxyUrl,
    [string]$DnsServer
)

$ErrorActionPreference = 'Stop'

if ([Environment]::OSVersion.Platform -ne 'Win32NT') {
    throw 'This diagnostic runs on Windows only.'
}

function Invoke-EndpointProbe {
    param([string]$Label, [string]$Url, [string]$Proxy)

    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if (-not $curl) { return [pscustomobject]@{ mode = $Label; status = 'curl.exe unavailable' } }

    $arguments = @('--silent', '--show-error', '--output', 'NUL', '--dump-header', '-', '--connect-timeout', '8', '--max-time', '12', '--write-out', 'HTTP=%{http_code};TIME=%{time_total}', '--request', 'GET')
    if ($Proxy) { $arguments += @('--proxy', $Proxy) }
    else { $arguments += @('--noproxy', '*') }
    $arguments += $Url

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $result = & $curl.Source @arguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    $response = ($result | Where-Object { $_ -is [string] -and $_ -match 'HTTP=\d{3}' } | Select-Object -Last 1)
    $errorText = ($result | Where-Object { "$_" -match 'curl: \(' } | Select-Object -First 1)
    $challenge = ($result | Where-Object { "$_" -match '^cf-mitigated:\s*challenge\s*$' } | Select-Object -Last 1)
    return [pscustomobject]@{
        mode = $Label
        exitCode = $exitCode
        result = if ($response) { "$response" } else { 'no HTTP response' }
        cloudflareChallenge = [bool]$challenge
        error = if ($errorText) { ("$errorText" -replace 'https?://\S+', '<URL>') } else { $null }
    }
}

function Resolve-ProxyUrl {
    param([string]$Explicit, [object]$Settings)

    if ($Explicit) { return $Explicit }
    if ($Settings.ProxyEnable -ne 1 -or -not $Settings.ProxyServer) { return $null }
    $entry = [string]$Settings.ProxyServer
    if ($entry -match '(?:^|;)https=([^;]+)') { $entry = $Matches[1] }
    elseif ($entry -match ';') { return $null }
    if ($entry -notmatch '^[a-z]+://') { $entry = "http://$entry" }
    try {
        $uri = [uri]$entry
        if ($uri.Host -and $uri.Port -gt 0) { return $uri.AbsoluteUri.TrimEnd('/') }
    } catch {}
    return $null
}

function Get-DnsAnswers {
    param([string]$Name, [string]$Server)
    $query = @{ Name = $Name; ErrorAction = 'Stop' }
    if ($Server) { $query.Server = $Server }
    $answers = [ordered]@{ A = @(); AAAA = @() }
    foreach ($type in @('A', 'AAAA')) {
        try {
            $query.Type = $type
            $answers[$type] = @(Resolve-DnsName @query |
                Where-Object { $_.Type -eq $type -and $_.IPAddress } |
                Select-Object -ExpandProperty IPAddress -Unique)
        } catch { $answers["${type}Error"] = $_.Exception.Message }
    }
    return [pscustomobject]$answers
}

$report = [ordered]@{
    collectedAt = (Get-Date).ToString('o')
    os = 'Windows'
    dns = $null
    alternateDns = $null
    adapterDnsServers = @()
    selectedRoutes = @()
    virtualAdapters = @()
    relevantServices = @()
    systemProxy = $null
    processProxyVariables = @()
    proxyListener = $null
    codexProcesses = @()
    codexDomainConnections = @()
    probes = @()
}

$report.dns = Get-DnsAnswers -Name 'chatgpt.com'
if ($DnsServer) {
    $report.alternateDns = [pscustomobject]@{
        server = $DnsServer
        answers = Get-DnsAnswers -Name 'chatgpt.com' -Server $DnsServer
    }
}

try {
    $upIndexes = @(Get-NetAdapter -IncludeHidden -ErrorAction Stop |
        Where-Object { $_.Status -eq 'Up' } |
        Select-Object -ExpandProperty ifIndex)
    $report.adapterDnsServers = @(Get-DnsClientServerAddress -ErrorAction Stop |
        Where-Object { $upIndexes -contains $_.InterfaceIndex -and $_.ServerAddresses.Count -gt 0 } |
        Select-Object InterfaceIndex, InterfaceAlias, AddressFamily, ServerAddresses)
} catch { $report.adapterDnsError = $_.Exception.Message }

try {
    foreach ($address in @($report.dns.A) + @($report.dns.AAAA)) {
        $routes = @(Find-NetRoute -RemoteIPAddress $address -ErrorAction Stop | Where-Object { $_.DestinationPrefix })
        foreach ($route in $routes) {
            $report.selectedRoutes += [pscustomobject]@{
                remoteAddress = $address
                destinationPrefix = $route.DestinationPrefix
                interfaceIndex = $route.InterfaceIndex
                interfaceAlias = $route.InterfaceAlias
                nextHop = $route.NextHop
            }
        }
    }
} catch { $report.routeError = $_.Exception.Message }

try {
    $report.codexProcesses = @(Get-Process -ErrorAction Stop |
        Where-Object { $_.ProcessName -match '^(Codex|ChatGPT)$' } |
        Select-Object Id, ProcessName)
    $processIds = @($report.codexProcesses | Select-Object -ExpandProperty Id)
    $resolvedAddresses = @($report.dns.A) + @($report.dns.AAAA)
    if ($processIds.Count -gt 0) {
        $report.codexDomainConnections = @(Get-NetTCPConnection -State Established, SynSent -ErrorAction Stop |
            Where-Object { $processIds -contains $_.OwningProcess -and $resolvedAddresses -contains $_.RemoteAddress } |
            Select-Object OwningProcess, RemoteAddress, RemotePort, @{ Name = 'State'; Expression = { $_.State.ToString() } })
    }
} catch { $report.processConnectionError = $_.Exception.Message }

try {
    $report.virtualAdapters = @(Get-NetAdapter -IncludeHidden -ErrorAction Stop |
        Where-Object { ($_.Name + ' ' + $_.InterfaceDescription) -match 'Clash|Mihomo|aTrust|Sangfor|TUN|Wintun|vEthernet|Hyper-V|Tailscale|ZeroTier' } |
        Select-Object ifIndex, Name, InterfaceDescription, Status)
} catch { $report.adapterError = $_.Exception.Message }

try {
    $report.relevantServices = @(Get-Service -ErrorAction Stop |
        Where-Object { ($_.Name + ' ' + $_.DisplayName) -match 'Clash|Mihomo|aTrust|Sangfor' } |
        Select-Object Name, DisplayName, @{ Name = 'Status'; Expression = { $_.Status.ToString() } })
} catch { $report.serviceError = $_.Exception.Message }

$settings = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
$effectiveProxy = Resolve-ProxyUrl -Explicit $ProxyUrl -Settings $settings
$report.systemProxy = [pscustomobject]@{
    enabled = ($settings.ProxyEnable -eq 1)
    pacConfigured = [bool]$settings.AutoConfigURL
    endpoint = if ($effectiveProxy) { $uri = [uri]$effectiveProxy; "{0}://{1}:{2}" -f $uri.Scheme, $uri.Host, $uri.Port } else { $null }
    note = if (($settings.ProxyEnable -eq 1 -or $settings.AutoConfigURL) -and -not $effectiveProxy) { 'Proxy or PAC is configured but could not be safely parsed; pass -ProxyUrl explicitly if needed.' } else { $null }
}

foreach ($name in @('HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'WS_PROXY', 'WSS_PROXY', 'NO_PROXY')) {
    $value = [Environment]::GetEnvironmentVariable($name, 'Process')
    if ($value) {
        $report.processProxyVariables += [pscustomobject]@{
            name = $name
            configured = $true
            endpoint = if ($name -eq 'NO_PROXY') { '<redacted>' } else {
                try {
                    $proxyUri = [uri]$value
                    if ($proxyUri.Host) { '{0}://{1}:{2}' -f $proxyUri.Scheme, $proxyUri.Host, $proxyUri.Port }
                    else { '<redacted>' }
                } catch { '<redacted>' }
            }
        }
    }
}

if ($effectiveProxy) {
    $proxyUri = [uri]$effectiveProxy
    if ($proxyUri.Host -in @('127.0.0.1', 'localhost', '::1')) {
        try {
            $report.proxyListener = [pscustomobject]@{
                host = $proxyUri.Host
                port = $proxyUri.Port
                listening = [bool](Test-NetConnection -ComputerName $proxyUri.Host -Port $proxyUri.Port -InformationLevel Quiet -WarningAction SilentlyContinue)
            }
        } catch { $report.proxyListenerError = $_.Exception.Message }
    }
}

$report.probes += Invoke-EndpointProbe -Label 'direct' -Url $Endpoint
if ($effectiveProxy) { $report.probes += Invoke-EndpointProbe -Label 'explicit-proxy' -Url $Endpoint -Proxy $effectiveProxy }

[pscustomobject]$report | ConvertTo-Json -Depth 6
