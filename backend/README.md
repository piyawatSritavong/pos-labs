## POS Labs Backend (Go + Gin)

### Overview

This backend is a Go service using Gin, PostgreSQL, and token-based session authentication with role/permission (RBAC) checks.

- **Framework**: Gin
- **Database**: PostgreSQL
- **Migrations**: `golang-migrate` with SQL files in `./migrations`
- **Auth**: Database-backed sessions with bearer tokens, RBAC using `role`, `permission`, `role_permission`

### Configuration

Environment variables (see `docker-compose.yml` for defaults):

- `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`, `DB_SSLMODE`
- `PORT` – HTTP port (default `8080`)
- `ENV` – `development` or `production`
- `SESSION_SECRET` – Secret for session token generation (not used with DB sessions, but kept for compatibility)
- `SESSION_DURATION` – Session expiration duration (e.g., `4h`, `24h`, default: `4h`)

All database connections are configured to use **UTF-8** encoding and **UTC** timezone:

- Docker Postgres is initialized with `--encoding=UTF8 --locale=C.UTF-8`.
- The Go connection string adds `timezone=UTC`, and each connection runs `SET TIME ZONE 'UTC'`.
- All timestamps returned by the API are in **UTC** (RFC3339), and all text fields support Thai and other Unicode characters.

### Migrations and Seeding

On startup (`cmd/server/main.go`):

1. Connects to PostgreSQL using `internal/db.Connect`.
2. Runs any pending migrations via `internal/db.RunMigrations`, reading from `file://migrations`.
3. Seeds core data via `internal/db.SeedCoreData` (idempotent - skips if data exists):
   - Inserts default `permission` rows (parts, bills, users).
   - Inserts `role.owner` (all permissions) and `role.cashier` (parts read, bills read/write).
   - Grants permissions via `role_permission`.
   - Creates default `store_master` and `unit_master` entries.
   - Creates an admin user:
     - `id`: `admin`
     - `username`: `admin`
     - `password`: `admin123` (bcrypt-hashed, **change in production**)
4. In development mode only, seeds mock data via `internal/db.SeedMockData`:
   - Sample categories, parts, and addresses for testing.

**Note**: Seeding uses an "all-or-nothing" approach - if any core data exists, seeding is skipped entirely to prevent partial updates.

### Authentication, Sessions, and RBAC

- **Login flow**:
  - `POST /auth/login` with JSON `{ "username": "admin", "password": "admin123" }`.
  - Verifies credentials against the `user` table (password stored as bcrypt hash).
  - On success, creates a row in the `session` table with:
    - `id` – opaque random token (64-char hex, not the user ID)
    - `user_id` – internal user primary key
    - `ip` – client IP address (for security)
    - `user_agent` – client user agent
    - `created_at`, `expires_at`, `last_seen_at` (all in UTC)
  - Returns a response:
    ```json
    {
      "token": "abc123...",
      "name": "Admin User",
      "role_id": "owner",
      "expires": "2025-12-03T16:00:00Z"
    }
    ```
- **Using the token**:
  - Clients send `Authorization: Bearer <token>` on all protected requests.
  - The middleware validates the token, checks expiration, and optionally matches IP.
- **Logout**:
  - `POST /auth/logout` with `Authorization: Bearer <token>` deletes the session row.
- **Session management**:
  - Sessions are stored in the database (`session` table) for better control.
  - Background goroutine runs every 5 minutes to delete expired sessions.
  - Session duration is configurable via `SESSION_DURATION` environment variable.
- **RBAC enforcement**:
  - Middleware `RequireAuth()` validates the session and loads the user.
  - Middleware `RequirePermission(resource, action)` checks RBAC using `role`, `permission`, `role_permission`.
  - Example: `parts:read`, `bills:write`, etc.

### HTTP API

#### Health
- `GET /health` – Health check, returns `{"status": "ok", "db": "up"}` or `{"status": "unhealthy", "db": "down"}`

#### Authentication
- `POST /auth/login` – Login with `{ "username": "...", "password": "..." }`. Returns `token`, `name`, `role_id`, `expires`.
- `POST /auth/logout` – Logout (requires `Authorization: Bearer <token>`).
- `GET /auth/me` – Get current user info (requires auth). Returns `name`, `role_id`, `is_active`.

#### Parts (requires `parts:read` permission)
- `GET /parts?limit=50&offset=0` – List parts with pagination.
  - Query params: `limit` (1-500, default: 50), `offset` (default: 0).
  - Returns array of parts with category, unit, and total stock.
- `GET /parts/:code` – Get part details by code.
  - Returns full part info with nested category, unit, total stock, and addresses (with store info).

#### Bills
- `GET /bills?limit=50&offset=0` – List bills with pagination (requires `bills:read`).
  - Query params: `limit` (1-500, default: 50), `offset` (default: 0).
  - Returns array of bills ordered by `created_at DESC`.
- `POST /bills` – Create empty bill (requires `bills:write`).
  - No request body required.
  - Generates systematic bill ID using `counter` table (format: `YYYYMMDD` + 6-digit counter, e.g., `20251204000001`).
  - Returns `{ "id": "20251204000001" }`.

### Systematic ID Generation

The backend uses a unified `counter` table for generating systematic IDs:

- **Bills**: Date-based keys (e.g., `"20251204"`) that reset daily. Bill IDs format: `YYYYMMDD` + 6-digit counter (e.g., `"20251204000001"`).
- **Members**: Static key `"member"` for sequential member codes (e.g., `"000001"`, `"000002"`).

The counter uses atomic SQL operations (`INSERT ... ON CONFLICT DO UPDATE`) to prevent race conditions and ensure unique IDs.

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
  - Seed mock data (categories, parts, addresses) in development mode.
  - Start background session cleanup goroutine.

### Running Locally (Go only)

From `backend/`:

```bash
go run ./cmd/server
```

Ensure PostgreSQL is running and the configuration env vars are set. The server will:
- Run migrations automatically.
- Seed core data if the database is empty.
- Seed mock data if `ENV=development`.

### Testing the API

A Postman collection is available at `_dev-resources/posman-collection-v1.0.json`:

1. Import the collection into Postman.
2. Set the `base_url` variable to `http://localhost:8080`.
3. Run `POST /auth/login` to get a token (automatically saved to `auth_token` variable).
4. Use other endpoints - the token is automatically included in the `Authorization` header.

### Project Structure

```
backend/
├── cmd/server/          # Application entrypoint
├── internal/
│   ├── config/         # Configuration loading
│   ├── db/             # Database connection, migrations, seeding
│   ├── httpserver/     # HTTP server setup
│   │   ├── handlers/   # Request handlers (auth, parts, bills, health)
│   │   └── middleware/ # Auth and RBAC middleware
│   └── repository/     # Data access layer (interfaces and PostgreSQL implementations)
└── migrations/         # SQL migration files (up/down)
```


