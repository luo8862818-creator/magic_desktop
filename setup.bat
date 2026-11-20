@echo off
setlocal
cd /d "%~dp0"
chcp 65001 >nul

echo ==========================================
echo   Magic Desktop - Environment Setup
echo ==========================================

where py >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Python Launcher was not found.
    echo Install Python 3.11 or newer and enable "Add Python to PATH".
    pause
    exit /b 1
)

if not exist ".venv\Scripts\python.exe" (
    echo [INFO] Creating virtual environment...
    py -3 -m venv .venv
    if errorlevel 1 (
        echo [ERROR] Failed to create virtual environment.
        pause
        exit /b 1
    )
)

echo [INFO] Installing dependencies...
".venv\Scripts\python.exe" -m pip install --upgrade pip
if errorlevel 1 (
    echo [ERROR] pip upgrade failed.
    pause
    exit /b 1
)

".venv\Scripts\python.exe" -m pip install -r requirements.txt
if errorlevel 1 (
    echo [ERROR] Dependency installation failed.
    pause
    exit /b 1
)

echo.
echo [SUCCESS] Setup completed.
echo Run start.bat to open Magic Desktop.
pause
