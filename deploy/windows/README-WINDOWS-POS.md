# POS – Windows 10 Deployment (No Docker)

This guide shows how to install and run the POS system on a Windows 10 POS machine
using a native PostgreSQL, a single Go binary, and Flutter Web served by that binary.

> **Build target:** `dist/POSApp/` produced on a macOS dev machine by
> `scripts/build-pos-windows.sh`. Copy that folder to `C:\POSApp` on the POS PC.

---

## 1. What's in the package

After running `scripts/build-pos-windows.sh` on macOS, you get `dist/POSApp/`:

```
dist/POSApp/
├── pos-backend.exe         # Go backend, Windows x64, statically linked
├── start-pos.bat           # Starts PostgreSQL, backend, Edge kiosk(s)
├── stop-pos.bat            # Stops backend (PG left running)
├── load-real-data.bat      # Helper to import 1,566 products into the DB
├── verify-data.bat         # Diagnostic — print counts of every key table
├── seed-real-data.sql      # The actual SQL script (run via psql)
├── seed-real-data.down.sql # Rollback for the seed (advanced)
├── .env.example            # Template — rename to .env and edit
├── logs/                   # Backend stdout/stderr → logs/backend.log
├── migrations/             # SQL schema migrations auto-run by backend on startup
└── static/                 # Flutter Web release build (Go serves these)
    ├── index.html
    ├── main.dart.js
    ├── flutter_bootstrap.js
    └── assets/...
```

## 1.1 How the data gets into the database

There are **two phases** of data loading on a fresh install:

| Phase | What happens | Who triggers it |
|---|---|---|
| **Phase 1 — Auto on first start** | Backend runs migrations (creates all tables) → then `SeedCoreData` inserts **permissions, roles, admin user, `pos1` user, units (7 default), default store, company, branch `00000`, POS device `POS001`** | `start-pos.bat` (automatic) |
| **Phase 2 — Manual once** | Run `load-real-data.bat` (which calls `psql -f seed-real-data.sql`) — adds **15 categories, 21 Thai units, 1,566 products, 1,566 inventory addresses** | You, after Phase 1 succeeds |

After both phases, you can log in with `pos1`/`pos123456` and see all products.

**Important:** Phase 2 must run **after** Phase 1 — the SQL script needs the schema and core data to already exist (it references roles/branches that Phase 1 creates).

## 1.2 Default credentials

| Username | Password   | Role            | Notes                                |
|----------|------------|-----------------|--------------------------------------|
| `pos1`   | `pos123456`| cashier         | Created by Phase 1. Used at POS UI.  |
| `admin`  | `admin123` | superuser admin | Created by Phase 1. For backoffice. **Change ASAP.** |

`start-pos.bat` opens the Edge kiosk with `?username=pos1` — login screen pre-fills the username so the cashier only needs to type the password.

The backend serves:
- **API** at the existing routes (`/auth`, `/parts`, `/bills`, ...)
- **Flutter Web** for everything else (with SPA fallback to `index.html`)

Both share `http://127.0.0.1:8080` — same origin → no CORS issues.

---

## 2. Prerequisites on the Windows 10 POS machine

- Windows 10 x64 (with recent updates so Edge supports `--edge-kiosk-type`)
- Microsoft Edge (preinstalled on Win10/11)
- Local administrator rights for first-time install
- About 200 MB free disk space

---

## 3. Step 1 — Install PostgreSQL 17 (native)

1. Download the EnterpriseDB Windows installer:
   https://www.postgresql.org/download/windows/ → "Download the installer"
2. Run the installer **as Administrator**.
3. During install:
   - Keep the default install path
   - **Remember the postgres superuser password** you set
   - Keep the default port `5432`
   - Make sure "Install as a Windows service" is **checked** (default)
4. After install, verify the service is running:
   - Open `services.msc`
   - Find `postgresql-x64-17` → status should be **Running**

> If the service is named differently (e.g. `postgresql-x64-16`), edit
> `start-pos.bat` and update `PG_SERVICE_NAME` near the top.

---

## 4. Step 2 — Create the POS database and user

Open **SQL Shell (psql)** from the Start menu (installed with PostgreSQL).
Press Enter to accept defaults until it asks for the postgres password, then run:

```sql
CREATE USER posuser WITH PASSWORD 'CHANGE_ME_STRONG_PASSWORD';
CREATE DATABASE poslabs OWNER posuser;
GRANT ALL PRIVILEGES ON DATABASE poslabs TO posuser;
```

Use the same password you'll put into `.env` below.

> **Schema migrations run automatically.** The backend calls `golang-migrate` on
> startup, reading SQL files from `C:\POSApp\migrations\` (shipped in the build).
> You do not need to run them by hand — just make sure the database `poslabs`
> exists and `posuser` owns it.

---

## 5. Step 3 — Copy POSApp to C:\POSApp

1. On the macOS dev machine: `cd dist && zip -r POSApp.zip POSApp/`
2. Transfer `POSApp.zip` to the Windows machine (USB, network share, etc.)
3. On Windows: extract so that `C:\POSApp\pos-backend.exe` exists.

If you choose a different folder, edit `APP_DIR` near the top of `start-pos.bat`.

---

## 6. Step 4 — Configure .env

In `C:\POSApp\`:

1. Rename `.env.example` → `.env`
2. Open `.env` in Notepad and edit:
   - `DB_PASSWORD=` → the password you used in `CREATE USER posuser`
   - `SESSION_SECRET=` → a long random string (32+ chars)
   - `POS_SECRET=` → leave as `windows-pos-default-secret` for the default build, OR
     pick a custom value (must match the Flutter build — see Section 14 below)
   - Leave other values unless you have a reason to change them

`.env` is read by the backend at startup. **Do not commit it to git.**

---

## 6.5 Step 4.5 — Load real product data (Phase 2)

After Step 5 below works (backend has started at least once), come back here
and load the 1,566 products from the spreadsheet:

**Option A — easy way (recommended):**
Double-click `C:\POSApp\load-real-data.bat` — it will prompt for `posuser`'s
password (same as `DB_PASSWORD` in `.env`) and run the SQL automatically.

**Option B — manual psql:**

Open Command Prompt and run:

```
"C:\Program Files\PostgreSQL\17\bin\psql.exe" -h 127.0.0.1 -U posuser -d poslabs -f C:\POSApp\seed-real-data.sql
```

(If `psql` is on PATH from the PostgreSQL installer, just `psql` works.)

You should see ~5 `INSERT 0 …` lines and a final `UPDATE 1`. The script is safe
to re-run — every INSERT uses `ON CONFLICT DO NOTHING`.

After this, the Flutter Web UI shows real products in `parts/search`, `bills`,
etc. The Edge kiosk that started in Step 5 just needs a refresh (Ctrl+R if you
can exit kiosk, or restart with `stop-pos.bat` + `start-pos.bat`).

---

## 7. Step 5 — Test by double-clicking start-pos.bat

Double-click `C:\POSApp\start-pos.bat`. You should see:

```
=== POS Auto-Start ===
[1/5] Checking PostgreSQL service "postgresql-x64-17" ...
[2/5] Ensuring logs folder exists ...
[3/5] Starting backend "pos-backend.exe" (hidden/background, logs to logs\backend.log) ...
[4/5] Opening Microsoft Edge kiosk (main POS) at http://127.0.0.1:8080 ...
[5/5] Detecting monitors ...
```

Edge should open in fullscreen kiosk on the POS UI within ~5 seconds.
The Go backend runs in the background with no terminal window. To stop it,
run `stop-pos.bat` or kill it manually:

```cmd
taskkill /F /IM pos-backend.exe /T
```

> To exit kiosk for debugging: `Ctrl+Alt+Del` → close Edge from Task Manager,
> or run `stop-pos.bat`.

---

## 8. Step 6 — Open manually in a regular browser

To test the API or use DevTools, open a regular Edge window and navigate to:

```
http://127.0.0.1:8080
```

API endpoints work at the same origin: e.g. `http://127.0.0.1:8080/health`
should return JSON.

---

## 9. Step 7 — Register auto-start with Task Scheduler

Run **once** as Administrator in an elevated Command Prompt:

```
schtasks /Create /TN "POS Auto Start" /TR "C:\POSApp\start-pos.bat" /SC ONLOGON /RL HIGHEST /F
```

This makes `start-pos.bat` run automatically whenever the POS user logs into Windows.

---

## 10. Remove auto-start

```
schtasks /Delete /TN "POS Auto Start" /F
```

---

## 11. Verify / change PostgreSQL service name

1. Press `Win+R`, type `services.msc`, Enter.
2. Scroll to `postgresql-x64-*`. The exact name depends on the major version.
3. If it's not `postgresql-x64-17`, edit `C:\POSApp\start-pos.bat` and update
   `PG_SERVICE_NAME` to match.

You can also check from the command line:

```
sc query state= all | findstr /I postgresql
```

### About `net start` and admin rights

`net start` requires administrator rights to start a stopped service.
Two ways to handle this on the POS machine — pick one:

**Option A (recommended): set the service to start automatically at boot.**
Open `services.msc` → right-click `postgresql-x64-17` → Properties →
"Startup type" → **Automatic**. After the next reboot the service is already
running, and `start-pos.bat` only needs to verify (no admin required).

**Option B: run `start-pos.bat` as administrator.**
Right-click `start-pos.bat` → "Run as administrator". If you registered it
with Task Scheduler (Step 7), the `/RL HIGHEST` flag already runs it elevated.

`start-pos.bat` uses `sc query` (no admin required) to check the service first
and only falls through to `net start` when stopping. If `net start` is denied,
the script prints a clear warning and continues — the backend will then fail
to reach the DB and you'll see it in `logs\backend.log`.

---

## 12. Troubleshooting

### Backend does not start

- Open `C:\POSApp\logs\backend.log` in Notepad — look for the last error.
- Check that port 8080 is free:
  ```
  netstat -ano | findstr :8080
  ```
  If something else holds it, change `PORT=` in `.env` and `BACKEND_URL` in
  `start-pos.bat`.
- Run `pos-backend.exe` directly from a Command Prompt (not via `.bat`) to see
  errors in the foreground:
  ```
  cd C:\POSApp
  pos-backend.exe
  ```
- Normal `start-pos.bat` startup intentionally runs the backend through
  `start-backend-hidden.vbs`, so there is no visible backend terminal. Check
  `logs\backend.log` or Task Manager (`pos-backend.exe`) instead.

### Database connection fails

- Verify the PostgreSQL service is running: `sc query postgresql-x64-17`
- Verify port 5432 is listening: `netstat -ano | findstr :5432`
- Verify credentials by connecting manually:
  ```
  psql -U posuser -d poslabs -h 127.0.0.1
  ```
  If `psql` is not on PATH, use the full path from the PostgreSQL install,
  e.g. `"C:\Program Files\PostgreSQL\17\bin\psql.exe"`.
- Check `DB_PASSWORD` in `.env` matches what you used in `CREATE USER`.

### Flutter Web page is blank

- Confirm `C:\POSApp\static\index.html` exists.
- Confirm `STATIC_FILES_PATH=static` in `.env` (relative to `C:\POSApp`).
- Open a non-kiosk Edge window: `http://127.0.0.1:8080`, press `F12`, look at
  the **Console** and **Network** tabs:
  - 200s for `main.dart.js`, `flutter_bootstrap.js` → static serving is fine.
  - 404s on `/auth/...` → backend probably failed; check `logs\backend.log`.
- Clear Edge cache (`Ctrl+Shift+Delete`) if you redeployed a new build but the
  old one is still cached.

### Backend logs

- `C:\POSApp\logs\backend.log` (appended on every start). Truncate it if it
  grows large:
  ```
  echo. > C:\POSApp\logs\backend.log
  ```
- For deeper logs, run the backend in the foreground (see "Backend does not
  start" above).

### Edge kiosk flag not recognized

Older Edge versions may not support `--edge-kiosk-type=fullscreen`. Update Edge
(Settings → About Microsoft Edge), or edit `start-pos.bat` and replace the Edge
line with:

```
start "" msedge.exe --kiosk "%BACKEND_URL%" --no-first-run
```

---

## 13. Updating the deployment later

1. On macOS: rebuild with `bash scripts/build-pos-windows.sh`
2. On Windows:
   - Run `C:\POSApp\stop-pos.bat`
   - Replace `pos-backend.exe`, `static\`, and `migrations\` folders
   - Keep your `.env` and `logs\` as-is
   - Run `C:\POSApp\start-pos.bat`

---

## 14. Dual-monitor customer display

`start-pos.bat` auto-detects monitor count via PowerShell. If **2 or more monitors** are connected:

- **Main monitor (1)**: opens Edge kiosk on the main POS UI (`http://127.0.0.1:8080/?username=pos1`)
- **Monitor 2**: opens a **second** Edge kiosk on the customer display route (`http://127.0.0.1:8080/#/customer`), positioned at `x=2000,y=0`

The two kiosks sync in real time via backend WebSockets:

- Cashier POS sends state to `/ws/pos-mirror` after login.
- Customer display stays open at `/#/customer` and receives state from `/ws/customer-display?branchId=00000&posId=POS001&posSecret=...`.

This works even though `start-pos.bat` launches the customer kiosk with a separate Edge profile.

To test the customer display without a sale, log in on the cashier screen and call:

```powershell
curl -X POST http://127.0.0.1:8080/pos-mirror/test-state -H "Authorization: Bearer <SESSION_TOKEN>"
```

### Adjusting monitor 2 position

Default `CUSTOMER_MONITOR_X=2000` works if monitor 2 is **to the right** of a ~1920×1080 main monitor. For other layouts edit the variable near the top of `start-pos.bat`:

| Layout                        | CUSTOMER_MONITOR_X      |
|-------------------------------|-------------------------|
| Monitor 2 right of FHD (1920) | `2000` (default)        |
| Monitor 2 right of 4K (3840)  | `3850`                  |
| Monitor 2 left of main        | a negative value (e.g. `-1920`) |
| Monitor 2 above main          | leave X, but Edge `--window-position` only takes X,Y — change the `--window-position=%CUSTOMER_MONITOR_X%,0` to use a negative Y |

Find the exact X coordinate via Windows Settings → System → Display → drag monitor 2 → note the "Identify" pixel offset, or run in PowerShell:

```powershell
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Screen]::AllScreens | ForEach-Object {
    "$($_.DeviceName)  Primary=$($_.Primary)  Bounds=$($_.Bounds)"
}
```

### "เปิดจอลูกค้า" button (in-app)

On the main POS, the cashier can press the **"หน้าจอลูกค้า"** button to open the customer display as a browser popup. The popup uses the **Window Management API** to detect monitor 2 and open the popup there in fullscreen.

**First-click permission prompt:** the first time the button is pressed, Edge will ask:

> "พิเซิญถาว่าจะให้ไซต์นี้จัดการหน้าต่างบนจอภาพทั้งหมดของคุณหรือไม่?" / "Allow this site to manage windows on all your displays?"

→ Click **Allow**. The permission persists, so subsequent clicks open the customer display on monitor 2 instantly.

If you decline / single-monitor setup, the popup falls back to a 1024×768 window on the main monitor (you can drag it to monitor 2 manually).

### Single-monitor setup

If only one monitor is connected, `start-pos.bat` skips the second kiosk and just shows the main UI. The "หน้าจอลูกค้า" button still works as a regular popup on the same monitor.

---

## 15. Receipt printer mode and test print

Production defaults to readable ASCII receipt output:

```env
RECEIPT_PRINTER_ENABLED=true
RECEIPT_PRINTER_PORT=LPT1
RECEIPT_PRINTER_NAME=POS80
RECEIPT_TEXT_MODE=ascii
RECEIPT_PRINT_MODE=ascii
RECEIPT_PRODUCT_NAME_MODE=receipt_name
RECEIPT_FORCE_ASCII=true
RECEIPT_CHARSET=21
CASH_DRAWER_ENABLED=true
CASH_DRAWER_BIN_PATH=C:\POSApp\drawer.bin
CASH_DRAWER_COMMAND=1B700019FA
```

The production printer is the internal 80mm thermal printer using Windows
Generic / Text Only on `LPT1`. The backend writes raw ESC/POS bytes; Flutter
Web does not use browser printing for receipts.

Why ASCII: this POS printer rendered Thai CP874 incorrectly in Generic / Text
Only mode. ASCII mode avoids garbled output. Product names shown in the POS UI
remain Thai, but paper receipts use `part_master.receipt_name`, an uppercase
ASCII name created specifically for LPT1 / Generic Text printing.

When adding new products through seed/admin SQL, always set
`part_master.receipt_name`. Keep it short, uppercase ASCII, and readable on an
80mm receipt. Examples:

```sql
-- name_th: ไม้อัดยาง 10 มิล เกรด C
receipt_name = 'PLYWOOD 10MM C'

-- name_th: เมลามีนขาว 1 หน้า ขนาด 6 มิล
receipt_name = 'MELAMINE WHITE 1S 6MM'
```

If `receipt_name` is empty, the backend falls back to a controlled ASCII name
from product code/size/grade and finally `ITEM <part_code>`. It does not print
raw Thai product names in ASCII production mode.

Thai output remains available for later testing:

```env
RECEIPT_FORCE_ASCII=false
RECEIPT_TEXT_MODE=thai_cp874
RECEIPT_CHARSET=21
```

If Thai is wrong, try `RECEIPT_CHARSET=20`, then `18`, then the value from the printer self-test/vendor manual. Return to `RECEIPT_TEXT_MODE=ascii` and `RECEIPT_FORCE_ASCII=true` if it is not reliable.

To print a small readable test print without completing a sale:

```powershell
curl.exe -X POST http://127.0.0.1:8080/pos/printer/test-print -H "Authorization: Bearer <SESSION_TOKEN>"
```

To print a sample 80mm receipt without completing a sale:

```powershell
curl.exe -X POST http://127.0.0.1:8080/pos/printer/test-receipt -H "Authorization: Bearer <SESSION_TOKEN>"
```

Refund/return receipts are printed by the cashier checkout flow after the
return note is created. The backend endpoint is:

```http
POST /returns/<RETURN_NOTE_ID>/print
```

### Cash drawer testing

The cash drawer does not open automatically just because the printer prints.
The backend must send an explicit ESC/POS drawer kick command to the printer.

Manual Windows test confirmed `cmd /c copy /b C:\POSApp\drawer.bin LPT1` opens
the drawer when run from PowerShell. The backend drawer path intentionally uses
the same PowerShell flow: write `C:\POSApp\drawer.bin` as bytes, then call
`cmd.exe /c copy /b ... LPT1` from that PowerShell process.

Example for the default command:

```powershell
[byte[]](0x1B,0x70,0x00,0x19,0xFA) | Set-Content -Encoding Byte C:\POSApp\drawer.bin
cmd /c copy /b C:\POSApp\drawer.bin LPT1
```

Use this endpoint to test the drawer without printing a receipt:

```powershell
curl.exe -X POST http://127.0.0.1:8080/pos/printer/open-drawer `
  -H "Authorization: Bearer <SESSION_TOKEN>" `
  -H "Content-Type: application/json" `
  -d "{\"command\":\"1B700019FA\"}"
```

Try these common commands one at a time:

```text
1B700019FA  ESC p 0 25 250  DK1 / pin 0, short pulse
1B700032FA  ESC p 0 50 250  DK1 / pin 0, longer pulse
1B700119FA  ESC p 1 25 250  DK2 / pin 1, short pulse
1B700132FA  ESC p 1 50 250  DK2 / pin 1, longer pulse
```

All four commands were manually tested on the Windows POS and opened the drawer.
Default production command is `1B700019FA`.

If a different command is preferred, set it in `C:\POSApp\.env`:

```env
CASH_DRAWER_ENABLED=true
CASH_DRAWER_BIN_PATH=C:\POSApp\drawer.bin
CASH_DRAWER_COMMAND=1B700119FA
```

`POST /pos/printer/open-drawer` logs the target, command, byte count, and
PowerShell method/bin path. A successful write only means Windows accepted the
bytes; it does **not** prove the cash drawer opened. You must visually confirm
the drawer movement. DK1/DK2 or pin 0/pin 1 depends on the printer's drawer
port wiring and firmware.

Troubleshooting if the drawer does not open:

- Confirm `RECEIPT_PRINTER_PORT=LPT1` and `CASH_DRAWER_ENABLED=true`.
- Confirm `CASH_DRAWER_BIN_PATH=C:\POSApp\drawer.bin` is writable by the
  backend process.
- Confirm manual PowerShell + `cmd /c copy /b ... LPT1` still opens it.
- Try the other three `CASH_DRAWER_COMMAND` values.
- Check `logs\backend.log` for `OpenCashDrawer` or `PrintReceipt` lines.
- Confirm the drawer cable is in the printer DK port, not a cash-drawer-only jack.

Keep tests separate while diagnosing:

- Test small printer output only: `POST /pos/printer/test-print`
- Test sample receipt: `POST /pos/printer/test-receipt`
- Test drawer only: `POST /pos/printer/open-drawer`
- Checkout print plus drawer: set `CASH_DRAWER_ENABLED=true` and the working `CASH_DRAWER_COMMAND`

---

## 16. POS Secret

The Flutter app sends a `POS_SECRET` to the backend on each login. Both ends **must agree**:

- **Backend side**: `pos_setting.pos_secret` in the DB (set by migration `0010_real_seed_data.up.sql` to `windows-pos-default-secret`)
- **Frontend side**: compiled into the Flutter Web bundle via `--dart-define=POS_SECRET=...` when the build script runs
- **Frontend API URL**: compiled via `--dart-define=API_BASE_URL=...`; Windows default is `http://127.0.0.1:8080`

If they don't match → login returns `invalid_pos_secret`.

### Using the default

Leave `.env` `POS_SECRET=windows-pos-default-secret` and rebuild on macOS using:

```bash
bash scripts/build-pos-windows.sh
```

(The build script defaults to that value.)

If you changed the backend port, rebuild with the matching API URL:

```bash
API_BASE_URL="http://127.0.0.1:8090" bash scripts/build-pos-windows.sh
```

### Changing to a custom secret

1. On macOS: rebuild with the new value:
   ```bash
   POS_SECRET="my-super-secret-key" bash scripts/build-pos-windows.sh
   ```
2. On Windows: update `C:\POSApp\.env` with `POS_SECRET=my-super-secret-key`
3. **Also update the DB** so `pos_setting.pos_secret` matches:
   ```
   psql -U posuser -d poslabs -h 127.0.0.1
   UPDATE "pos_setting" SET "pos_secret" = 'my-super-secret-key' WHERE "pos_id" = 'POS001';
   ```
4. Restart with `stop-pos.bat` then `start-pos.bat`

---

## 17. Regenerating real product data from xlsx

The `seed-real-data.sql` script was auto-generated from `~/Downloads/real-data-stock.xlsx` by `scripts/generate-real-seed-sql.py`.

If you update the spreadsheet (add/remove products, change prices), regenerate the SQL on macOS:

```bash
pip3 install openpyxl  # one-time
python3 scripts/generate-real-seed-sql.py
bash scripts/build-pos-windows.sh    # rebuilds dist/POSApp/ with the new SQL
```

Then on the Windows POS:
- Copy the new `seed-real-data.sql` to `C:\POSApp\`
- Re-run `load-real-data.bat` — the `ON CONFLICT DO NOTHING` clauses mean **existing products are not overwritten**, only new ones get added.

**To overwrite existing products** (e.g. when prices change), you have two options:

- **Surgical**: write your own `UPDATE` SQL and run it via psql.
- **Nuclear**: drop the `poslabs` database, recreate it, run `start-pos.bat` (re-seeds core data), then `load-real-data.bat` (re-loads all products). Be aware this wipes bills/returns/stock counts too.

---

## 18. Troubleshooting — "Parts list is empty / Addresses page returns 500"

If after a fresh deploy you see Parts page showing "ยังไม่มีข้อมูลสินค้า" or the Addresses page returns `500 {"error": "failed_to_list_addresses"}`, run this diagnostic first:

```cmd
C:\POSApp\verify-data.bat
```

Read the output carefully. The most common causes:

### Case A — Tables empty (parts: 0, addresses: 0)

You haven't run Phase 2 yet, or it failed silently. Run:

```cmd
C:\POSApp\load-real-data.bat
```

Watch the output:
- If you see `INSERT 0 N` lines for parts/addresses/categories → success.
- If you see `ERROR: invalid byte sequence for encoding "UTF8"` → your `PGCLIENTENCODING` isn't taking effect. Make sure you're using the latest `load-real-data.bat` (it sets `PGCLIENTENCODING=UTF8` at the top).
- If you see `ERROR: permission denied` → `posuser` doesn't own the `poslabs` database. Re-run the `CREATE USER / GRANT` commands from Step 2.

### Case B — Tables full but UI fails (parts: 1566, addresses: 1566, but UI shows 500)

The data was loaded by an older version of `seed-real-data.sql` that left `NULL` values in columns the Go code can't Scan as `string`/`int` (`bar_code`, `details`, `cost`, `shelf`, `max`, `remarks`).

The new `seed-real-data.sql` automatically repairs this on top of `INSERT` via `UPDATE … WHERE x IS NULL` statements. Re-running fixes it:

```cmd
C:\POSApp\load-real-data.bat
```

After re-running, `verify-data.bat` should show all `NULL` counts at 0.

### Case C — pos1 user gets 403 on Addresses page

`pos1` (role `role.cashier`) lacks `perm.addresses.read`. The new `seed-real-data.sql` grants it via `INSERT INTO role_permission (...) ON CONFLICT DO NOTHING`. If you already ran the old script, just re-run `load-real-data.bat`.

Manual one-liner:
```cmd
set PGCLIENTENCODING=UTF8
psql -h 127.0.0.1 -U posuser -d poslabs -c "INSERT INTO \"role_permission\"(\"role_id\",\"permission_id\") VALUES ('role.cashier','perm.addresses.read') ON CONFLICT DO NOTHING;"
```

### Case D — Nothing works, want to start clean

The nuclear option:
1. `C:\POSApp\stop-pos.bat`
2. In psql (as postgres superuser): `DROP DATABASE poslabs; CREATE DATABASE poslabs OWNER posuser; GRANT ALL PRIVILEGES ON DATABASE poslabs TO posuser;`
3. `C:\POSApp\start-pos.bat` — backend will re-run all migrations + SeedCoreData (admin, pos1, units, store, company, branch, POS device)
4. `C:\POSApp\load-real-data.bat` — products + categories + Thai units + pos_secret + cashier perm
5. `C:\POSApp\verify-data.bat` — should now show parts=1566, addresses=1566, all NULL counts=0
6. Refresh Edge kiosk (or `stop-pos.bat` then `start-pos.bat`)

---

## 19. Quick diagnostic one-liner

If you want to check DB state without `verify-data.bat`:

```cmd
set PGCLIENTENCODING=UTF8
psql -h 127.0.0.1 -U posuser -d poslabs -c "SELECT 'users' AS t, count(*) FROM \"user\" UNION ALL SELECT 'parts', count(*) FROM part_master UNION ALL SELECT 'addresses', count(*) FROM address_master UNION ALL SELECT 'categories', count(*) FROM category_master UNION ALL SELECT 'units', count(*) FROM unit_master ORDER BY t;"
```

Expected on a healthy fresh install: users=2, parts=1566, addresses=1566, categories=15, units=28.
