Option Explicit
Dim shell, files, scriptPath, command, port, pattern
Set shell = CreateObject("WScript.Shell")
Set files = CreateObject("Scripting.FileSystemObject")
port = 7890
If WScript.Arguments.Count > 0 Then
    Set pattern = New RegExp
    pattern.Pattern = "^[0-9]{1,5}$"
    If WScript.Arguments.Count <> 1 Then WScript.Quit 1
    If Not pattern.Test(WScript.Arguments(0)) Then WScript.Quit 1
    port = CLng(WScript.Arguments(0))
    If port < 1 Or port > 65535 Then WScript.Quit 1
End If
scriptPath = files.BuildPath(files.GetParentFolderName(WScript.ScriptFullName), "Start-ChatGPT-With-Proxy.ps1")
command = """" & shell.ExpandEnvironmentStrings("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe") & """ -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & scriptPath & """"
shell.Run command & " -ProxyPort " & port, 0, False
