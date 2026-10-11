$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot '../skills/codex-remote-control-fix/scripts/diagnose.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path $scriptPath).Path, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }

# Load only helpers; unit tests do not invoke Windows queries or remote endpoints.
$functions = $ast.FindAll({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
}, $false)
foreach ($function in $functions) { Invoke-Expression $function.Extent.Text }
$script:checks = 0
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
    $script:checks++
}
function Assert-Rejected {
    param([scriptblock]$Action, [string]$Message)
    $rejected = $false
    try { & $Action | Out-Null } catch { $rejected = $true }
    Assert-True $rejected $Message
}

$settings = [pscustomobject]@{ ProxyEnable = 1; ProxyServer = '127.0.0.1:7890' }
Assert-True ((Resolve-ProxyUrl -Settings $settings) -eq 'http://127.0.0.1:7890') 'Single proxy not parsed'
$settings.ProxyServer = 'http=127.0.0.1:7890;https=127.0.0.1:7891'
Assert-True ((Resolve-ProxyUrl -Settings $settings) -eq 'http://127.0.0.1:7891') 'HTTPS proxy not selected'
$settings.ProxyServer = 'http=127.0.0.1:7890;ftp=127.0.0.1:7892'
Assert-True ($null -eq (Resolve-ProxyUrl -Settings $settings)) 'Ambiguous proxy should be unknown'
$settings.ProxyEnable = 0
Assert-True ($null -eq (Resolve-ProxyUrl -Settings $settings)) 'Disabled system proxy used'
Assert-True ((Resolve-ProxyUrl -Explicit 'socks5h://127.0.0.1:1080' -Settings $settings) -eq 'socks5h://127.0.0.1:1080') 'Explicit SOCKS proxy failed'
$ipv6Proxy = [uri](Resolve-ProxyUrl -Explicit 'http://[::1]:7890')
Assert-True ($ipv6Proxy.Port -eq 7890 -and [System.Net.IPAddress]::Parse($ipv6Proxy.DnsSafeHost).Equals([System.Net.IPAddress]::IPv6Loopback)) 'IPv6 proxy failed'
Assert-True (Test-IsLoopbackHost -HostName $ipv6Proxy.DnsSafeHost) 'IPv6 loopback proxy listener skipped'
Assert-True (-not (Test-IsLoopbackHost -HostName 'example.com')) 'Remote proxy misclassified as loopback'
foreach ($bad in @('garbage', 'file:///tmp/proxy', 'http://user:secret@localhost:7890', 'http://localhost:7890/path', 'http://localhost:7890/?token=secret')) {
    Assert-Rejected { Resolve-ProxyUrl -Explicit $bad } 'Unsafe proxy accepted'
}
Assert-True ($null -eq (ConvertTo-SafeUri 'https://chatgpt.com/?token=secret' @('https'))) 'Query accepted'
Assert-True ($null -eq (ConvertTo-SafeUri 'http://chatgpt.com/' @('https'))) 'HTTP endpoint accepted'
Assert-True ($null -eq (ConvertTo-SafeUri 'https://diagnostic.invalid/' @('https'))) 'Reserved bypass target accepted'
Assert-True ($null -eq (ConvertTo-SafeUri 'https://sub.diagnostic.invalid/' @('https'))) 'Reserved bypass subdomain accepted'
Assert-True ((ConvertTo-SafeUri 'https://example.com/remote' @('https')).DnsSafeHost -eq 'example.com') 'Custom endpoint host failed'

$direct = @(Get-EndpointProbeArguments -Url 'https://chatgpt.com/remote')
$proxy = @(Get-EndpointProbeArguments -Url 'https://chatgpt.com/remote' -Proxy 'http://127.0.0.1:7890')
Assert-True ($direct[0] -eq '-q') 'curlrc isolation must be the first argument'
Assert-True ($direct[([array]::IndexOf($direct, '--noproxy') + 1)] -eq '*') 'Direct mode can inherit a proxy'
Assert-True ($proxy[([array]::IndexOf($proxy, '--noproxy') + 1)] -eq 'diagnostic.invalid') 'Explicit proxy can inherit NO_PROXY'
Assert-True ($proxy[([array]::IndexOf($proxy, '--proxy') + 1)] -eq 'http://127.0.0.1:7890') 'Explicit proxy not passed'
Assert-True ($proxy[-2] -eq '--url') 'URL must be passed as an option value'
Assert-True (-not ($proxy -contains '--insecure')) 'TLS verification disabled'

$challenge = ConvertFrom-EndpointProbeOutput -Label 'direct' -ExitCode 0 -Lines @('HTTP/2 403', 'Cf-Mitigated: challenge', 'HTTP=403;TIME=0.01')
Assert-True $challenge.cloudflareChallenge 'Challenge not detected'
Assert-True ($challenge.result -eq 'HTTP=403;TIME=0.01') 'Probe result missing'
$ordinary = ConvertFrom-EndpointProbeOutput -Label 'proxy' -ExitCode 0 -Lines @('HTTP/2 403', 'HTTP=403;TIME=1.1')
Assert-True (-not $ordinary.cloudflareChallenge) 'Ordinary 403 misclassified'
$failure = ConvertFrom-EndpointProbeOutput -Label 'direct' -ExitCode 7 -Lines @('curl: (7) socks5://user:secret@localhost', 'HTTP=000;TIME=0.00')
Assert-True ($failure.exitCode -eq 7 -and $failure.result -like 'HTTP=000*') 'Failure evidence lost'
Assert-True (($failure | ConvertTo-Json) -notmatch 'secret|user:') 'Credential text leaked'
$missing = ConvertFrom-EndpointProbeOutput -Label 'direct' -ExitCode 28 -Lines @()
Assert-True ($missing.result -eq 'no HTTP response') 'Missing response misclassified'

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
$listener.Start()
$port = $listener.LocalEndpoint.Port
try {
    Assert-True (Test-LocalProxyListener -ComputerName '127.0.0.1' -Port $port) 'Open loopback listener not detected'
} finally { $listener.Stop() }
Assert-True (-not (Test-LocalProxyListener -ComputerName '127.0.0.1' -Port $port)) 'Closed loopback listener reported open'

Write-Output "Passed $script:checks diagnostic checks."

if ([Environment]::OSVersion.Platform -eq 'Win32NT') {
    $report = (& $scriptPath -SkipProbes) | ConvertFrom-Json
    Assert-True ($report.schemaVersion -eq 2 -and $report.probesSkipped) 'Windows JSON smoke test failed'
    Assert-True ($report.endpointHost -eq 'chatgpt.com' -and $report.probes.Count -eq 0) 'SkipProbes issued HTTP probes'
    Write-Output 'Windows diagnostic JSON smoke test passed.'
}
