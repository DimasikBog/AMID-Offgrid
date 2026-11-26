@echo off
setlocal
cd /d "%~dp0"
py -3 -m venv .venv
if errorlevel 1 goto failed
".venv\Scripts\python.exe" -m pip install -r requirements.txt
if errorlevel 1 goto failed
echo Setup complete. Run START_WINDOWS.cmd
pause
exit /b 0
:failed
echo Setup failed. Install Python 3.10 or newer with the Windows Python launcher. Internet is needed for dependencies.
pause
exit /b 1
