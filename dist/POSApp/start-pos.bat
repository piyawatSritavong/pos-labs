@echo off
REM ============================================================================
REM  POS Auto-Start Script (Windows 10)
REM  - Ensures PostgreSQL service is running (with admin-friendly fallback)
REM  - Starts pos-backend.exe hidden/background, redirecting stdout+stderr to logs\backend.log
REM  - Opens Edge kiosk on main monitor (login URL pre-fills "pos1" username)
REM  - If a 2nd monitor is detected, opens another Edge kiosk on it for customer
REM    display (route /#/customer) — separate user-data-dir so Edge allows two kiosks
REM
REM  Secrets (DB password, session secret, POS_SECRET) live in %APP_DIR%\.env.
REM ============================================================================

REM ---- Configurable variables (edit if your setup differs) -------------------
set "APP_DIR=C:\POSApp"
set "PG_SERVICE_NAME=postgresql-x64-17"
set "BACKEND_URL=http://127.0.0.1:8080"
set "BACKEND_EXE=pos-backend.exe"
set "LOGIN_USERNAME=pos1"
REM x-coord ของจอ 2 (override ตามจริง — ถ้าจอ 2 อยู่ด้านขวาของจอ 1 ส่วนใหญ่ค่าจะเท่ากับความกว้างของจอ 1)
set "CUSTOMER_MONITOR_X=2000"
REM ---------------------------------------------------------------------------

echo.
echo === POS Auto-Start ===
echo APP_DIR          : %APP_DIR%
echo PG_SERVICE_NAME  : %PG_SERVICE_NAME%
echo BACKEND_URL      : %BACKEND_URL%
echo LOGIN_USERNAME   : %LOGIN_USERNAME%
echo CUSTOMER_MONITOR_X: %CUSTOMER_MONITOR_X%
echo.

cd /d "%APP_DIR%"
if errorlevel 1 (
    echo [ERROR] Cannot cd into %APP_DIR%. Is POSApp installed there?
    pause
    exit /b 1
)

echo [1/5] Checking PostgreSQL service "%PG_SERVICE_NAME%" ...

REM Step A: does the service exist?
sc query "%PG_SERVICE_NAME%" >nul 2>&1
if errorlevel 1 (
    echo       [WARN] Service "%PG_SERVICE_NAME%" not found.
    echo              Open services.msc, find the postgresql-x64-* service,
    echo              and update PG_SERVICE_NAME at the top of this file.
    goto :after_pg
)

REM Step B: is it already running?
sc query "%PG_SERVICE_NAME%" | findstr /I /C:"STATE" | findstr /I /C:"RUNNING" >nul 2>&1
if not errorlevel 1 (
    echo       Already running.
    goto :after_pg
)

REM Step C: not running — try to start it.
echo       Service is not running. Attempting "net start" ...
net start "%PG_SERVICE_NAME%" >nul 2>&1
if errorlevel 1 (
    echo       [WARN] Could not start the service (access denied?).
    echo              Either:
    echo              - Right-click start-pos.bat then "Run as administrator", OR
    echo              - Open services.msc, set Startup type to "Automatic" so it
    echo                starts at boot without needing admin here.
) else (
    echo       Started.
)
:after_pg

echo [2/5] Ensuring logs folder exists ...
if not exist "%APP_DIR%\logs" mkdir "%APP_DIR%\logs"
echo. >> "%APP_DIR%\logs\backend.log"
echo === Backend start: %DATE% %TIME% === >> "%APP_DIR%\logs\backend.log"

echo [3/5] Starting backend "%BACKEND_EXE%" (hidden/background, logs ^> logs\backend.log) ...
REM Run through WScript so no backend terminal window is shown on the POS screen.
REM To stop it later, use stop-pos.bat or: taskkill /F /IM %BACKEND_EXE% /T
if not exist "%APP_DIR%\start-backend-hidden.vbs" (
    echo       [ERROR] Missing %APP_DIR%\start-backend-hidden.vbs
    echo              Re-copy the full POSApp deploy folder.
    pause
    exit /b 1
)
wscript.exe "%APP_DIR%\start-backend-hidden.vbs" "%APP_DIR%" "%BACKEND_EXE%" "%APP_DIR%\logs\backend.log"

echo       Waiting 5 seconds for backend to come up ...
timeout /t 5 /nobreak >nul

echo [4/5] Opening Microsoft Edge kiosk (main POS) at %BACKEND_URL% (prefill username=%LOGIN_USERNAME%) ...
start "" msedge.exe --kiosk "%BACKEND_URL%/?username=%LOGIN_USERNAME%" --edge-kiosk-type=fullscreen --no-first-run --disable-features=TranslateUI

echo [5/5] Detecting monitors ...
set "MONITOR_COUNT=1"
for /f "tokens=*" %%i in ('powershell -NoProfile -Command "try { Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.Screen]::AllScreens.Count } catch { 1 }"') do set "MONITOR_COUNT=%%i"
echo       Detected %MONITOR_COUNT% monitor(s).

if %MONITOR_COUNT% GEQ 2 (
    echo       Opening customer display kiosk on monitor 2 at x=%CUSTOMER_MONITOR_X% ...
    REM ใช้ --user-data-dir แยก เพราะ Edge ไม่ยอม run 2 kiosk บน profile เดียวกัน
    start "POS Customer Display" msedge.exe --kiosk "%BACKEND_URL%/#/customer" --window-position=%CUSTOMER_MONITOR_X%,0 --edge-kiosk-type=fullscreen --no-first-run --disable-features=TranslateUI --user-data-dir="%LOCALAPPDATA%\POSCustomerEdge"
) else (
    echo       Single-monitor setup — skipping customer display kiosk.
    echo       (Cashier can still click "หน้าจอลูกค้า" button to open popup.)
)

echo.
echo POS is starting. Logs: %APP_DIR%\logs\backend.log
echo To stop later, run stop-pos.bat
echo.
