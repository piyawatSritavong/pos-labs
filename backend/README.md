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
- `CORS_ALLOWED_ORIGINS` – Comma-separated list of allowed origins for CORS (production only, e.g., `https://app.example.com,https://www.example.com`)

All database connections are configured to use **UTF-8** encoding and **UTC** timezone:

- Docker Postgres is initialized with `--encoding=UTF8 --locale=C.UTF-8`.
- The Go connection string adds `timezone=UTC`, and each connection runs `SET TIME ZONE 'UTC'`.
- All timestamps returned by the API are in **UTC** (RFC3339), and all text fields support Thai and other Unicode characters.

### CORS Configuration

CORS (Cross-Origin Resource Sharing) is configured with environment-aware behavior:

**Development Mode (`ENV=development`):**
- Allows common localhost origins (ports 3000, 3001, 5173, 8080, 8081)
- Also allows any `localhost` or `127.0.0.1` origin for flexibility
- Credentials are allowed (for session cookies/auth tokens)

**Production Mode (`ENV=production`):**
- Only allows origins specified in `CORS_ALLOWED_ORIGINS` environment variable
- Format: comma-separated list (e.g., `https://app.example.com,https://www.example.com`)
- If `CORS_ALLOWED_ORIGINS` is not set, no origins are allowed (strict security)

**Allowed Methods:** `GET, POST, PUT, DELETE, PATCH, OPTIONS`

**Allowed Headers:** `Content-Type, Authorization, X-Requested-With`

This configuration ensures:
- Frontend developers work with CORS from the start (good practice)
- Development is easy (allows localhost)
- Production is secure (specific origins only)

### Migrations and Seeding

On startup (`cmd/server/main.go`):

1. Connects to PostgreSQL using `internal/db.Connect`.
2. Runs any pending migrations via `internal/db.RunMigrations`, reading from `file://migrations`.
3. Seeds core data via `internal/db.SeedCoreData` (idempotent - skips if data exists):
   - Inserts default `permission` rows for:
     - Parts: `read`, `write`, `delete`
     - Bills: `read`, `write`, `delete`
     - Users: `read`, `write`, `delete`, `manage`
     - Roles: `read`, `write`, `delete`
     - Permissions: `read`, `write`, `delete`
     - Company: `read`, `write`
     - Branch: `read`, `write`, `delete`
     - POS: `read`, `write`, `delete`
     - User Branches: `read`, `write`
   - Inserts `role.admin` (all permissions) and `role.cashier` (parts read, bills read/write).
   - Grants permissions via `role_permission`.
   - Creates default company, branch, and POS settings.
   - Creates default `store_master` (linked to default branch) and `unit_master` entries.
   - Creates an admin user:
     - `id`: `admin`
     - `username`: `admin`
     - `password`: `admin123` (bcrypt-hashed, **change in production**)
     - `is_superuser`: `true` (cannot be deleted)
4. In development mode only, seeds mock data via `internal/db.SeedMockData`:
   - Sample categories, parts, and addresses for testing.

**Note**: Seeding uses an "all-or-nothing" approach - if any core data exists, seeding is skipped entirely to prevent partial updates.

### Authentication, Sessions, and RBAC

- **Login flow**:
  - `POST /auth/login` with JSON `{ "username": "admin", "password": "admin123", "branchId": "00000", "posId": "POS001" }`.
  - `branchId` and `posId` are optional (required for cashier users, optional for superusers/admin).
  - Verifies credentials against the `user` table (password stored as bcrypt hash).
  - If `branchId` and `posId` are provided:
    - Validates branch and POS exist.
    - Validates user has access to branch (unless superuser).
  - On success, deletes any existing session for the user (only 1 session per user), then creates a new row in the `session` table with:
    - `id` – opaque random token (64-char hex, not the user ID)
    - `user_id` – internal user primary key (UNIQUE constraint - only 1 session per user)
    - `branch_id` – branch the user is working at (nullable)
    - `pos_id` – POS the user is working at (nullable)
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
  - The middleware extracts `branchId` and `posId` from the session and sets them in the request context.
  - All bill-related endpoints automatically use `branchId` and `posId` from the session (no need to pass them in requests).
- **Logout**:
  - `POST /auth/logout` with `Authorization: Bearer <token>` deletes the session row.
- **Session management**:
  - Sessions are stored in the database (`session` table) for better control.
  - Only 1 active session per user (enforced by UNIQUE constraint on `user_id`).
  - When a user logs in, any existing session for that user is automatically deleted.
  - Background goroutine runs every 5 minutes to delete expired sessions.
  - Session duration is configurable via `SESSION_DURATION` environment variable.
  - Sessions store `branch_id` and `pos_id` for cashier users, allowing bill operations to automatically use the correct branch and POS.
- **RBAC enforcement**:
  - Middleware `RequireAuth()` validates the session and loads the user.
  - Middleware `RequirePermission(resource, action)` checks RBAC using `role`, `permission`, `role_permission`.
  - Resources: `parts`, `bills`, `users`, `roles`, `permissions`, `company`, `branch`, `pos`, `user_branch`
  - Actions: `read`, `write`, `delete`, `manage` (depending on resource)
  - Example: `parts:read`, `bills:write`, `branch:delete`, etc.
  - Superusers (`is_superuser=true`) have access to all branches and cannot be deleted.

### HTTP API

#### Health
- `GET /health` – Health check, returns `{"status": "ok", "db": "up"}` or `{"status": "unhealthy", "db": "down"}`

#### Authentication
- `POST /auth/login` – Login with `{ "username": "...", "password": "..." }`. Returns `token`, `name`, `role_id`, `expires`.
- `POST /auth/logout` – Logout (requires `Authorization: Bearer <token>`).
- `GET /auth/me` – Get current user info (requires auth). Returns `name`, `role_id`, `is_active`, `branchId`, `posId` (if set in session).

#### Parts (requires `parts:read` permission)
- `GET /parts?limit=20&offset=0` – List parts with pagination.
  - Query params: `limit` (1-500, default: 20), `offset` (default: 0).
  - Returns array of parts with category, unit, and total stock.
- `GET /parts/search?q=...` – Universal search for parts.
  - Query params: `q` (search query), `categoryId`, `isActive`, `crossBranch`, `limit` (default: 20), `offset` (default: 0).
  - Searches across: part code, barcode, part name, name_th, category name, category name_th, address code, store address shelf, store address remarks, store label, store label_th.
  - If `crossBranch` is false (default), only shows parts from session's branch.
  - Returns full part details with addresses array.
- `GET /parts/:code` – Get part details by code.
  - Returns full part info with nested category, unit, total stock, and addresses (with store info).

#### Bills
- `GET /bills?limit=20&offset=0` – List bills with pagination (requires `bills:read`).
  - Query params: `limit` (1-500, default: 20), `offset` (default: 0).
  - Returns array of bills ordered by `created_at DESC`.
  - Uses `branchId` and `posId` from session (set at login).
- `GET /bills/:id` – Get bill details with items and discounts (requires `bills:read`).
  - Uses `branchId` and `posId` from session (set at login).
  - Returns full bill with `details` (items) and `discounts` arrays.
- `POST /bills` – Create empty bill (requires `bills:write`).
  - No request body required.
  - Uses `branchId` and `posId` from session (set at login).
  - Generates systematic bill ID using `counter` table (format: `YYYYMMDD` + 6-digit counter, e.g., `20251204000001`).
  - Returns `{ "id": "20251204000001" }`.
  - If POS already has a bill with status "new", returns 409 conflict error.
- `PUT /bills/:id/add-item` – Add item to bill by part code (requires `bills:write`).
  - Request body: `{ "partCode": "P0001", "addressCode": "A001", "qty": 1 }`.
  - Validates that part exists in the branch (from session).
  - If item already exists in bill, increments quantity; otherwise inserts new bill item detail.
  - Automatically recalculates bill amounts (purchaseAmount, totalDiscount, totalAmount, vatAmount, xvatAmount).
  - Uses `branchId` and `posId` from session (set at login).
- `PUT /bills/:id/add-item-by-barcode` – Add item to bill by barcode (requires `bills:write`).
  - Request body: `{ "barcode": "1234567890123", "qty": 1 }`.
  - Gets part by barcode, validates it exists in the branch (from session).
  - Uses the default address (is_default=true) for the part. Returns error "no_default_store" if no default is configured.
  - If item already exists in bill, increments quantity; otherwise inserts new bill item detail.
  - Automatically recalculates bill amounts (purchaseAmount, totalDiscount, totalAmount, vatAmount, xvatAmount).
  - Uses `branchId` and `posId` from session (set at login).
- `PUT /bills/:id/remove-item` – Remove item from bill by part code (requires `bills:write`).
  - Request body: `{ "partCode": "P0001", "addressCode": "A001", "qty": 1 (optional, default: 1), "isRemoveAll": false (optional) }`.
  - If `isRemoveAll` is `true`: deletes the item completely (regardless of qty).
  - If `isRemoveAll` is `false` or not provided: removes specified `qty` (default: 1). If qty to remove >= existing qty, deletes the item.
  - Automatically recalculates bill amounts (purchaseAmount, totalDiscount, totalAmount, vatAmount, xvatAmount).
  - Returns 400 if item not found in bill.
  - Uses `branchId` and `posId` from session (set at login).
- `PUT /bills/:id/add-discount` – Apply discount to bill (requires `bills:write`).
  - Request body: `{ "promotionCode": "PROMO001" }`.
  - Validates promotion exists in `promotion_master` table.
  - Supports THB (fixed amount) and percentage discounts.
  - If promotion already exists in bill, updates it; otherwise inserts new discount.
  - Automatically recalculates bill amounts (purchaseAmount, totalDiscount, totalAmount, vatAmount, xvatAmount).
  - Returns 404 if promotion not found.
  - Uses `branchId` and `posId` from session (set at login).
- `PUT /bills/:id/remove-discount` – Remove discount from bill (requires `bills:write`).
  - Request body: `{ "promotionCode": "PROMO001" }`.
  - Validates discount exists in bill.
  - Removes discount from `bill_discount_detail` table.
  - Automatically recalculates bill amounts (purchaseAmount, totalDiscount, totalAmount, vatAmount, xvatAmount).
  - Returns 400 if discount not found in bill.
  - Uses `branchId` and `posId` from session (set at login).
- `PUT /bills/:id/hold` – Hold bill (requires `bills:write`).
  - Changes status from "new" to "hold". Only bills with status "new" can be held.
  - Uses `branchId` and `posId` from session (set at login).
- `PUT /bills/switch` – Switch bills or create new bill (requires `bills:write`).
  - Request body: `{ "targetBillId": "20251204000002" }` (optional).
  - If `targetBillId` is not provided or empty: creates a new bill.
  - If `targetBillId` is provided: switches to that bill (holds current "new" bill, resumes target).
  - Backend automatically finds and holds the current "new" bill for the same POS.
  - Returns full bill details with items and discounts.
  - Uses `branchId` and `posId` from session (set at login).
- `PUT /bills/:id/payment` – Process payment for bill (requires `bills:write`).
  - Request body: `{ "paymentMethod": "cash", "paymentRef": "REF123" }` (both fields optional).
  - Validates bill status must be "new" to process payment.
  - Updates `payment_method`, `payment_ref`, and sets status to "completed".
  - Returns full bill details with updated status.
  - Uses `branchId` and `posId` from session (set at login).
- `PUT /bills/:id/cancel` – Cancel bill (requires `bills:write`).
  - Updates bill status to "cancelled" (does not delete the bill).
  - Only allows cancelling bills with status "new" or "hold".
  - Returns full bill details with updated status.
  - Uses `branchId` and `posId` from session (set at login).
- `DELETE /bills/:id` – Delete bill permanently (requires `bills:delete` permission, admin only).
  - Permanently deletes bill and all related records (cascade delete: bill items, discounts).
  - Cannot be undone.
  - Uses `branchId` and `posId` from session (set at login).

**Bill Status Rules:**
- Bill status must be **"new"** for all modification operations:
  - Adding items (`PUT /bills/:id/add-item`, `PUT /bills/:id/add-item-by-barcode`)
  - Removing items (`PUT /bills/:id/remove-item`)
  - Adding discounts (`PUT /bills/:id/add-discount`)
  - Removing discounts (`PUT /bills/:id/remove-discount`)
  - Processing payment (`PUT /bills/:id/payment`)
- Only one bill with status "new" per POS (enforced in `POST /bills`).
- Returns 400 error if trying to modify a bill that's not "new".

**Bill Amount Calculation:**
All bill amounts are automatically recalculated after any item or discount operation:
- **purchaseAmount**: Sum of (item.price × item.qty) for all items
- **totalDiscount**: Sum of discounts (THB fixed amount or percentage of purchaseAmount)
- **amountAfterDiscount**: purchaseAmount - totalDiscount
- **Tax Calculation** (based on company `taxType`):
  - **xvat** (exclude VAT): `vatAmount = 0`, `totalAmount = amountAfterDiscount`, `xvatAmount = totalAmount`
  - **vat** (price includes VAT): `totalAmount = amountAfterDiscount`, `vatAmount = amountAfterDiscount × (taxRate / (1 + taxRate))`, `xvatAmount = totalAmount - vatAmount`
- When `taxType = "vat"`, part prices already include VAT, so VAT is extracted from the price rather than added

#### Company Settings
- `GET /company` – Get company settings (requires `company:read`).
- `PUT /company` – Update company settings (requires `company:write`).
  - Updates tax information, company name, address, contact details, etc.
  - Company cannot be created or deleted (single record).

#### Branches
- `GET /branches?limit=20&offset=0` – List branches (requires `branch:read`).
- `GET /branches/:id` – Get branch by ID (requires `branch:read`).
  - Returns branch details with `stores` array (all stores linked to the branch via `branch_store`).
- `POST /branches` – Create new branch (requires `branch:write`).
- `PUT /branches/:id` – Update branch (requires `branch:write`).
- `DELETE /branches/:id` – Delete branch (requires `branch:delete`).
  - Cannot delete if only 1 record exists.

#### POS
- `GET /pos?limit=20&offset=0` – List POS (requires `pos:read`).
- `GET /pos/:id` – Get POS by ID (requires `pos:read`).
- `POST /pos` – Create new POS (requires `pos:write`).
- `PUT /pos/:id` – Update POS (requires `pos:write`).
- `DELETE /pos/:id` – Delete POS (requires `pos:delete`).

#### Users
- `GET /users?limit=20&offset=0` – List users (requires `users:read`).
- `GET /users/:id` – Get user by ID (requires `users:read`).
- `POST /users` – Create new user (requires `users:write`).
  - Password is automatically hashed with bcrypt.
- `PUT /users/:id` – Update user (requires `users:write`).
  - Password is optional - only updates if provided.
- `DELETE /users/:id` – Delete user (requires `users:delete`).
  - Cannot delete superusers (`is_superuser=true`).

#### User Branches
- `GET /user-branches/user/:user_id` – List branches for a user (requires `user_branch:read`).
- `GET /user-branches/branch/:branch_id` – List users for a branch (requires `user_branch:read`).
- `GET /user-branches/:user_id/:branch_id` – Get specific user-branch association (requires `user_branch:read`).
- `POST /user-branches` – Create user-branch association (requires `user_branch:write`).
- `DELETE /user-branches/:user_id/:branch_id` – Delete user-branch association (requires `user_branch:write`).

### Systematic ID Generation

The backend uses a unified `counter` table for generating systematic IDs:

- **Bills**: Date-based keys (e.g., `"20251204"`) that reset daily. Bill IDs format: `YYYYMMDD` + 6-digit counter (e.g., `"20251204000001"`).
- **Members**: Static key `"member"` for sequential member codes (e.g., `"000001"`, `"000002"`).

The counter uses atomic SQL operations (`INSERT ... ON CONFLICT DO UPDATE`) to prevent race conditions and ensure unique IDs.

### Database Schema

Key tables:
- `company_setting` - Company information and tax settings (single record)
- `branch_setting` - Branch information (multiple branches per company)
- `pos_setting` - POS terminals (multiple POS per branch)
- `user` - User accounts with roles and superuser flag
- `user_branch` - Many-to-many relationship between users and branches
- `role` - User roles
- `permission` - System permissions
- `role_permission` - Role-permission mappings
- `part_master` - Product/part master data
- `store_master` - Warehouse/store locations (linked to branches)
- `branch_store` - Links branches to stores (many-to-many with is_default flag)
- `address_master` - Stock locations within stores
- `promotion_master` - Discount/promotion definitions (code, details, unit: THB/percentage, amount)
- `bill_master` - Sales transactions (includes purchaseAmount, totalDiscount, totalAmount, vatAmount, xvatAmount)
- `bill_item_detail` - Bill line items
- `bill_discount_detail` - Applied discounts (links bills to promotions)
- `member_master` - Customer/member information
- `session` - Active user sessions

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
│   │   ├── handlers/   # Request handlers (auth, parts, bills, company, branch, pos, users, user_branch, health)
│   │   └── middleware/ # Auth and RBAC middleware
│   └── repository/     # Data access layer (interfaces and PostgreSQL implementations)
└── migrations/         # SQL migration files (up/down)
```

### Permission Structure

Permissions follow the pattern `perm.{resource}.{action}`:

- **Parts**: `perm.parts.read`, `perm.parts.write`, `perm.parts.delete`
- **Bills**: `perm.bills.read`, `perm.bills.write`, `perm.bills.delete`
- **Users**: `perm.users.read`, `perm.users.write`, `perm.users.delete`, `perm.users.mgmt`
- **Roles**: `perm.roles.read`, `perm.roles.write`, `perm.roles.delete`
- **Permissions**: `perm.permissions.read`, `perm.permissions.write`, `perm.permissions.delete`
- **Company**: `perm.company.read`, `perm.company.write`
- **Branch**: `perm.branch.read`, `perm.branch.write`, `perm.branch.delete`
- **POS**: `perm.pos.read`, `perm.pos.write`, `perm.pos.delete`
- **User Branches**: `perm.user_branch.read`, `perm.user_branch.write`

The `role.admin` role automatically receives all permissions. The `role.cashier` role receives limited permissions (parts read, bills read/write).


