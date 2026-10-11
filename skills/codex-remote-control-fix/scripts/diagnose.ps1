param(
    [string]$Endpoint = 'https://chatgpt.com/backend-api/wham/remote/control/server',
    [string]$ProxyUrl
)

$ErrorActionPreference = 'Stop'

if ([Environment]::OSVersion.Platform -ne 'Win32NT') {
    throw 'This diagnostic runs on Windows only.'
}

function Invoke-EndpointProbe {
    param([string]$Label, [string]$Url, [string]$Proxy)

    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if (-not $curl) { return [pscustomobject]@{ mode = $Label; status = 'curl.exe unavailable' } }

    $arguments = @('--silent', '--show-error', '--output', 'NUL', '--connect-timeout', '8', '--max-time', '12', '--write-out', 'HTTP=%{http_code};TIME=%{time_total}', '--request', 'GET')
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
    return [pscustomobject]@{
        mode = $Label
        exitCode = $exitCode
        result = if ($response) { "$response" } else { 'no HTTP response' }
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

$report = [ordered]@{
    collectedAt = (Get-Date).ToString('o')
    os = 'Windows'
    dns = @()
    selectedRoutes = @()
    virtualAdapters = @()
    relevantServices = @()
    systemProxy = $null
    probes = @()
}

try {
    $answers = @(Resolve-DnsName chatgpt.com -Type A -ErrorAction Stop | Where-Object { $_.Type -eq 'A' -and $_.IPAddress } | Select-Object -ExpandProperty IPAddress -Unique)
    $report.dns = $answers
    foreach ($address in $answers) {
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
} catch { $report.dnsError = $_.Exception.Message }

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

$report.probes += Invoke-EndpointProbe -Label 'direct' -Url $Endpoint
if ($effectiveProxy) { $report.probes += Invoke-EndpointProbe -Label 'explicit-proxy' -Url $Endpoint -Proxy $effectiveProxy }

[pscustomobject]$report | ConvertTo-Json -Depth 6
