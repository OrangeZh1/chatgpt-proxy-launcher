param([switch]$CheckOnly, [switch]$InsidePackage, [int]$ProxyPort = 7890)

$ErrorActionPreference = 'Stop'

try {
    if ($ProxyPort -lt 1 -or $ProxyPort -gt 65535) { throw 'ProxyPort must be between 1 and 65535.' }
    Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class ChatGPTPackageIdentity {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetCurrentPackageFullName(ref uint length, StringBuilder name);
}
"@

    $env:HTTP_PROXY  = "http://127.0.0.1:$ProxyPort"
    $env:HTTPS_PROXY = $env:HTTP_PROXY
    $env:ALL_PROXY   = $env:HTTP_PROXY
    $env:NO_PROXY    = 'localhost,127.0.0.1,::1'

    $codexPackage = Get-AppxPackage -Name OpenAI.Codex | Select-Object -First 1
    if (-not $codexPackage) { throw 'ChatGPT/Codex is not installed for this Windows user.' }
    $codexExe = Join-Path $codexPackage.InstallLocation 'app\ChatGPT.exe'
    if (-not (Test-Path -LiteralPath $codexExe)) { throw 'ChatGPT.exe was not found in the installed package.' }

    [xml]$manifest = Get-Content -LiteralPath (Join-Path $codexPackage.InstallLocation 'AppxManifest.xml')
    $appEntry = @($manifest.Package.Applications.Application | Where-Object {
        ($_.Executable -replace '/', '\') -eq 'app\ChatGPT.exe'
    })
    if ($appEntry.Count -ne 1) { throw 'Could not identify the ChatGPT application entry in its package.' }
    if ($appEntry[0].EntryPoint -ne 'Windows.FullTrustApplication') {
        throw 'The app no longer uses a full-trust desktop entry point. This launcher needs to be updated.'
    }

    [uint32]$identityLength = 0
    $identityResult = [ChatGPTPackageIdentity]::GetCurrentPackageFullName([ref]$identityLength, $null)
    $currentPackage = $null
    if ($identityResult -eq 122) {
        $identityBuffer = New-Object System.Text.StringBuilder ([int]$identityLength)
        $identityResult = [ChatGPTPackageIdentity]::GetCurrentPackageFullName([ref]$identityLength, $identityBuffer)
        if ($identityResult -eq 0) { $currentPackage = $identityBuffer.ToString() }
    }
    if ($InsidePackage -and $currentPackage -ne $codexPackage.PackageFullName) {
        throw 'Package identity verification failed. ChatGPT was not started.'
    }
    if (-not $InsidePackage) {
        Get-Command Invoke-CommandInDesktopPackage -ErrorAction Stop | Out-Null
    }

    $proxyConnection = New-Object System.Net.Sockets.TcpClient
    try {
        $connectTask = $proxyConnection.ConnectAsync('127.0.0.1', $ProxyPort)
        if (-not $connectTask.Wait(2000) -or -not $proxyConnection.Connected) {
            throw 'The proxy connection timed out.'
        }
    } catch {
        throw "Cannot connect to the proxy at 127.0.0.1:$ProxyPort. Start your proxy client and check its HTTP/mixed port."
    } finally {
        $proxyConnection.Dispose()
    }

    $alreadyRunning = @(Get-Process -Name ChatGPT -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -eq $codexExe }).Count -gt 0

    if ($CheckOnly) {
        [ordered]@{
            executable = $codexExe
            app_running = $alreadyRunning
            proxy_reachable = $true
            launch_method = 'windows_package_context'
            expected_package = $codexPackage.PackageFullName
            current_package = $currentPackage
            inside_package = [bool]$InsidePackage
            application_id = [string]$appEntry[0].Id
            environment = @{
                HTTP_PROXY = $env:HTTP_PROXY
                HTTPS_PROXY = $env:HTTPS_PROXY
                ALL_PROXY = $env:ALL_PROXY
                NO_PROXY = $env:NO_PROXY
            }
        } | ConvertTo-Json -Depth 3 -Compress
        exit 0
    }

    if ($alreadyRunning) {
        throw 'ChatGPT is already running. Finish active tasks, fully exit ChatGPT (including the tray), then run this shortcut again.'
    }

    if ($InsidePackage) {
        Start-Process -FilePath $codexExe -WorkingDirectory (Split-Path -Parent $codexExe) -WindowStyle Normal
    } else {
        $powershellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $packageArguments = '-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -InsidePackage -ProxyPort {1}' -f $PSCommandPath, $ProxyPort
        Invoke-CommandInDesktopPackage -PackageFamilyName $codexPackage.PackageFamilyName -AppId ([string]$appEntry[0].Id) -Command $powershellExe -Args $packageArguments -PreventBreakaway
    }
} catch {
    if ($CheckOnly) { throw }
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show($_.Exception.Message, 'ChatGPT proxy launcher') | Out-Null
    exit 1
}
