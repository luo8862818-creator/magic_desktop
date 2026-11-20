@echo off
setlocal
cd /d "%~dp0"
chcp 65001 >nul

if not exist ".venv\Scripts\python.exe" (
    echo [INFO] Virtual environment not found. Run setup.bat first.
    pause
    exit /b 1
)

".venv\Scripts\python.exe" -m app.main
if errorlevel 1 (
    echo.
    echo [ERROR] Magic Desktop exited with an error.
    echo Check logs\app.log
    pause
)
