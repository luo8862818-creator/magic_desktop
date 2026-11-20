@echo off
setlocal
cd /d "%~dp0"
chcp 65001 >nul

set "GODOT_EXE="
for %%F in ("%CD%\tools\godot\Godot*.exe") do (
    if exist "%%~fF" (
        echo %%~nxF | findstr /i "_console.exe" >nul
        if errorlevel 1 set "GODOT_EXE=%%~fF"
    )
)

if not defined GODOT_EXE (
    echo [ERROR] Godot GUI executable not found.
    echo Put Godot 4.x Windows GUI exe in tools\godot\
    pause
    exit /b 1
)

echo [INFO] Using: "%GODOT_EXE%"
echo [INFO] Checking project and GDScript parsing...
"%GODOT_EXE%" --headless --path "%CD%\engine" --editor --quit

if errorlevel 1 (
    echo.
    echo [ERROR] Godot validation failed. Review the messages above.
    pause
    exit /b 1
)

echo.
echo [OK] Godot project loaded without reported parse errors.
pause
