@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-WidgetProbe.ps1" %*
echo.
pause
