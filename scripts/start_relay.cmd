@echo off
chcp 65001 >nul
echo 正在启动 UDP 桥接守护...
echo.
echo ADB redir 检查:
adb -s emulator-5554 emu redir add udp:53318:53317 >nul 2>&1
adb -s emulator-5556 emu redir add udp:53319:53317 >nul 2>&1
adb -s FMR0224521005953 forward tcp:53320 tcp:53317 >nul 2>&1
echo   模拟器 redir: OK
echo.
echo 启动中继脚本 (隐藏窗口保持后台)...
wscript.exe "%~dpn0.vbs"
echo.
echo 已启动，PID 见中继日志文件
timeout /t 3 >nul
