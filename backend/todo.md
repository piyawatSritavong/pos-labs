# Backend TODO Checklist

## Current Status Summary

### ✅ Completed
- **Authentication**: Login, logout, session management, RBAC
- **Company**: CRUD (Get, Update)
- **Branch**: CRUD (List, Get, Create, Update, Delete) + stores array in Get
- **POS**: CRUD (List, Get, Create, Update, Delete)
- **Users**: CRUD (List, Get, Create, Update, Delete)
- **User Branches**: CRUD (ListByUser, ListByBranch, Get, Create, Delete)
- **Parts**: List, Get, Universal Search
- **Bills**: Create, Get, List, Add/Remove items (with qty), Add/Remove discounts, Hold, Switch
- **Bill Amount Calculation**: Automatic recalculation with VAT logic (xvat and vat modes)

### 🚧 In Progress / Partial
- **Parts**: Update and Delete endpoints missing
- **Bills**: Checkout and Payment are mock implementations, Cancel operation missing
- **User/User Branch**: Still in development (may need refinement)

### ❌ Not Started
- **Promotion Master**: CRUD endpoints (only GetByCode exists in repository)
- **Members**: All endpoints
- **Categories**: CRUD endpoints
- **Addresses**: CRUD endpoints

---

## Project Setup & Structure

- [x] Initialize Go module
- [x] Project structure setup (cmd/, internal/, pkg/, migrations/)
- [x] Configuration management (environment variables)
- [x] Database connection setup (PostgreSQL)
- [x] Logging setup (Gin logger)
- [x] Error handling middleware (Gin recovery)
- [x] Request validation middleware (Gin binding)
- [x] CORS configuration (environment-aware: permissive in dev, strict in production)
- [x] API routing setup

## Database Migrations

- [x] Migration system setup (golang-migrate)
- [x] Users table migration
- [x] Products/PartMaster table migration
- [x] Categories/CategoryMaster table migration
- [x] Addresses/AddressMaster table migration
- [x] Billing/Bills table migration (with amount fields: purchaseAmount, totalDiscount, totalAmount, vatAmount, xvatAmount)
- [x] BillItems table migration (bill_item_detail)
- [x] BillDiscountDetail table migration
- [x] Members table migration
- [x] PromotionMaster table migration
- [x] Company/Branch/POS settings tables migration
- [x] StoreMaster and BranchStore tables migration
- [x] Session table migration
- [x] Role/Permission tables migration
- [ ] PaymentMethods table migration (if needed)
- [ ] Transactions table migration (if needed)
- [ ] Inventory/Stock table migration (if needed)

## Authentication & Authorization

- [x] User login endpoint (`POST /auth/login`)
- [x] Token validation middleware (session-based)
- [x] Password hashing (bcrypt)
- [x] Logout functionality (`POST /auth/logout`)
- [x] Role-based access control (RBAC)
- [x] Permission management
- [x] Session management (database-backed sessions)
- [x] Get current user info (`GET /auth/me`)
- [ ] User registration endpoint (if needed)

## Master Data Management

### PartMaster (Product Management)
- [x] Get product by code endpoint (`GET /parts/:code`)
- [x] List products endpoint (with pagination, `GET /parts`)
- [x] Search products endpoint (universal search, `GET /parts/search`)
  - Searches across: code, barcode, name, name_th, category, store address, etc.
- [ ] Create product endpoint (`POST /parts`)
- [ ] Update product endpoint (`PUT /parts/:code`)
- [ ] Delete product endpoint (`DELETE /parts/:code`)
- [ ] Bulk product operations
- [ ] Product validation

### CategoryMaster
- [ ] Create category endpoint
- [ ] Get category by ID endpoint
- [ ] List categories endpoint
- [ ] Update category endpoint
- [ ] Delete category endpoint
- [ ] Category hierarchy support
- [ ] Get products by category endpoint

### AddressMaster
- [ ] Create address endpoint
- [ ] Get address by ID endpoint
- [ ] List addresses endpoint
- [ ] Update address endpoint
- [ ] Delete address endpoint
- [ ] Address validation
- [ ] Default address management

### Member Management
- [ ] Create member endpoint
- [ ] Get member by ID endpoint
- [ ] Search members endpoint
- [ ] List members endpoint (with pagination)
- [ ] Update member endpoint
- [ ] Delete member endpoint
- [ ] Member points/loyalty system
- [ ] Member address management

## Billing Operations

### Bill Management
- [x] Create new empty bill endpoint (`POST /bills`)
- [x] Get bill by ID endpoint (`GET /bills/:id`)
- [x] List bills endpoint (`GET /bills`)
- [x] Automatic bill amount calculation (purchaseAmount, totalDiscount, totalAmount, vatAmount, xvatAmount)
- [ ] Update bill endpoint (if needed for member assignment, etc.)
- [ ] Add / Remove member to bill
- [ ] Cancel bill endpoint (`PUT /bills/:id/cancel`)

### Bill Items Management
- [x] Add item to bill endpoint (`PUT /bills/:id/add-item`)
- [x] Add item by barcode endpoint (`PUT /bills/:id/add-item-by-barcode`)
- [x] Remove item from bill endpoint (`PUT /bills/:id/remove-item`)
  - Supports optional `qty` parameter (default: 1)
  - Supports `isRemoveAll` flag
- [x] Update item quantity endpoint (via add-item increments, remove-item decrements)
- [x] Get bill items endpoint (included in `GET /bills/:id`)
- [x] Item validation (branch/store validation, default store check)
- [x] Automatic amount recalculation after item changes

### Bill Actions
- [x] Apply discount to bill endpoint (`PUT /bills/:id/add-discount`)
  - Validates promotion from `promotion_master`
  - Supports THB (fixed) and percentage discounts
- [x] Remove discount from bill endpoint (`PUT /bills/:id/remove-discount`)
- [x] Calculate bill totals (automatic recalculation)
  - purchaseAmount, totalDiscount, totalAmount, vatAmount, xvatAmount
  - VAT calculation based on company taxType (xvat/vat)
- [x] Hold bill endpoint (`PUT /bills/:id/hold`)
- [x] Switch bills endpoint (`PUT /bills/switch`)
  - Can create new bill or resume held bill
- [ ] Cancel bill endpoint (`PUT /bills/:id/cancel`)
- [ ] Complete/checkout bill endpoint (`PUT /bills/:id/checkout` - mock implementation)
- [ ] Apply member to bill endpoint (if needed)

### Payment Processing
- [ ] Process payment endpoint (`PUT /bills/:id/payment` - mock implementation)
- [ ] Payment method validation
- [ ] Payment confirmation
- [ ] Receipt generation
- [ ] Transaction recording

## Additional Features

### Inventory Management
- [ ] Stock level tracking
- [ ] Stock update endpoint
- [ ] Low stock alerts
- [ ] Stock adjustment endpoint
- [ ] Stock history tracking
- [ ] Reserve stock on bill creation
- [ ] Release stock on bill cancellation

### Discount Management (Promotion Master)
- [x] Discount calculation logic (THB and percentage)
- [x] Discount validation (promotion exists check)
- [ ] Create promotion endpoint (`POST /promotions`)
- [ ] List promotions endpoint (`GET /promotions`)
- [ ] Get promotion by code endpoint (`GET /promotions/:code`)
- [ ] Update promotion endpoint (`PUT /promotions/:code`)
- [ ] Delete promotion endpoint (`DELETE /promotions/:code`)

### Reports & Analytics
- [ ] Sales report endpoint
- [ ] Daily sales report
- [ ] Weekly sales report
- [ ] Monthly sales report
- [ ] Product sales report
- [ ] Top selling products endpoint
- [ ] Revenue analytics endpoint
- [ ] Transaction history endpoint
- [ ] Export reports (CSV, PDF)

### Settings Management
- [x] Company settings endpoint (`GET /company`, `PUT /company`)
  - Tax configuration (taxRate, taxType)
  - Company information
- [x] Branch settings endpoints (`GET /branches`, `GET /branches/:id`, `POST /branches`, `PUT /branches/:id`, `DELETE /branches/:id`)
- [x] POS settings endpoints (`GET /pos`, `GET /pos/:id`, `POST /pos`, `PUT /pos/:id`, `DELETE /pos/:id`)
- [ ] Store settings endpoint (if needed beyond branch_store)
- [ ] Currency settings endpoint (if needed)
- [ ] Payment methods configuration
- [ ] Receipt template configuration
- [ ] Printer configuration

### Search & Filtering
- [x] Universal search endpoint for parts (`GET /parts/search`)
  - Searches across: code, barcode, name, name_th, category, store address, etc.
  - Supports cross-branch search option
  - Supports category and active status filters
- [ ] Universal search endpoint (members, bills)
- [ ] Advanced filtering for products
- [ ] Search result ranking
- [ ] Search history/cache

## API Endpoints Structure

### Authentication Routes
- [ ] POST /api/auth/register
- [x] POST /api/auth/login
- [x] POST /api/auth/logout
- [x] GET /api/auth/me

### Product Routes (Parts)
- [x] GET /parts (list with pagination)
- [x] GET /parts/:code (get by code)
- [x] GET /parts/search (universal search)
- [ ] POST /parts (create)
- [ ] PUT /parts/:code (update)
- [ ] DELETE /parts/:code (delete)

### Promotion Routes
- [ ] GET /promotions (list)
- [ ] GET /promotions/:code (get by code)
- [ ] POST /promotions (create)
- [ ] PUT /promotions/:code (update)
- [ ] DELETE /promotions/:code (delete)

### Category Routes
- [ ] GET /categories (list)
- [ ] GET /categories/:id (get by id)
- [ ] POST /categories (create)
- [ ] PUT /categories/:id (update)
- [ ] DELETE /categories/:id (delete)

### Address Routes
- [ ] GET /addresses (list)
- [ ] GET /addresses/:code (get by code)
- [ ] POST /addresses (create)
- [ ] PUT /addresses/:code (update)
- [ ] DELETE /addresses/:code (delete)

### Member Routes
- [ ] GET /members (list)
- [ ] GET /members/:id (get by id)
- [ ] POST /members (create)
- [ ] PUT /members/:id (update)
- [ ] DELETE /members/:id (delete)
- [ ] GET /members/search (search)

### Company Routes
- [x] GET /company (get)
- [x] PUT /company (update)

### Branch Routes
- [x] GET /branches (list)
- [x] GET /branches/:id (get with stores)
- [x] POST /branches (create)
- [x] PUT /branches/:id (update)
- [x] DELETE /branches/:id (delete)

### POS Routes
- [x] GET /pos (list)
- [x] GET /pos/:id (get)
- [x] POST /pos (create)
- [x] PUT /pos/:id (update)
- [x] DELETE /pos/:id (delete)

### User Routes
- [x] GET /users (list)
- [x] GET /users/:id (get)
- [x] POST /users (create)
- [x] PUT /users/:id (update)
- [x] DELETE /users/:id (delete)

### User Branch Routes
- [x] GET /user-branches/user/:user_id (list by user)
- [x] GET /user-branches/branch/:branch_id (list by branch)
- [x] GET /user-branches/:user_id/:branch_id (get)
- [x] POST /user-branches (create)
- [x] DELETE /user-branches/:user_id/:branch_id (delete)

### Billing Routes
- [x] POST /bills (create new empty bill)
- [x] GET /bills (list with pagination)
- [x] GET /bills/:id (get bill with details and discounts)
- [x] PUT /bills/:id/add-item (add item by part code)
- [x] PUT /bills/:id/add-item-by-barcode (add item by barcode)
- [x] PUT /bills/:id/remove-item (remove item with optional qty)
- [x] PUT /bills/:id/add-discount (apply discount from promotion_master)
- [x] PUT /bills/:id/remove-discount (remove discount)
- [x] PUT /bills/:id/hold (hold bill)
- [x] PUT /bills/switch (switch bills or create new)
- [ ] PUT /bills/:id/cancel (cancel bill)
- [ ] PUT /bills/:id/checkout (complete bill - mock implementation)
- [ ] PUT /bills/:id/payment (process payment - mock implementation)

## Data Validation & Business Logic

- [x] Input validation for all endpoints (Gin binding)
- [x] Business rule validation (branch/POS access, bill status, etc.)
- [x] Branch/store filtering validation
- [x] Price calculation logic (purchaseAmount from items)
- [x] Tax calculation logic (xvat and vat modes)
  - xvat: vatAmount = 0, totalAmount = amountAfterDiscount
  - vat: Extract VAT from price (price includes VAT)
- [x] Discount calculation logic (THB fixed and percentage)
- [x] Total calculation logic (automatic recalculation)
- [x] Data integrity constraints (foreign keys, ON DELETE CASCADE)
- [ ] Stock availability checks (if needed)

## Error Handling & Logging

- [ ] Centralized error handling
- [ ] Custom error types
- [ ] Error response formatting
- [ ] Request logging
- [ ] Error logging
- [ ] Performance logging
- [ ] Audit trail logging

## Testing

- [ ] Unit tests for business logic
- [ ] Integration tests for API endpoints
- [ ] Database migration tests
- [ ] Authentication tests
- [ ] Billing operation tests
- [ ] Test data fixtures
- [ ] Test coverage reporting

## Documentation

- [ ] API documentation (OpenAPI/Swagger)
- [ ] Database schema documentation
- [ ] Setup and deployment guide
- [ ] Environment variables documentation
- [ ] Code comments and documentation

## Performance & Optimization

- [ ] Database query optimization
- [ ] Index creation for frequently queried fields
- [ ] Caching strategy (Redis if needed)
- [ ] Connection pooling
- [ ] Response pagination
- [ ] Rate limiting
- [ ] Performance monitoring

## Security

- [ ] SQL injection prevention
- [ ] XSS prevention
- [ ] CSRF protection
- [ ] Input sanitization
- [ ] Secure password storage
- [ ] API rate limiting
- [ ] HTTPS enforcement
- [ ] Security headers

