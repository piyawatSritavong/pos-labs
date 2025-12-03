## POS Labs Backend (Go + Gin)

### Overview

This backend is a Go service using Gin, PostgreSQL, and token-based session authentication with role/permission (RBAC) checks.

- **Framework**: Gin
- **Database**: PostgreSQL
- **Migrations**: `golang-migrate` with SQL files in `./migrations`
- **Auth**: Cookie-based sessions, RBAC using `role`, `permission`, `role_permission`

### Configuration

Environment variables (see `docker-compose.yml` for defaults):

- `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`, `DB_SSLMODE`
- `PORT` – HTTP port (default `8080`)
- `ENV` – `development` or `production`

All database connections are configured to use **UTF-8** encoding and **UTC** timezone:

- Docker Postgres is initialized with `--encoding=UTF8 --locale=C.UTF-8`.
- The Go connection string adds `timezone=UTC`, and each connection runs `SET TIME ZONE 'UTC'`.
- All timestamps returned by the API are in **UTC** (RFC3339), and all text fields support Thai and other Unicode characters.

### Migrations and Seeding

On startup (`cmd/server/main.go`):

1. Connects to PostgreSQL using `internal/db.Connect`.
2. Runs any pending migrations via `internal/db.RunMigrations`, reading from `file://migrations`.
3. Seeds core data via `internal/db.SeedCoreData`:
   - Inserts default `permission` rows (parts, bills, users).
   - Inserts `role.admin` and `role.cashier`.
   - Grants all permissions to admin, POS-related permissions to cashier.
   - Creates an admin user:
     - `id`: `admin`
     - `username`: `admin`
     - `password`: `admin123` (bcrypt-hashed, **change in production**)

### Authentication, Sessions, and RBAC

- Login flow:
  - `POST /auth/login` with JSON `{ "username": "admin", "password": "admin123" }`.
  - Verifies credentials against the `user` table (password stored as bcrypt hash).
  - On success, creates a row in the `session` table with:
    - `id` – opaque random token (not the user ID)
    - `user_id` – internal user primary key
    - `ip`, `user_agent`, `created_at`, `expires_at`, `last_seen_at` (all in UTC)
  - Returns a response like:
    - `token` – the session ID to be used as bearer token
    - `name` – user display name
    - `role_id` – role for RBAC
    - `expires` – UTC timestamp (RFC3339) when the token expires
- Using the token:
  - Clients send `Authorization: Bearer <token>` on all protected requests.
- Logout:
  - `POST /auth/logout` with `Authorization: Bearer <token>` deletes the session row.
- Session enforcement:
  - Middleware:
    - Looks up the token in `session`, checks `expires_at > now()` and optional IP match.
    - Loads the `user` by `user_id` and ensures `is_active = true`.
    - `RequirePermission(resource, action)` checks RBAC using `role`, `permission`, `role_permission`.

### HTTP API

Key endpoints:

- `GET /health` – basic health check, including DB connectivity.
- `POST /auth/login` – login.
- `POST /auth/logout` – logout (requires auth).
- `GET /auth/me` – current user (requires auth).
- `GET /parts` – example protected endpoint (requires `resource="parts"`, `action="read"`).
- `GET /bills` – example protected endpoint (requires `resource="bills"`, `action="read"`).

### Running Locally (Docker)

From the project root:

```bash
docker-compose up --build
```

- `postgres` will start and expose `5432`.
- `backend` will start on `http://localhost:8080`, running `air` for hot reload in development.
- The Go server will automatically:
  - Run migrations.
  - Seed roles, permissions, and admin user if missing.

### Running Locally (Go only)

From `backend/`:

```bash
go run ./cmd/server
```

Ensure PostgreSQL is running and the configuration env vars are set.


