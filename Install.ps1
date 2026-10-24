param(
    [ValidateRange(1, 65535)][int]$ProxyPort = 7890,
    [string]$Destination = (Join-Path $env:LOCALAPPDATA 'ChatGPTProxyLauncher'),
    [string]$ShortcutDirectory = [Environment]::GetFolderPath('Desktop'),
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$Destination = [IO.Path]::GetFullPath($Destination)
$ShortcutDirectory = [IO.Path]::GetFullPath($ShortcutDirectory)
if ($Destination.TrimEnd('\') -eq $PSScriptRoot.TrimEnd('\')) {
    throw 'Choose an installation directory outside the source directory.'
}
$files = @('Start-ChatGPT-With-Proxy.ps1', 'Launch-ChatGPT.vbs')
$shortcutPath = Join-Path $ShortcutDirectory 'ChatGPT Proxy.lnk'
foreach ($name in $files) {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $name) -PathType Leaf)) {
        throw "Missing source file: $name"
    }
}
$targets = @($files | ForEach-Object { Join-Path $Destination $_ }) + @($shortcutPath)
foreach ($target in $targets) {
    if ((Test-Path -LiteralPath $target) -and -not $Force) {
        throw "Already exists: $target. Review the existing files, then use -Force to replace launcher files."
    }
}

New-Item -ItemType Directory -Path $Destination -Force | Out-Null
New-Item -ItemType Directory -Path $ShortcutDirectory -Force | Out-Null
foreach ($name in $files) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $Destination $name) -Force
}
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
$shortcut.Arguments = '//nologo "{0}" {1}' -f (Join-Path $Destination 'Launch-ChatGPT.vbs'), $ProxyPort
$shortcut.WorkingDirectory = $Destination
$shortcut.WindowStyle = 7
$shortcut.Description = "Start ChatGPT/Codex with the local HTTP proxy on port $ProxyPort."
$shortcut.IconLocation = (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') + ',0'
$shortcut.Save()
Write-Output "Installed: $Destination"
Write-Output "Shortcut: $shortcutPath"
Write-Output "Proxy: http://127.0.0.1:$ProxyPort"
