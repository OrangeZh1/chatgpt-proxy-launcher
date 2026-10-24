$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$detector = Join-Path $root 'Get-LocalProxy.ps1'
$installer = Join-Path $root 'Install.ps1'
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$testRoot = Join-Path $tempRoot ('chatgpt-proxy-detection-' + [Guid]::NewGuid().ToString('N'))
$savedEnvironment = @{}
foreach ($name in @('HTTPS_PROXY', 'HTTP_PROXY', 'ALL_PROXY')) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    [Environment]::SetEnvironmentVariable($name, $null, 'Process')
}
function Assert($condition, [string]$message) { if (-not $condition) { throw $message } }
function Get-ItemProperty { param($LiteralPath, $ErrorAction) return $proxySettings }
function Read-Host {
    param($Prompt)
    if ($null -eq $answer) { throw 'Unexpected interactive prompt during auto-detection' }
    return $answer
}

$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
try {
    $listener.Start()
    $port = $listener.LocalEndpoint.Port
    $script:proxySettings = [pscustomobject]@{ ProxyEnable = 1; ProxyServer = "127.0.0.1:$port" }
    $found = & $detector
    Assert ($found.Port -eq $port -and $found.Source -eq 'Windows system proxy') 'System proxy was not detected'
    $script:proxySettings.ProxyServer = "socks=127.0.0.1:9;http=localhost:$port;https=localhost:$port"
    Assert ((& $detector).Port -eq $port) 'Protocol-specific proxy format was not parsed'
    $script:proxySettings.ProxyEnable = 0
    $env:HTTPS_PROXY = "http://127.0.0.1:$port"
    Assert ((& $detector).Source -eq 'HTTPS_PROXY') 'Disabled system proxy did not fall back to environment'
    $script:proxySettings.ProxyEnable = 1
    Assert ((& $detector).Source -eq 'Windows system proxy') 'System proxy did not take priority'
    $script:proxySettings.ProxyEnable = 0
    $env:HTTPS_PROXY = 'http://127.0.0.1:0'
    $env:HTTP_PROXY = "http://localhost:$port"
    Assert ((& $detector).Source -eq 'HTTP_PROXY') 'Invalid candidate did not fall back to HTTP_PROXY'
    $env:HTTP_PROXY = $null
    foreach ($invalid in @("socks5://127.0.0.1:$port", "http://user:password@127.0.0.1:$port", 'http://192.0.2.1:7890', "http://127.0.0.1:$port/path")) {
        $env:HTTPS_PROXY = $invalid
        Assert ($null -eq (& $detector)) 'Unsupported proxy was accepted'
    }
    $env:HTTPS_PROXY = $null
    Assert ($null -eq (& $detector)) 'Missing proxy settings should not select a port'
    Write-Output 'PASS: system/environment priority, per-protocol parsing and unsupported proxies'

    $script:proxySettings = [pscustomobject]@{ ProxyEnable = 1; ProxyServer = "127.0.0.1:$port" }
    $script:answer = $null
    $destination = Join-Path $testRoot 'auto install'
    $desktop = Join-Path $testRoot 'auto desktop'
    & $installer -Interactive -Destination $destination -ShortcutDirectory $desktop | Out-Null
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut((Join-Path $desktop 'ChatGPT Proxy.lnk'))
    Assert ($link.Arguments.EndsWith(" $port")) 'Detected port was not saved to shortcut'
    $installedScript = Join-Path $destination 'Start-ChatGPT-With-Proxy.ps1'
    $hash = (Get-FileHash -LiteralPath $installedScript).Hash
    $script:answer = 'N'
    $cancelled = $false
    try { & $installer -Interactive -Destination $destination -ShortcutDirectory $desktop | Out-Null }
    catch { $cancelled = $true }
    Assert ($cancelled -and (Get-FileHash -LiteralPath $installedScript).Hash -eq $hash) 'Cancelled update modified files'
    $script:answer = 'Y'
    & $installer -Interactive -Destination $destination -ShortcutDirectory $desktop | Out-Null
    $script:proxySettings.ProxyEnable = 0
    $script:answer = '7897'
    & $installer -Interactive -Destination (Join-Path $testRoot 'manual') -ShortcutDirectory (Join-Path $testRoot 'manual desktop') | Out-Null
    $manual = $shell.CreateShortcut((Join-Path $testRoot 'manual desktop\ChatGPT Proxy.lnk'))
    Assert ($manual.Arguments.EndsWith(' 7897')) 'Manual fallback port was not saved'
    Write-Output 'PASS: automatic installation without prompting, update confirmation and manual fallback'

    $listener.Stop()
    $script:proxySettings.ProxyEnable = 1
    Assert ($null -eq (& $detector)) 'Closed configured port was accepted'
    Write-Output 'PASS: unreachable configured proxy was rejected'
} finally {
    $listener.Stop()
    foreach ($name in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process') }
    if (Test-Path -LiteralPath $testRoot) {
        $resolved = (Resolve-Path -LiteralPath $testRoot).Path
        if ($resolved -eq $testRoot -and $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolved -Recurse -Force
        } else { throw "Refusing to clean an unexpected path: $resolved" }
    }
}
