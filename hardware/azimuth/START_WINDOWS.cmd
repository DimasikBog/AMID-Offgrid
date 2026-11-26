@echo off
setlocal
cd /d "%~dp0"
if not exist ".venv\Scripts\python.exe" goto missing
".venv\Scripts\python.exe" launcher.py
pause
exit /b
:missing
echo Run SETUP_WINDOWS.cmd first.
pause
exit /b 1
