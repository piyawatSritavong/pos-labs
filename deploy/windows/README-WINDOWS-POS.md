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
[1/4] Starting PostgreSQL service "postgresql-x64-17" ...
[2/4] Ensuring logs folder exists ...
[3/4] Starting backend "pos-backend.exe" (minimized, logs to logs\backend.log) ...
[4/4] Opening Microsoft Edge in kiosk mode at http://127.0.0.1:8080 ...
```

Edge should open in fullscreen kiosk on the POS UI within ~5 seconds.

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

The two kiosks sync in real time via a backend WebSocket (`/ws/pos-mirror`) — when the cashier scans/adds an item on monitor 1, monitor 2 updates immediately.

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

## 15. POS Secret

The Flutter app sends a `POS_SECRET` to the backend on each login. Both ends **must agree**:

- **Backend side**: `pos_setting.pos_secret` in the DB (set by migration `0010_real_seed_data.up.sql` to `windows-pos-default-secret`)
- **Frontend side**: compiled into the Flutter Web bundle via `--dart-define=POS_SECRET=...` when the build script runs

If they don't match → login returns `invalid_pos_secret`.

### Using the default

Leave `.env` `POS_SECRET=windows-pos-default-secret` and rebuild on macOS using:

```bash
bash scripts/build-pos-windows.sh
```

(The build script defaults to that value.)

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

## 16. Regenerating real product data from xlsx

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

## 17. Troubleshooting — "Parts list is empty / Addresses page returns 500"

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

## 18. Quick diagnostic one-liner

If you want to check DB state without `verify-data.bat`:

```cmd
set PGCLIENTENCODING=UTF8
psql -h 127.0.0.1 -U posuser -d poslabs -c "SELECT 'users' AS t, count(*) FROM \"user\" UNION ALL SELECT 'parts', count(*) FROM part_master UNION ALL SELECT 'addresses', count(*) FROM address_master UNION ALL SELECT 'categories', count(*) FROM category_master UNION ALL SELECT 'units', count(*) FROM unit_master ORDER BY t;"
```

Expected on a healthy fresh install: users=2, parts=1566, addresses=1566, categories=15, units=28.
