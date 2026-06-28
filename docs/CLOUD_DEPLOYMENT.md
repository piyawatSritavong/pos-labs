# Cloud Deployment: Vercel + Render + Supabase

This guide deploys POS Labs as separate services:

- Frontend: Flutter Web on Vercel
- Backend: Go API on Render Web Service
- Database: Supabase PostgreSQL

Local and Windows POS deployment still work. In cloud mode, hardware features such as LPT1 receipt printing and cash drawer commands must be disabled.

## 1. Supabase Database

Create a Supabase project and copy the PostgreSQL connection string. Direct connection is fine for a Render Web Service. If direct connection has network/IP issues, use the Supabase pooler URL instead.

Run migrations from the repo:

```bash
cd backend
DATABASE_URL='postgresql://USER:PASSWORD@HOST:5432/postgres?sslmode=require' \
APP_ENV=production \
go run ./cmd/migrate up
```

Seed core data:

```bash
cd backend
DATABASE_URL='postgresql://USER:PASSWORD@HOST:5432/postgres?sslmode=require' \
APP_ENV=production \
go run ./cmd/seed --core
```

Seed real product/stock data:

```bash
cd backend
DATABASE_URL='postgresql://USER:PASSWORD@HOST:5432/postgres?sslmode=require' \
APP_ENV=production \
go run ./cmd/seed --real-data ../deploy/windows/seed-real-data.sql
```

Alternative with `psql`:

```bash
psql "$DATABASE_URL" -f deploy/windows/seed-real-data.sql
```

Do not run down migrations or drop tables on production data.

## 2. Render Backend

Use the root `render.yaml` or create a Render Web Service manually.

Build command:

```bash
go build -o app ./cmd/api
```

Start command:

```bash
./app
```

Health check path:

```text
/health
```

Required Render env vars:

```bash
APP_ENV=production
DATABASE_URL=postgresql://USER:PASSWORD@HOST:5432/postgres?sslmode=require
SERVE_STATIC=false
AUTO_MIGRATE=false
AUTO_SEED_CORE=false
AUTO_ENSURE_BARCODES=false
CORS_ALLOWED_ORIGINS=https://your-vercel-app.vercel.app
SESSION_SECRET=change-me
POS_SECRET=windows-pos-default-secret
RECEIPT_PRINTER_ENABLED=false
CASH_DRAWER_ENABLED=false
```

Optional DB pool env vars:

```bash
DB_MAX_OPEN_CONNS=10
DB_MAX_IDLE_CONNS=5
DB_CONN_MAX_LIFETIME=30m
```

Verify:

```bash
curl https://your-render-service.onrender.com/health
curl https://your-render-service.onrender.com/ready
```

`/health` is a Render liveness check. `/ready` checks database connectivity.

## 3. Vercel Frontend

Set Vercel project root to `frontend`.

Required Vercel env vars:

```bash
API_BASE_URL=https://your-render-service.onrender.com
POS_SECRET=windows-pos-default-secret
```

Optional:

```bash
WS_BASE_URL=wss://your-render-service.onrender.com
FLUTTER_VERSION=stable
```

The Vercel build uses `frontend/vercel.json` and `frontend/scripts/vercel-build.sh`. The script installs Flutter if Vercel does not already have it, then builds:

```bash
flutter build web --release \
  --dart-define=API_BASE_URL=$API_BASE_URL \
  --dart-define=POS_SECRET=$POS_SECRET
```

Local build equivalent:

```bash
cd frontend
flutter build web --release \
  --dart-define=API_BASE_URL=https://your-render-service.onrender.com \
  --dart-define=POS_SECRET=windows-pos-default-secret
```

## 4. Local and Windows POS

Local default API URL for Flutter is:

```text
http://127.0.0.1:8080
```

The Windows build script now accepts `API_BASE_URL`:

```bash
API_BASE_URL=http://127.0.0.1:8080 POS_SECRET=windows-pos-default-secret bash scripts/build-pos-windows.sh
```

Windows backend `.env` should keep:

```bash
SERVE_STATIC=true
AUTO_MIGRATE=true
AUTO_SEED_CORE=true
RECEIPT_PRINTER_ENABLED=true
CASH_DRAWER_ENABLED=true
```

Cloud deployments should keep printer and drawer disabled. Checkout still creates bills when printing is disabled; only hardware print/drawer endpoints return disabled errors.

## 5. Manual Smoke Test

1. Run migrations and seeds against Supabase.
2. Deploy Render and verify `/health` and `/ready`.
3. Test login with `POST /auth/login`.
4. Deploy Vercel and open DevTools Network.
5. Login, search parts, create a bill, and confirm there are no CORS errors.
6. Test POS mirror/customer display if used; `WS_BASE_URL` is only needed when WebSocket origin differs from API origin.
