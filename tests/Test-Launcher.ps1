$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$launcher = Join-Path $root 'Start-ChatGPT-With-Proxy.ps1'
$installer = Join-Path $root 'Install.ps1'
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$testRoot = Join-Path $tempRoot ('chatgpt-launcher-test-' + [Guid]::NewGuid().ToString('N'))
$listener = $null

function Assert($condition, [string]$message) {
    if (-not $condition) { throw $message }
}

function Run-Check([int]$port, [bool]$expectSuccess) {
    # Capture native errors without Windows PowerShell turning stderr into a terminating error.
    $savedPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $result = & $powershell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $launcher -CheckOnly -ProxyPort $port 2>&1
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $savedPreference }
    Assert (($code -eq 0) -eq $expectSuccess) "Unexpected exit code $code for port $port`: $result"
    return ($result | Out-String)
}

try {
    foreach ($file in Get-ChildItem -LiteralPath $root -Filter '*.ps1' -Recurse) {
        $tokens = $null
        $parseErrors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
        Assert ($parseErrors.Count -eq 0) "Syntax errors in $($file.Name): $parseErrors"
    }
    Write-Output 'PASS: PowerShell syntax'

    $badPort = Run-Check 0 $false
    Assert ($badPort -match 'ProxyPort must be between') 'Missing invalid-port diagnostic'
    $badPort = Run-Check 65536 $false
    Assert ($badPort -match 'ProxyPort must be between') 'Missing upper-bound diagnostic'

    # A TCP listener checks the launcher's reachability contract, not proxy functionality.
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = $listener.LocalEndpoint.Port
    $originalProxy = $env:HTTP_PROXY
    $check = (Run-Check $port $true) | ConvertFrom-Json
    Assert $check.proxy_reachable 'Proxy reachability was not reported'
    Assert ($check.application_id -and $check.expected_package) 'Missing package information'
    foreach ($name in @('HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY')) {
        Assert ($check.environment.$name -eq "http://127.0.0.1:$port") "Incorrect $name"
    }
    Assert ($check.environment.NO_PROXY -eq 'localhost,127.0.0.1,::1') 'Incorrect local bypass list'
    Assert ($env:HTTP_PROXY -eq $originalProxy) 'Parent environment was changed'
    $listener.Stop()
    $listener = $null
    $closedPort = Run-Check $port $false
    Assert ($closedPort -match 'Cannot connect to the proxy') 'Missing closed-port diagnostic'
    Write-Output 'PASS: package inspection, proxy variables, valid/invalid/closed ports'

    $destination = Join-Path $testRoot 'install with spaces'
    $desktop = Join-Path $testRoot 'desktop with spaces'
    & $installer -Destination $destination -ShortcutDirectory $desktop -ProxyPort 7897 | Out-Null
    foreach ($name in @('Start-ChatGPT-With-Proxy.ps1', 'Launch-ChatGPT.vbs')) {
        Assert ((Get-FileHash -LiteralPath (Join-Path $root $name)).Hash -eq (Get-FileHash -LiteralPath (Join-Path $destination $name)).Hash) "Copy mismatch: $name"
    }
    $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $desktop 'ChatGPT Proxy.lnk'))
    Assert ($shortcut.TargetPath -eq (Join-Path $env:SystemRoot 'System32\wscript.exe')) 'Incorrect shortcut target'
    Assert ($shortcut.Arguments -eq ('//nologo "{0}" 7897' -f (Join-Path $destination 'Launch-ChatGPT.vbs'))) 'Incorrect shortcut arguments'
    Assert ($shortcut.WorkingDirectory -eq $destination) 'Incorrect working directory'
    Assert ((Test-Path -LiteralPath ($shortcut.IconLocation -replace ',0$', ''))) 'Missing system icon'
    $blocked = $false
    try { & $installer -Destination $destination -ShortcutDirectory $desktop | Out-Null }
    catch { $blocked = $_.Exception.Message -like 'Already exists:*' }
    Assert $blocked 'Installer overwrote an existing installation without -Force'
    $retainedFile = Join-Path $destination 'user-note.txt'
    Set-Content -LiteralPath $retainedFile -Value 'keep'
    & $installer -Destination $destination -ShortcutDirectory $desktop -ProxyPort 7897 -Force | Out-Null
    Assert ((Get-Content -LiteralPath $retainedFile) -eq 'keep') 'Installer modified an unrelated file'
    Write-Output 'PASS: temporary installation, shortcut, overwrite protection and scoped update'

    # Replace ONLY the temporary launcher with a harmless probe before exercising VBS.
    $probe = 'param([int]$ProxyPort); [IO.File]::WriteAllText((Join-Path $PSScriptRoot "port.txt"), [string]$ProxyPort)'
    [IO.File]::WriteAllText((Join-Path $destination 'Start-ChatGPT-With-Proxy.ps1'), $probe)
    $vbs = Join-Path $destination 'Launch-ChatGPT.vbs'
    & (Join-Path $env:SystemRoot 'System32\cscript.exe') //nologo $vbs 'not-a-port'
    Assert ($LASTEXITCODE -ne 0) 'VBS accepted an invalid argument'
    & (Join-Path $env:SystemRoot 'System32\cscript.exe') //nologo $vbs 7897
    Assert ($LASTEXITCODE -eq 0) 'VBS failed to start the harmless probe'
    $portFile = Join-Path $destination 'port.txt'
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath $portFile) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
    Assert ((Get-Content -LiteralPath $portFile) -eq '7897') 'VBS failed to forward the port'
    Write-Output 'PASS: VBS argument validation and forwarding with spaces in paths'
    Write-Output 'All checks passed. No real application or WSL process was started or stopped.'
} finally {
    if ($listener) { $listener.Stop() }
    # Only remove this run's unique temporary tree, after verifying the resolved boundary.
    if (Test-Path -LiteralPath $testRoot) {
        $resolved = (Resolve-Path -LiteralPath $testRoot).Path
        if ($resolved -eq $testRoot -and $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolved -Recurse -Force
        } else { throw "Refusing to clean an unexpected path: $resolved" }
    }
}
