param(
    [ValidateRange(1, 65535)][int]$ProxyPort = 7890,
    [string]$Destination = (Join-Path $env:LOCALAPPDATA 'ChatGPTProxyLauncher'),
    [string]$ShortcutDirectory = [Environment]::GetFolderPath('Desktop'),
    [switch]$Force,
    [switch]$Interactive
)

$ErrorActionPreference = 'Stop'
$detectedProxy = $null
if (-not $PSBoundParameters.ContainsKey('ProxyPort')) {
    $detectedProxy = & (Join-Path $PSScriptRoot 'Get-LocalProxy.ps1')
    if ($detectedProxy) {
        $ProxyPort = $detectedProxy.Port
        Write-Host "自动识别代理：http://127.0.0.1:${ProxyPort}（$($detectedProxy.Source)）" -ForegroundColor Cyan
    }
}
if ($Interactive) {
    Write-Host 'ChatGPT Proxy Launcher 安装' -ForegroundColor Cyan
    Write-Host '请先安装 ChatGPT/Codex，并准备本地 HTTP / mixed 代理。'
    if (-not $detectedProxy -and -not $PSBoundParameters.ContainsKey('ProxyPort')) {
        Write-Host '未识别到可连接的本地代理，请核对代理客户端的 HTTP / mixed 端口。'
        $portInput = Read-Host "代理端口（直接回车使用 $ProxyPort）"
        if (-not [string]::IsNullOrWhiteSpace($portInput)) {
            [int]$selectedPort = 0
            if (-not [int]::TryParse($portInput, [ref]$selectedPort) -or $selectedPort -lt 1 -or $selectedPort -gt 65535) {
                throw '端口必须是 1 到 65535 之间的整数。'
            }
            $ProxyPort = $selectedPort
        }
    }
}
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
if ($Interactive -and -not $Force -and @($targets | Where-Object { Test-Path -LiteralPath $_ }).Count -gt 0) {
    Write-Host "发现已有安装：$Destination"
    Write-Host '将替换两个启动脚本及 ChatGPT Proxy 桌面快捷方式，其他文件保留。'
    if ((Read-Host '确认更新请输入 Y；其他输入取消') -ne 'Y') { throw '安装已取消，未修改文件。' }
    $Force = $true
}
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
if ($Interactive) {
    Write-Host '安装完成。' -ForegroundColor Green
    Write-Host '请先开启代理，保存任务并完全退出 ChatGPT/Codex（包括托盘），再双击桌面 ChatGPT Proxy。'
    Write-Host '安装程序不会自动关闭或重启应用。'
}
