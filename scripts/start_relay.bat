@echo off
chcp 65001 >nul
echo ====================================
echo   UDP 中继 - 桥接两台 Android 模拟器
echo ====================================
echo.
echo 确保 ADB redir 已设置:
echo   adb -s emulator-5554 emu redir add udp:53318:53317
echo   adb -s emulator-5556 emu redir add udp:53319:53317
echo.
echo 本窗口必须保持打开，关闭即停止中继
echo ====================================
echo.

python "%~dp0udp_relay_v2.py"
pause
