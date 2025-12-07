# Bills Endpoints - Logic Summary

## Overview
All bills endpoints use `branchId` and `posId` from the user's session (set at login). Bills are scoped to a specific branch and POS combination.

---

## Read Endpoints (Requires `bills:read` permission)

### 1. `GET /bills` - List Bills
**Logic:**
- Returns paginated list of all bills
- Query parameters: `limit` (1-500, default: 50), `offset` (default: 0)
- Returns bill summary fields (no details/discounts)

**Response:** Array of bill summaries

---

### 2. `GET /bills/:id` - Get Bill Details
**Logic:**
1. Validates bill exists
2. **Access Control:** Verifies bill belongs to session's `branchId` and `posId`
   - If not: Returns 403 "bill_access_denied"
3. Returns full bill with:
   - Bill master fields
   - `details`: Array of bill items (partCode, addressCode, qty, price, etc.)
   - `discounts`: Array of applied discounts

**Response:** Full bill object with details and discounts

---

## Write Endpoints (Requires `bills:write` permission)

### 3. `POST /bills` - Create New Bill
**Logic:**
1. Gets `branchId` and `posId` from session
2. **Validation:** Checks if POS already has a bill with status "new"
   - If yes: Returns 409 "pos_has_active_bill" with `existingBillId`
   - Only one "new" bill per POS at a time
3. Generates bill ID: `YYYYMMDD + 6-digit counter` (e.g., "20251204000001")
4. Creates empty bill with:
   - Status: "new"
   - CustomerName: "ทั่วไป" (default)
   - All amounts: 0
   - Sets `createdBy` and `updatedBy` to current user

**Response:** `{ "id": "bill_id" }`

---

### 4. `PUT /bills/:id/add-item` - Add Item by Part Code
**Logic:**
1. Validates bill access (branchId/posId match)
2. Validates request: `partCode`, `addressCode`, `qty` (min: 1)
3. **Branch Validation:** Checks if part exists in branch's stores (via `branch_store`)
   - If not: Returns 404 "Part does not exist in this branch"
4. Gets part detail (filtered by branch) to get unit/price info
5. Validates `addressCode` exists for the part
6. **Item Management:**
   - If item already exists in bill (same partCode + addressCode): **Increments quantity**
   - Otherwise: **Inserts new bill item**
7. **Automatically recalculates bill amounts** (purchaseAmount, totalDiscount, totalAmount, vatAmount, xvatAmount)
8. Updates bill `updated_at` and `updated_by`

**Response:** `{ "message": "Item added successfully", "billId": "..." }`

---

### 5. `PUT /bills/:id/add-item-by-barcode` - Add Item by Barcode
**Logic:**
1. Validates bill access (branchId/posId match)
2. Validates request: `barcode`, `qty` (min: 1)
3. Gets part by barcode (filtered by branch's stores via `branch_store`)
   - If part not found: Returns 404 "Part with this barcode not found"
4. **Branch Validation:** Checks if addresses exist (empty = part not in branch)
   - If empty: Returns 404 "Part does not exist in this branch"
5. **Default Store Selection:**
   - Finds address with `is_default = true` (from `branch_store`)
   - **If no default store:** Returns 400 "no_default_store" error
     - Message: "Part exists in multiple stores but no default store is configured. Please use add-item endpoint to select a specific store address."
   - Uses default store's address
6. **Item Management:**
   - If item already exists: **Increments quantity**
   - Otherwise: **Inserts new bill item**
7. **Automatically recalculates bill amounts** (purchaseAmount, totalDiscount, totalAmount, vatAmount, xvatAmount)
8. Updates bill `updated_at` and `updated_by`

**Response:** `{ "message": "Item added successfully", "billId": "..." }`

**Error Cases:**
- Part not in branch stores → 404
- No default store configured → 400 "no_default_store" (frontend should use `/add-item`)

---

### 6. `PUT /bills/:id/remove-item` - Remove Item
**Logic:**
1. Validates bill access (branchId/posId match)
2. Validates request: `partCode`, `addressCode`, `qty` (optional, default: 1), `isRemoveAll` (optional, boolean)
3. Checks if item exists in bill
   - If not: Returns 400 "item_not_found"
4. **Removal Logic:**
   - If `isRemoveAll = true`: **Deletes item completely** (regardless of qty)
   - If `isRemoveAll = false` or not provided:
     - Removes specified `qty` (default: 1 if not provided or <= 0)
     - If `qty to remove >= existing qty`: **Deletes item completely**
     - Otherwise: **Decrements quantity by specified qty**
5. **Automatically recalculates bill amounts** (purchaseAmount, totalDiscount, totalAmount, vatAmount, xvatAmount)
6. Updates bill `updated_at` and `updated_by`

**Response:** `{ "message": "Item removed successfully", "billId": "..." }`

---

### 7. `PUT /bills/:id/add-discount` - Add Discount
**Logic:**
1. Validates bill access (branchId/posId match)
2. Validates request: `promotionCode` (required)
3. **Promotion Validation:** Checks if promotion exists in `promotion_master` table
   - If not: Returns 404 "promotion_not_found"
4. Gets promotion details (unit: "THB" or "percentage", amount)
5. **Discount Application:**
   - If promotion already exists in bill: **Updates discount** (overwrites existing)
   - Otherwise: **Inserts new discount** into `bill_discount_detail`
6. **Automatically recalculates bill amounts** (purchaseAmount, totalDiscount, totalAmount, vatAmount, xvatAmount)
7. Updates bill `updated_at` and `updated_by`

**Discount Types:**
- **THB**: Fixed amount discount (e.g., 50 THB off)
- **percentage**: Percentage discount on purchaseAmount (e.g., 10% off)

**Response:** `{ "message": "Discount added successfully", "billId": "..." }`

---

### 8. `PUT /bills/:id/remove-discount` - Remove Discount
**Logic:**
1. Validates bill access (branchId/posId match)
2. Validates request: `promotionCode` (required)
3. **Discount Validation:** Checks if discount exists in bill
   - If not: Returns 400 "discount_not_found"
4. **Removes discount** from `bill_discount_detail` table
5. **Automatically recalculates bill amounts** (purchaseAmount, totalDiscount, totalAmount, vatAmount, xvatAmount)
6. Updates bill `updated_at` and `updated_by`

**Response:** `{ "message": "Discount removed successfully", "billId": "..." }`

---

### 9. `PUT /bills/:id/hold` - Hold Bill
**Logic:**
1. Validates bill access (branchId/posId match)
2. Gets bill to check current status
3. **Status Validation:** Only bills with status "new" can be held
   - If not "new": Returns 400 "invalid_bill_status"
4. Updates bill status to "hold"
5. Updates `updated_by` to current user

**Response:** `{ "message": "bill_held", "billId": "...", "status": "hold" }`

---

### 10. `PUT /bills/switch` - Switch Bills
**Complex endpoint with two modes:**

#### Mode 1: Create New Bill (targetBillId not provided or empty)
**Logic:**
1. Finds current "new" bill for the POS
2. If "new" bill exists: **Holds it first** (status → "hold")
3. Generates new bill ID
4. Creates new bill with status "new"
5. Returns full bill details
6. **Rollback:** If creation fails, resumes held bill back to "new"

**Response:** Full bill object + optional `heldBillId` if a bill was held

#### Mode 2: Switch to Existing Bill (targetBillId provided)
**Logic:**
1. Gets target bill
2. **If target is already "new":** Returns it immediately (no switch needed)
3. **Status Validation:** Target must be "hold" or "new"
   - If not: Returns 400 "invalid_target_bill_status"
4. Finds current "new" bill for the POS
   - If none exists: Returns 400 "no_active_bill"
5. **Switch Process:**
   - Holds current "new" bill (status → "hold")
   - Resumes target bill (status → "new")
6. **Rollback:** If resume fails, resumes held bill back to "new"
7. Returns full bill details of resumed bill

**Response:** Full bill object + optional `heldBillId` if a bill was held

**Use Cases:**
- Create new bill: `{ "targetBillId": "" }` or omit field
- Resume held bill: `{ "targetBillId": "20251204000002" }`

---

### 11. `PUT /bills/:id/checkout` - Complete Bill
**Status:** Mock implementation (placeholder)
**Logic:**
1. Validates bill access
2. Returns success message

**Response:** `{ "message": "bill_checkout_completed", "billId": "...", "status": "completed" }`

---

### 12. `PUT /bills/:id/payment` - Process Payment
**Status:** Mock implementation (placeholder)
**Logic:**
1. Validates bill access
2. Returns success message

**Response:** `{ "message": "payment_processed", "billId": "...", "status": "completed" }`

---

## Common Patterns

### Access Control
All endpoints (except List) validate:
- Bill belongs to session's `branchId` and `posId`
- Returns 403 "bill_access_denied" if mismatch

### Branch/Store Filtering
- `add-item` and `add-item-by-barcode` filter parts by `branch_store` table
- Only parts in stores linked to the branch are accessible
- Default store selection uses `branch_store.is_default` flag

### Bill Status Flow
- **new** → Can be held → **hold**
- **hold** → Can be resumed → **new**
- **new** → Can be completed → **completed**
- Only one "new" bill per POS at a time

### Item Quantity Management
- Adding same item (partCode + addressCode): **Increments quantity**
- Removing item: **Removes specified qty** (default: 1) or **removes completely** based on `isRemoveAll` or if qty to remove >= existing qty

### Bill Amount Calculation
All bill amounts are **automatically recalculated** after any item or discount operation (add-item, remove-item, add-discount, remove-discount).

**Calculation Steps:**
1. **purchaseAmount** = Sum of (item.price × item.qty) for all items
2. **totalDiscount** = Sum of all discounts:
   - THB discounts: Fixed amount
   - Percentage discounts: `purchaseAmount × (percentage / 100)`
3. **amountAfterDiscount** = `purchaseAmount - totalDiscount` (minimum 0)
4. **Tax Calculation** (based on company `taxType` from `company_setting`):
   - **If `taxType = "xvat"`** (exclude VAT):
     - `vatAmount = 0`
     - `totalAmount = amountAfterDiscount`
     - `xvatAmount = totalAmount` (same as totalAmount)
   - **If `taxType = "vat"`** (price includes VAT):
     - `totalAmount = amountAfterDiscount` (price already includes VAT)
     - `vatAmount = amountAfterDiscount × (taxRate / (1 + taxRate))` (extract VAT from price)
     - `xvatAmount = amountAfterDiscount - vatAmount` (price excluding VAT)

**Example (taxType = "vat", taxRate = 0.07):**
- purchaseAmount = 100
- totalDiscount = 0
- amountAfterDiscount = 100
- vatAmount = 100 × (0.07 / 1.07) = 6.54
- xvatAmount = 100 - 6.54 = 93.46
- totalAmount = 100 (customer pays this amount)

### Timestamp Updates
- All write operations update `updated_at` and `updated_by`
- Uses current user ID from session

---

## Key Business Rules

1. **One Active Bill Per POS:** Only one bill with status "new" per POS
2. **Branch Scoping:** Bills are scoped to branch + POS combination
3. **Store Filtering:** Parts must exist in branch's stores (via `branch_store`)
4. **Default Store Required:** Barcode scanning requires a default store to be configured
5. **Item Uniqueness:** Items are unique by `(billId, partCode, addressCode)` combination
6. **Automatic Amount Recalculation:** Bill amounts are recalculated automatically after any item or discount change
7. **VAT Handling:** When `taxType = "vat"`, part prices already include VAT, so VAT is extracted rather than added

