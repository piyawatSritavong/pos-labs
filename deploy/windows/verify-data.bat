@echo off
REM ============================================================================
REM  Verify POS database state
REM  Shows counts of every key table + checks pos1 user + addresses:read perm.
REM  Safe to run anytime — read-only.
REM ============================================================================

set "DB_HOST=127.0.0.1"
set "DB_PORT=5432"
set "DB_USER=posuser"
set "DB_NAME=poslabs"
set "PSQL_EXE=psql"
set "PGCLIENTENCODING=UTF8"

echo.
echo === Verify POS Database State ===
echo Target: %DB_NAME% @ %DB_HOST%:%DB_PORT% (user %DB_USER%)
echo.

REM Locate psql.exe. Priority:
REM   1. PSQL_EXE as a full file path  ->  use `if exist`
REM   2. PSQL_EXE as a bare command name (e.g. "psql") on PATH  ->  use `where`
REM   3. Scan common PostgreSQL install dirs
REM NOTE: `where` cannot handle paths with spaces, so for full paths we MUST
REM use `if exist`. This is why the previous version failed even with a valid
REM `C:\Program Files\PostgreSQL\17\bin\psql.exe`.

if exist "%PSQL_EXE%" goto :psql_ok

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
echo         Current PSQL_EXE = %PSQL_EXE%
echo         Tried: PATH and C:\Program Files\PostgreSQL\{12..17}\bin\psql.exe
echo         Edit this file and set PSQL_EXE to the full path, e.g.
echo             set "PSQL_EXE=D:\PostgreSQL\17\bin\psql.exe"
pause
exit /b 1

:psql_ok
echo Using psql: %PSQL_EXE%
echo.

echo --- Row counts (expected after full deploy: parts=1566 addresses=1566 cats=15 units=28 users=2) ---
"%PSQL_EXE%" -h %DB_HOST% -p %DB_PORT% -U %DB_USER% -d %DB_NAME% -t -A -F " | " -c "SELECT rpad(t,18) || ': ' || count FROM (SELECT 'users' AS t, count(*) FROM \"user\" UNION ALL SELECT 'parts', count(*) FROM part_master UNION ALL SELECT 'addresses', count(*) FROM address_master UNION ALL SELECT 'categories', count(*) FROM category_master UNION ALL SELECT 'units', count(*) FROM unit_master UNION ALL SELECT 'permissions', count(*) FROM permission UNION ALL SELECT 'roles', count(*) FROM role UNION ALL SELECT 'role_permissions', count(*) FROM role_permission UNION ALL SELECT 'pos_devices', count(*) FROM pos_setting UNION ALL SELECT 'branches', count(*) FROM branch_setting) x ORDER BY t;"

echo.
echo --- pos1 user check ---
"%PSQL_EXE%" -h %DB_HOST% -p %DB_PORT% -U %DB_USER% -d %DB_NAME% -t -A -F " | " -c "SELECT username, role_id, is_active FROM \"user\" WHERE username = 'pos1';"

echo.
echo --- pos1 permissions check (should include parts.read AND addresses.read) ---
"%PSQL_EXE%" -h %DB_HOST% -p %DB_PORT% -U %DB_USER% -d %DB_NAME% -t -A -c "SELECT rp.permission_id FROM role_permission rp JOIN \"user\" u ON u.role_id = rp.role_id WHERE u.username = 'pos1' ORDER BY rp.permission_id;"

echo.
echo --- NULL / receipt-name counts (should ALL be 0 — non-zero = data needs repair; rerun load-real-data.bat) ---
"%PSQL_EXE%" -h %DB_HOST% -p %DB_PORT% -U %DB_USER% -d %DB_NAME% -t -A -F " | " -c "SELECT 'parts.bar_code NULL'  AS t, count(*) FROM part_master    WHERE bar_code IS NULL UNION ALL SELECT 'parts.receipt_name empty',   count(*) FROM part_master    WHERE COALESCE(receipt_name, '') = '' UNION ALL SELECT 'parts.receipt_name non ASCII', count(*) FROM part_master WHERE receipt_name !~ '^[ -~]*$' UNION ALL SELECT 'parts.details NULL',          count(*) FROM part_master    WHERE details  IS NULL UNION ALL SELECT 'parts.cost NULL',             count(*) FROM part_master    WHERE cost     IS NULL UNION ALL SELECT 'addresses.shelf NULL',        count(*) FROM address_master WHERE shelf    IS NULL UNION ALL SELECT 'addresses.max NULL',          count(*) FROM address_master WHERE \"max\"   IS NULL UNION ALL SELECT 'addresses.remarks NULL',      count(*) FROM address_master WHERE remarks  IS NULL ORDER BY t;"

echo.
echo --- Sellable stock check (zero ADDR rows should be 0 after rerun load-real-data.bat) ---
"%PSQL_EXE%" -h %DB_HOST% -p %DB_PORT% -U %DB_USER% -d %DB_NAME% -t -A -F " | " -c "SELECT 'ADDR rows with qty=0', count(*) FROM address_master WHERE code ~ '^ADDR[0-9]+$' AND store_id = 'main' AND COALESCE(qty, 0) = 0;"

echo.
echo --- POS device pos_secret (should be 'windows-pos-default-secret' if you use default build) ---
"%PSQL_EXE%" -h %DB_HOST% -p %DB_PORT% -U %DB_USER% -d %DB_NAME% -t -A -c "SELECT pos_id || ' = ' || pos_secret FROM pos_setting;"

echo.
pause
