@echo off
REM ============================================================================
REM  POS Stop Script (Windows 10)
REM  - Stops pos-backend.exe (if running)
REM  - Closes Microsoft Edge kiosk window (optional, commented out)
REM  - Does NOT stop PostgreSQL by default (other apps may use it)
REM ============================================================================

set "BACKEND_EXE=pos-backend.exe"
set "PG_SERVICE_NAME=postgresql-x64-17"

echo.
echo === POS Stop ===
echo.

echo [1/2] Stopping %BACKEND_EXE% ...
tasklist /FI "IMAGENAME eq %BACKEND_EXE%" 2>nul | find /I "%BACKEND_EXE%" >nul
if errorlevel 1 (
    echo       (not running)
) else (
    taskkill /F /IM "%BACKEND_EXE%" /T >nul 2>&1
    if errorlevel 1 (
        echo       [WARN] Failed to stop %BACKEND_EXE%
    ) else (
        echo       Stopped.
    )
)

echo [2/2] Closing Edge kiosk ...
REM Uncomment the next line if you also want to close the Edge kiosk window.
REM Caution: this kills ALL msedge.exe processes, including normal browser windows.
REM taskkill /F /IM msedge.exe /T >nul 2>&1

REM Optional: also stop PostgreSQL service. Uncomment if this machine is dedicated to POS.
REM net stop "%PG_SERVICE_NAME%"

echo.
echo Done.
echo.
