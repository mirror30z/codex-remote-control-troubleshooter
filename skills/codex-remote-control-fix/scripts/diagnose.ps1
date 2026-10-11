[CmdletBinding()]
param(
    [string]$Endpoint = 'https://chatgpt.com/backend-api/wham/remote/control/server',
    [string]$ProxyUrl,
    [string]$DnsServer,
    [switch]$SkipProbes
)

$ErrorActionPreference = 'Stop'

if ([Environment]::OSVersion.Platform -ne 'Win32NT') {
    throw 'This diagnostic runs on Windows only.'
}

function ConvertTo-SafeUri {
    param([string]$Value, [string[]]$Schemes)
    $uri = $null
    if ([uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri) -and
        $uri.Scheme -in $Schemes -and $uri.Host -and $uri.Port -gt 0 -and
        $uri.DnsSafeHost -notmatch '(^|\.)diagnostic\.invalid$' -and
        -not $uri.UserInfo -and -not $uri.Query -and -not $uri.Fragment) {
        return $uri
    }
    return $null
}

function Get-EndpointProbeArguments {
    param([string]$Url, [string]$Proxy)
    # -q must be first: do not load a user's curlrc (cookies, headers, proxy, etc.).
    $arguments = @('-q', '--silent', '--show-error', '--output', 'NUL', '--dump-header', '-', '--connect-timeout', '8', '--max-time', '12', '--write-out', 'HTTP=%{http_code};TIME=%{time_total}', '--request', 'GET')
    if ($Proxy) {
        # A nonmatching entry avoids empty-argument differences in Windows PS 5.1.
        # Override inherited NO_PROXY even when it contains '*' or the target host.
        $arguments += @('--proxy', $Proxy, '--noproxy', 'diagnostic.invalid')
    } else { $arguments += @('--noproxy', '*') }
    return $arguments + @('--url', $Url)
}

function Invoke-EndpointProbe {
    param([string]$Label, [string]$Url, [string]$Proxy)

    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if (-not $curl) { return [pscustomobject]@{ mode = $Label; status = 'curl.exe unavailable' } }

    $arguments = @(Get-EndpointProbeArguments -Url $Url -Proxy $Proxy)

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    # Native failures are captured as evidence, including in PowerShell 7.3+.
    $PSNativeCommandUseErrorActionPreference = $false
    try {
        $result = & $curl.Source @arguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    return ConvertFrom-EndpointProbeOutput -Label $Label -Lines $result -ExitCode $exitCode
}

function ConvertFrom-EndpointProbeOutput {
    param([string]$Label, [object[]]$Lines, [int]$ExitCode)
    $result = @($Lines | ForEach-Object { "$_" })
    $response = ($result | Where-Object { $_ -match '^HTTP=\d{3};TIME=[\d.]+$' } | Select-Object -Last 1)
    $challenge = ($result | Where-Object { "$_" -match '^cf-mitigated:\s*challenge\s*$' } | Select-Object -Last 1)
    return [pscustomobject]@{
        mode = $Label
        exitCode = $ExitCode
        result = if ($response) { "$response" } else { 'no HTTP response' }
        cloudflareChallenge = [bool]$challenge
        # Do not include raw stderr, which may contain credentials or URLs.
        error = if ($ExitCode -ne 0) { "curl failed with exit code $ExitCode; inspect locally if needed." } else { $null }
    }
}

function Resolve-ProxyUrl {
    param([string]$Explicit, [object]$Settings)

    if ($Explicit) {
        $uri = ConvertTo-SafeUri -Value $Explicit -Schemes @('http', 'https', 'socks5', 'socks5h')
        if (-not $uri -or $uri.AbsolutePath -ne '/') {
            throw 'ProxyUrl must be an HTTP(S) or SOCKS5 URL with a host and port, without credentials, query, fragment, or path.'
        }
        return $uri.AbsoluteUri.TrimEnd('/')
    }
    if ($Settings.ProxyEnable -ne 1 -or -not $Settings.ProxyServer) { return $null }
    $entry = [string]$Settings.ProxyServer
    if ($entry -match '(?:^|;)https=([^;]+)') { $entry = $Matches[1] }
    elseif ($entry -match ';') { return $null }
    if ($entry -notmatch '^[a-z]+://') { $entry = "http://$entry" }
    try {
        $uri = ConvertTo-SafeUri -Value $entry -Schemes @('http', 'https', 'socks5', 'socks5h')
        if ($uri -and $uri.AbsolutePath -eq '/') { return $uri.AbsoluteUri.TrimEnd('/') }
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

function Test-LocalProxyListener {
    param([string]$ComputerName, [int]$Port)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $pending = $client.BeginConnect($ComputerName, $Port, $null, $null)
        try {
            if (-not $pending.AsyncWaitHandle.WaitOne(1500)) { return $false }
            $client.EndConnect($pending)
            return $client.Connected
        } finally { $pending.AsyncWaitHandle.Close() }
    } catch { return $false }
    finally { $client.Close() }
}

function Test-IsLoopbackHost {
    param([string]$HostName)
    if ($HostName -eq 'localhost') { return $true }
    $address = $null
    return ([System.Net.IPAddress]::TryParse($HostName, [ref]$address) -and
        [System.Net.IPAddress]::IsLoopback($address))
}

$endpointUri = ConvertTo-SafeUri -Value $Endpoint -Schemes @('https')
if (-not $endpointUri) { throw 'Endpoint must be an HTTPS URL without credentials, query, or fragment.' }
$settings = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
$effectiveProxy = Resolve-ProxyUrl -Explicit $ProxyUrl -Settings $settings

$report = [ordered]@{
    schemaVersion = 2
    collectedAt = (Get-Date).ToString('o')
    os = 'Windows'
    powerShellVersion = $PSVersionTable.PSVersion.ToString()
    endpointHost = $endpointUri.DnsSafeHost
    dns = $null
    alternateDns = $null
    adapterDnsServers = @()
    selectedRoutes = @()
    routeErrors = @()
    virtualAdapters = @()
    relevantServices = @()
    systemProxy = $null
    processProxyVariables = @()
    proxyListener = $null
    codexProcesses = @()
    codexDomainConnections = @()
    probes = @()
    probesSkipped = [bool]$SkipProbes
}

$report.dns = Get-DnsAnswers -Name $endpointUri.DnsSafeHost
if ($DnsServer) {
    $report.alternateDns = [pscustomobject]@{
        server = $DnsServer
        answers = Get-DnsAnswers -Name $endpointUri.DnsSafeHost -Server $DnsServer
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

foreach ($address in @($report.dns.A) + @($report.dns.AAAA)) {
    try {
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
    } catch {
        $report.routeErrors += [pscustomobject]@{ remoteAddress = $address; error = $_.Exception.Message }
    }
}

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
    if (Test-IsLoopbackHost -HostName $proxyUri.DnsSafeHost) {
        try {
            $report.proxyListener = [pscustomobject]@{
                host = $proxyUri.Host
                port = $proxyUri.Port
                listening = Test-LocalProxyListener -ComputerName $proxyUri.DnsSafeHost -Port $proxyUri.Port
            }
        } catch { $report.proxyListenerError = $_.Exception.Message }
    }
}

if (-not $SkipProbes) {
    $report.probes += Invoke-EndpointProbe -Label 'direct' -Url $endpointUri.AbsoluteUri
    if ($effectiveProxy) { $report.probes += Invoke-EndpointProbe -Label 'explicit-proxy' -Url $endpointUri.AbsoluteUri -Proxy $effectiveProxy }
}

[pscustomobject]$report | ConvertTo-Json -Depth 6
