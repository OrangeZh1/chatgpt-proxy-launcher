@echo off
setlocal
title ChatGPT Proxy Launcher Setup
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1" -Interactive %*
set "install_exit=%errorlevel%"
if not "%install_exit%"=="0" echo Installation failed or was cancelled. See the message above.
echo.
pause
exit /b %install_exit%
