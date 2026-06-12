' UDP 桥接守护 — 用 VBScript 隐藏窗口启动 Python 中继
' 双击此文件或由 start_relay.cmd 调用

Dim objShell, objFSO, strScript, strLog, strPython

strPython = "D:\DevProjects\my\github\fr\scripts\udp_relay_v2.py"
strLog    = "D:\DevProjects\my\github\fr\scripts\relay_log.txt"

' 清理日志
Set objFSO = CreateObject("Scripting.FileSystemObject")
If objFSO.FileExists(strLog) Then objFSO.DeleteFile(strLog)

' 隐藏窗口启动 Python
Set objShell = CreateObject("WScript.Shell")
objShell.Run "cmd.exe /c python """ & strPython & """ > """ & strLog & """ 2>&1", 0, False

' 写入启动标记
Set objFSO = Nothing
Set objShell = Nothing
