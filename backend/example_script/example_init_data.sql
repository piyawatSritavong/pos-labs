-- ============================================================================
-- POS Labs Backend - Example Initialization Data Script for Clients
-- ============================================================================
-- This script provides a template for technicians to create client-specific
-- initialization scripts for business data (categories, products, inventory).
--
-- IMPORTANT NOTES:
-- 1. Run this script AFTER the main service has started (it runs migrations and core seed automatically)
-- 2. Core data (company, branch, POS, users, permissions, roles, units) is automatically
--    seeded by the main service - DO NOT include them in this script
-- 3. This script uses ON CONFLICT DO NOTHING to allow safe re-runs
-- 4. Customize all values below with actual client business data
-- 5. This script only contains business data that clients need to customize
-- ============================================================================

BEGIN;

-- ============================================================================
-- SECTION 1: ADDITIONAL BRANCHES (OPTIONAL)
-- ============================================================================
-- Add additional branches beyond the default main branch (00000).
-- The main branch is automatically created by the service.
-- ============================================================================

-- Example: Second branch (uncomment and customize if needed)
/*
INSERT INTO "branch_setting"(
    "branch_id", "company_id", "branch_name", "branch_name_th",
    "branch_address", "branch_address_th", "phone", "email"
)
VALUES (
    '00001',                            -- Branch ID (5 digits, must be unique)
    '0000000000000',                    -- Must match company_setting.tax_id (from core seed)
    'Second Branch',                    -- Branch name
    'สาขาที่สอง',                        -- Thai branch name
    '456 Second Street',                -- Branch address
    '456 ถนนที่สอง',                     -- Thai branch address
    '02-234-5678',                      -- Branch phone
    'branch2@clientcompany.com'        -- Branch email
)
ON CONFLICT ("branch_id") DO NOTHING;
*/

-- ============================================================================
-- SECTION 2: ADDITIONAL STORES (OPTIONAL)
-- ============================================================================
-- Add additional stores/warehouses beyond the default main store.
-- The main store for branch 00000 is automatically created by the service.
-- ============================================================================

-- Example: Additional store for branch 00000 (uncomment and customize if needed)
/*
INSERT INTO "store_master"("id", "branch_id", "label", "label_th", "is_default")
VALUES ('warehouse2', '00000', 'Warehouse 2', 'คลังที่ 2', false)
ON CONFLICT ("id") DO NOTHING;

INSERT INTO "branch_store"("branch_id", "store_id", "is_default")
VALUES ('00000', 'warehouse2', false)
ON CONFLICT ("branch_id", "store_id") DO NOTHING;
*/

-- ============================================================================
-- SECTION 3: CATEGORIES
-- ============================================================================
-- Create product categories. Customize based on client's product structure.
-- ============================================================================

INSERT INTO "category_master"("id", "label", "label_th")
VALUES 
    ('CAT001', 'Beverages', 'เครื่องดื่ม'),
    ('CAT002', 'Snacks', 'ขนมขบเคี้ยว'),
    ('CAT003', 'Household', 'ของใช้ในบ้าน')
ON CONFLICT ("id") DO NOTHING;

-- Add more categories as needed:
-- INSERT INTO "category_master"("id", "label", "label_th")
-- VALUES ('CAT004', 'Electronics', 'อิเล็กทรอนิกส์')
-- ON CONFLICT ("id") DO NOTHING;

-- ============================================================================
-- SECTION 4: PARTS (PRODUCTS)
-- ============================================================================
-- Create product master data. Customize with actual client products.
-- Each product needs: code, barcode, category, unit, name, price, etc.
-- Note: Units are pre-seeded by the service (pcs, box, case, set, pair, roll, sheet)
-- ============================================================================

-- Example products (customize with actual client products)
INSERT INTO "part_master"(
    "code", "bar_code", "category_id", "unit_id",
    "name", "name_th", "details", "cost", "price", "image", "is_active"
)
VALUES 
    ('P0001', '8850000001', 'CAT001', 'pcs', 
     'Product 1', 'สินค้า 1', 'Product description', 10.00, 15.00, '', true),
    ('P0002', '8850000002', 'CAT002', 'pcs', 
     'Product 2', 'สินค้า 2', 'Product description', 20.00, 30.00, '', true)
ON CONFLICT ("code") DO NOTHING;

-- Add more products as needed following the same pattern:
-- INSERT INTO "part_master"(
--     "code", "bar_code", "category_id", "unit_id",
--     "name", "name_th", "details", "cost", "price", "image", "is_active"
-- )
-- VALUES 
--     ('P0003', '8850000003', 'CAT003', 'pcs', 
--      'Product 3', 'สินค้า 3', 'Product description', 30.00, 45.00, '', true)
-- ON CONFLICT ("code") DO NOTHING;

-- ============================================================================
-- SECTION 5: ADDRESSES (INVENTORY LOCATIONS)
-- ============================================================================
-- Create inventory addresses for products in stores.
-- Each address links a product to a store location with quantity information.
-- Note: The 'main' store for branch '00000' is pre-created by the service.
-- ============================================================================

-- Example addresses (customize with actual inventory locations)
INSERT INTO "address_master"(
    "code", "part_code", "store_id", "shelf",
    "qty", "min", "max", "rop", "remarks"
)
VALUES 
    ('ADDR0001', 'P0001', 'main', 'A-01', 100, 10, 200, 20, 'Main store location'),
    ('ADDR0002', 'P0002', 'main', 'A-02', 150, 15, 250, 25, 'Main store location')
ON CONFLICT ("code") DO NOTHING;

-- Add more addresses as needed. Each product can have multiple addresses
-- (same product in different stores or locations):
-- INSERT INTO "address_master"(
--     "code", "part_code", "store_id", "shelf",
--     "qty", "min", "max", "rop", "remarks"
-- )
-- VALUES 
--     ('ADDR0003', 'P0001', 'main', 'A-03', 50, 5, 100, 10, 'Secondary location')
-- ON CONFLICT ("code") DO NOTHING;

-- ============================================================================
-- SECTION 6: PROMOTIONS (OPTIONAL)
-- ============================================================================
-- Create promotions/discounts. Optional - add if client uses promotions.
-- ============================================================================

-- Example promotions (uncomment and customize if needed)
/*
INSERT INTO "promotion_master"("code", "details", "unit", "amount")
VALUES 
    ('PROMO001', '10% discount', 'percentage', 10),
    ('PROMO002', '50 THB off', 'THB', 50)
ON CONFLICT ("code") DO NOTHING;
*/

-- ============================================================================
-- COMMIT TRANSACTION
-- ============================================================================

COMMIT;

-- ============================================================================
-- POST-SCRIPT NOTES FOR TECHNICIANS:
-- ============================================================================
-- 1. Verify all data was inserted correctly:
--    SELECT COUNT(*) FROM "category_master";
--    SELECT COUNT(*) FROM "part_master";
--    SELECT COUNT(*) FROM "address_master";
--
-- 2. Verify inventory quantities are correct:
--    SELECT "code", "part_code", "store_id", "qty" FROM "address_master";
--
-- 3. Test product search and bill creation through the API
--
-- 4. Create additional products and inventory as needed through the API
--
-- 5. Remember: Core data (company, branch, POS, users) is managed by the
--    main service and should NOT be modified in this script
-- ============================================================================
