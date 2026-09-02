# CLAUDE.md

POS Labs — a Thai-language Point of Sale for a van-sales business: one HQ warehouse
restocks vehicle stock on each POS, and van staff sell from the vehicle.

## Stack

- **Backend**: Go 1.23 (Docker builds on 1.24), Gin, `lib/pq`, `golang-migrate`, gorilla/websocket. Module name is `backend`.
- **Frontend**: Flutter (desktop Windows/Linux/macOS + Flutter Web; mobile targets exist). `provider` for state, `http` + `web_socket_channel` for the API.
- **DB**: PostgreSQL 17 (local Docker) / Supabase (cloud). Cloud API also runs on Render (`render.yaml`).

## Folder map

- [backend/cmd/](backend/cmd/) — entrypoints: `api` (Docker/Render), `server` (local `go run`), `migrate`, `seed`.
- [backend/internal/app/server.go](backend/internal/app/server.go) — startup: connect, migrate, seed, HTTP server, session GC.
- [backend/internal/config/config.go](backend/internal/config/config.go) — **every env var is read here** (plus `APP_ENV`/`ENV`/`GO_ENV` in [middleware/auth.go](backend/internal/httpserver/middleware/auth.go)).
- [backend/internal/httpserver/router.go](backend/internal/httpserver/router.go) — all routes + permission gates + Flutter Web SPA fallback.
- [backend/internal/httpserver/handlers/](backend/internal/httpserver/handlers/) — HTTP layer. Big ones: `bills.go`, `returns.go`, `inventory_transfer.go`, `parts.go`.
- [backend/internal/repository/](backend/internal/repository/) — interface (`x.go`) + Postgres impl (`x_pg.go`) per aggregate.
- [backend/internal/db/](backend/internal/db/) — migrations runner, core seed, mock seed, catalog seed, barcode backfill.
- [backend/migrations/](backend/migrations/) — numbered `NNNN_name.up.sql` / `.down.sql`. Never edit an applied migration; add a new one.
- [backend/internal/partsimport/](backend/internal/partsimport/) — XLSX bulk product import (parser + template).
- [frontend/lib/](frontend/lib/) — `screens/` (login, home/POS, backoffice, customer display), `widgets/`, `services/` (API clients), `providers/`, `config/`.
- [deploy/](deploy/) — one-off Supabase SQL run by hand. [scripts/](scripts/) — seed generators, smoke tests, perf. [docs/](docs/), [HANDBOOK.md](HANDBOOK.md) — manual test walkthrough (Thai).

## Run / build / test

```bash
# Backend + Postgres (Air hot reload inside the container)
docker-compose up --build            # add -d; `down -v` wipes the volume
go run ./cmd/server                  # from backend/, against a local/remote DB
go build ./... && go test ./...      # from backend/
go run ./cmd/migrate                 # migrations only; ./cmd/seed for seed data

# Frontend (from frontend/)
flutter run -d macos                 # or windows / linux / chrome
flutter build web --profile          # HANDBOOK serves build/web on :8081-8083 for 3 roles
flutter test
flutter build windows                # scripts/build-pos-windows.sh packages the POS
```

Backend listens on `:8080`. Frontend defaults to `http://127.0.0.1:8080`; override at build time with
`--dart-define=API_BASE_URL=... --dart-define=WS_BASE_URL=...` ([api_config.dart](frontend/lib/config/api_config.dart)).
Seeded logins: `admin/admin123`, `pos1/pos123456`, and (mock seed) `hqmanager/hq123456`.

## Env vars

Read only in [config.go](backend/internal/config/config.go) via `getEnv*`; `docker-compose.yml` passes them into the container, `.env` feeds compose.

- **DB**: `DATABASE_URL` (wins over everything; `@` in a password must be `%40`), else `DB_HOST/PORT/USER/PASSWORD/NAME/SSLMODE`, plus `DB_MAX_OPEN_CONNS`, `DB_MAX_IDLE_CONNS`, `DB_CONN_MAX_LIFETIME`.
- **App**: `APP_ENV`/`ENV` (`production` switches Gin to release + `WithCloudDefaults`), `PORT`, `SESSION_SECRET`, `SESSION_DURATION` (default `4h`).
- **Startup mutations**: `AUTO_MIGRATE`, `AUTO_SEED_CORE`, `AUTO_SEED_MOCK`, `AUTO_ENSURE_BARCODES`, `SERVE_STATIC`, `STATIC_FILES_PATH`. All default **off** in production unless explicitly set.
- **CORS**: `CORS_ALLOWED_ORIGINS`, `CORS_ALLOW_CREDENTIALS`.
- **Receipt/drawer** (Windows POS): `RECEIPT_PRINTER_ENABLED`, `RECEIPT_PRINTER_PORT`/`_NAME`/`_TARGET`, `RECEIPT_CHARSET` (21 = Thai), `RECEIPT_TEXT_MODE`, `RECEIPT_FORCE_ASCII`, `RECEIPT_PRODUCT_NAME_MODE`, `CASH_DRAWER_ENABLED`, `CASH_DRAWER_COMMAND`.

`.env` at the repo root may set `DATABASE_URL` to the cloud demo DB — a local backend then silently reads cloud data. Comment it out for local work.

## DB schema summary

- **Org**: `company_setting` (tax id, `tax_rate`, `tax_type`) → `branch_setting` (`branch_id` = 5-digit string, `00000` = HQ) → `pos_setting` (`pos_id`, `branch_id`, `pos_secret`, `vehicle_store_id`).
- The คลังสินค้า page (`GET /addresses`) reads **every** store, not just the warehouse — its filter offers the vans and "ทุกคลัง" has to mean all of them. Writes stay warehouse-only (`PUT /addresses/:code` returns `invalid_warehouse` for anything but `main`), because van stock moves through a transfer or a stock count; the UI disables the edit button on a van row rather than letting it fail.
- **Stock locations**: `store_master` (`location_type` = `warehouse` | `vehicle`; **exactly one** warehouse row exists, id `main`), `branch_store` join.
- **Catalog**: `part_master` (`code` PK, `bar_code`, `cost`, `price`, `min_price`, `is_active`) + `unit_master`, `category_master`. `address_master` is the stock row: one per (part, store) with `qty`, `shelf`, `rop`, `is_active` — **this table is the inventory**.
- **Sales**: `bill_master` (id `YYYYMMDDnnnnnn`, `branch_id`, `pos_id`, `status`, `payment_method`, amounts) → `bill_item_detail` (PK bill+part+address, price/qty snapshot) and `bill_discount_detail`. `return_note_master`/`_item_detail` (id `CNYYYYMMDDnnnnnn`). `member_master`, `promotion_master`.
- **Operations**: `inventory_transfer` (+`_item`, `_audit`) with `transfer_mode` `standard` | `pos_restock`; `stock_count`(+`_item`); `daily_close`; `cash_reconciliation`; `purchase_order`(+`_item`).
- **Auth**: `user` (`role_id`, `is_superuser`, `custom_permissions[]`, `default_pos_id`), `user_branch`, `session` (token = `session.id`, carries `branch_id` + `pos_id`), `role`/`permission`/`role_permission`.
- **`counter`**: single source of sequential numbers, keyed by `YYYYMMDD` (bills), `cn_YYYYMMDD` (returns), `branch_id`.

## Business rules that must never break

### Branch / POS data isolation

- Session identity is `branch_id` + `pos_id`, set at login from the POS credentials and stored on `session`. Handlers must read them from the gin context, **never** from the request body or a query param.
- [access_scope.go](backend/internal/httpserver/handlers/access_scope.go) is the gate: `canReadOperationalRecord` / `canReadOperationalBranch` / `canWriteOperationalRecord`. Only `is_superuser` or `role.admin` may read across branches. POS roles (`role.cashier`, `role.van_staff`) are additionally pinned to their own `pos_id`.
- Writes are stricter than reads: a write requires a non-empty session branch **and** POS that match the record. Admin's cross-branch read privilege does not extend to writes.
- List endpoints take `scope=pos|branch|all`; default is `pos`. `all` is admin-only, `branch` is denied to POS roles. Don't add a list endpoint without the same scope handling.
- Bills/returns/POS-mirror write routes sit behind `middleware.RequirePOSBranch()` — a session without both ids gets 403 `session_not_allow`.
- Parts, addresses and stock reads pass the session `branch_id` down to the repository so a POS sees only its own branch's stock rows.

### Role permissions

- Roles: `role.admin` (all permissions), `role.hq_manager`, `role.van_staff`, `role.cashier`. Seeded in [db/seed.go](backend/internal/db/seed.go); per-role permission lists live there and in later migrations.
- Every route is wrapped in `authMw.RequirePermission(resource, action)` in [router.go](backend/internal/httpserver/router.go). A new endpoint gets a permission — no unauthenticated route except `/health`, `/ready`, `/test`, `/auth/login`, `/parts/import/template`, the WS upgrade handlers (which authenticate via `?token=`), and static files.
- Permission changes must be seeded **and** added as a migration; existing deployments only get them through migrations.
- User administration is hierarchical: admin may manage `role.hq_manager` + `role.van_staff`, HQ manager may manage only `role.van_staff` ([user.go](backend/internal/httpserver/handlers/user.go)). Superusers cannot be deleted.
- Transfer approval (`transfers:approve`) belongs to HQ; van staff may create, submit and cancel **their own** requests only.
- The `mock-admin-token` bypass in [middleware/auth.go](backend/internal/httpserver/middleware/auth.go) must stay gated on a development env.

### Invoice / document numbering

- Bill ids are `YYYYMMDD` + 6-digit zero-padded counter (`20251204000001`); return notes are `CN` + the same shape. The date is **UTC+7 (Thailand)**, not server local time.
- Numbers come from a single atomic `INSERT … ON CONFLICT DO UPDATE SET value = value + 1 RETURNING value` on `counter` ([bill_pg.go](backend/internal/repository/bill_pg.go), [return_note_pg.go](backend/internal/repository/return_note_pg.go)). Never compute the next number with `SELECT MAX(...)` or in application code.
- Completed bills are permanent: `DELETE /bills/:id` refuses `status = completed`; cancellation flips status and returns stock instead.

### Stock movement

- `address_master.qty` is the only stock quantity. Every movement is an update of that column inside the transaction that records the document.
- POS sale: stock is decremented when the item is **added to the bill**, not at payment. `DecreaseInventory` is conditional (`WHERE qty >= n`) and returns whether it applied — a false result must surface as `not_enough_inventory`, never as a silent sale.
- Stock is returned by `IncreaseInventory` on remove-item, qty reduction, bill cancel, bill delete, and return notes. Any new bill-mutating path must balance the pair.
- The sale search (`saleableOnly=true`) is pinned to the session POS's own `vehicle_store_id`. It lists the whole van catalogue, including lines at zero — `includeOutOfStock=true` drops only the `qty > 0` clause, never the store scoping — so the till and the vehicle stock page show the same products; the client greys out what is finished. Hiding them read as "the system has the product but I cannot sell it".
- A POS may only sell from its own `pos_setting.vehicle_store_id` — an address in another store is rejected as `invalid_address_code` ([bills.go](backend/internal/httpserver/handlers/bills.go) `salesAddressForPOS`).
- Restock (`pos_restock`) is `draft → review → completed`; standard transfers are `pending → approved → dispatched → received`, either cancellable before completion. Stock leaves the warehouse address and lands on the vehicle address in one transaction, creating the destination row if missing; a shortage aborts the whole transfer.
- Stock counts **record** `system_qty` vs `counted_qty` and never adjust stock; variance is reported through `/reports/stock-variance` and settled by HQ.
- Deleting a part that any document references **archives** it (`is_active = false` on `part_master` and all its `address_master` rows) — a hard delete would cascade the vehicle's stock row away. Archiving strands whatever qty sat on those rows, so move the stock to the surviving product first; [deploy/supabase-merge-tyre-duplicates.sql](deploy/supabase-merge-tyre-duplicates.sql) is the worked example. Archived parts are out of the restock catalog and the inbound/transfer pickers (the purchase-order picker has an opt-in, because receiving is the only thing that reactivates a part), but their barcodes still resolve — a scan of one answers `part_archived`.

### Pricing

- `part_master` enforces `cost >= 0`, `price >= 0`, `0 <= min_price <= price` as a DB CHECK. Keep the constraint intact; when `min_price` is not supplied it defaults to `price * 0.90`.
- **A cashier may sell a line at any price.** There is no floor or ceiling: the van haggles both ways on the same round, and a catalog-derived limit turned that into an error the cashier could not clear. `min_price` is a reference for whoever sets prices, not a gate at the till — see [pricing_validation.go](backend/internal/httpserver/handlers/pricing_validation.go). A line total of **0 is a giveaway** (แถม) and must be accepted — the request field is a `*float64` so an explicit 0 is not mistaken for a missing one, and zero-priced lines are labelled แถม in the cart, on the customer display, in bill history and on the printed slip. Only a negative line is refused.
- Bill-level discounts are likewise unfloored; the client clamps them to the bill total so a bill cannot go negative. Discount units are `THB` or `percentage`.
- VAT follows `company_setting.tax_type`: `xvat` = price excludes VAT (`vat_amount = 0`), `vat` = price includes VAT and it is extracted as `amount × rate/(1+rate)`. Never add VAT on top of a stored price.
- Bill lines snapshot `price`/`cost` at sale time; restock lines snapshot `sale_price` at submit so HQ reviews a stable amount. Later catalog edits must not change past documents.
- Payment methods are normalised to `cash | bank | credit_term | exchange` ([payment_validation.go](backend/internal/httpserver/handlers/payment_validation.go)); `credit_term` requires a positive total plus payment meta, and is feature-flagged in the frontend by `kEnableCreditTerm`.
