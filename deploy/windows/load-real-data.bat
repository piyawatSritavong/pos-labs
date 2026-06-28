@echo off
REM ============================================================================
REM  Load real product data into the POS database
REM  - Runs seed-real-data.sql via psql (categories, units, parts, addresses)
REM  - Repairs any NULL columns left by older versions of this script
REM  - Grants cashier→addresses:read permission (idempotent)
REM  - Run this ONCE after start-pos.bat has been run for the first time
REM    (so the schema and core data already exist).
REM  - Safe to re-run — all INSERTs use ON CONFLICT DO NOTHING.
REM
REM  Requirements: psql.exe on PATH (comes with PostgreSQL install). If not on
REM  PATH, set PSQL_EXE below to the full path, e.g.
REM      set "PSQL_EXE=C:\Program Files\PostgreSQL\17\bin\psql.exe"
REM ============================================================================

set "APP_DIR=C:\POSApp"
set "DB_HOST=127.0.0.1"
set "DB_PORT=5432"
set "DB_USER=posuser"
set "DB_NAME=poslabs"
set "SQL_FILE=%APP_DIR%\seed-real-data.sql"
set "PSQL_EXE=psql"

REM Force UTF-8 so Thai characters in seed-real-data.sql are sent to the server
REM correctly. Without this, Windows Thai locale uses WIN874 and inserts fail.
set "PGCLIENTENCODING=UTF8"

echo.
echo === Load Real POS Data ===
echo SQL file        : %SQL_FILE%
echo Target          : %DB_NAME% @ %DB_HOST%:%DB_PORT% (user %DB_USER%)
echo PGCLIENTENCODING: %PGCLIENTENCODING%
echo.

if not exist "%SQL_FILE%" (
    echo [ERROR] %SQL_FILE% not found.
    echo         Make sure POSApp.zip was unzipped into %APP_DIR%.
    pause
    exit /b 1
)

REM Try psql on PATH first; if missing, probe common PostgreSQL install dirs.
where %PSQL_EXE% >nul 2>&1
if not errorlevel 1 goto :psql_ok

for %%V in (17 16 15 14 13 12) do (
    if exist "C:\Program Files\PostgreSQL\%%V\bin\psql.exe" (
        set "PSQL_EXE=C:\Program Files\PostgreSQL\%%V\bin\psql.exe"
        goto :psql_ok
    )
    if exist "C:\Program Files (x86)\PostgreSQL\%%V\bin\psql.exe" (
        set "PSQL_EXE=C:\Program Files (x86)\PostgreSQL\%%V\bin\psql.exe"
        goto :psql_ok
    )
)

echo [ERROR] psql.exe not found.
echo         Tried: PATH and C:\Program Files\PostgreSQL\{12..17}\bin\psql.exe
echo         If PostgreSQL is installed elsewhere, edit this file and set PSQL_EXE
echo         to the full path, e.g.
echo             set "PSQL_EXE=D:\PostgreSQL\17\bin\psql.exe"
pause
exit /b 1

:psql_ok
echo Using psql: %PSQL_EXE%
echo.

echo You will be prompted for the password of "%DB_USER%".
echo (Same password as in C:\POSApp\.env  ->  DB_PASSWORD)
echo.

echo --- Counts BEFORE load ---
"%PSQL_EXE%" -h %DB_HOST% -p %DB_PORT% -U %DB_USER% -d %DB_NAME% -t -A -c "SELECT 'parts: ' || count(*) FROM part_master UNION ALL SELECT 'addresses: ' || count(*) FROM address_master UNION ALL SELECT 'categories: ' || count(*) FROM category_master UNION ALL SELECT 'units: ' || count(*) FROM unit_master;"
if errorlevel 1 (
    echo.
    echo [ERROR] Cannot connect to the database. Check that:
    echo   - PostgreSQL service is running
    echo   - DB_USER "%DB_USER%" and DB_NAME "%DB_NAME%" exist
    echo   - The password you entered is correct (try psql manually to verify)
    pause
    exit /b 1
)

echo.
echo --- Running seed-real-data.sql ---
"%PSQL_EXE%" -h %DB_HOST% -p %DB_PORT% -U %DB_USER% -d %DB_NAME% -v ON_ERROR_STOP=1 -f "%SQL_FILE%"

if errorlevel 1 (
    echo.
    echo [ERROR] Loading seed data failed. Common causes:
    echo   - "invalid byte sequence for encoding"  ->  PGCLIENTENCODING not in effect
    echo   - Foreign key violation  ->  schema/core data missing (run start-pos.bat first)
    echo   - "permission denied"  ->  posuser lacks rights on poslabs DB
    echo.
    echo Re-run with verbose output:
    echo     "%PSQL_EXE%" -h %DB_HOST% -U %DB_USER% -d %DB_NAME% -v ON_ERROR_STOP=1 -f "%SQL_FILE%"
    pause
    exit /b 1
)

echo.
echo --- Counts AFTER load ---
"%PSQL_EXE%" -h %DB_HOST% -p %DB_PORT% -U %DB_USER% -d %DB_NAME% -t -A -c "SELECT 'parts: ' || count(*) FROM part_master UNION ALL SELECT 'addresses: ' || count(*) FROM address_master UNION ALL SELECT 'categories: ' || count(*) FROM category_master UNION ALL SELECT 'units: ' || count(*) FROM unit_master;"

echo.
echo [OK] seed-real-data.sql applied successfully.
echo      Expect: parts=1566, addresses=1566, categories=15, units=28
echo.
pause
