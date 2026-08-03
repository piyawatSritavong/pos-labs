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

-- Example products (20 items)
INSERT INTO "part_master"(
    "code", "bar_code", "category_id", "unit_id",
    "name", "name_th", "receipt_name", "details", "cost", "price", "image", "is_active"
)
VALUES 
    ('P0001', '8851000001', 'CAT001', 'pcs', 'Mock Product 01', 'สินค้าทดสอบ 01', 'MOCK PRODUCT 01', 'Mock data item 01', 10.00, 15.00, '', true),
    ('P0002', '8851000002', 'CAT002', 'pcs', 'Mock Product 02', 'สินค้าทดสอบ 02', 'MOCK PRODUCT 02', 'Mock data item 02', 12.00, 18.00, '', true),
    ('P0003', '8851000003', 'CAT003', 'pcs', 'Mock Product 03', 'สินค้าทดสอบ 03', 'MOCK PRODUCT 03', 'Mock data item 03', 14.00, 21.00, '', true),
    ('P0004', '8851000004', 'CAT001', 'pcs', 'Mock Product 04', 'สินค้าทดสอบ 04', 'MOCK PRODUCT 04', 'Mock data item 04', 16.00, 24.00, '', true),
    ('P0005', '8851000005', 'CAT002', 'pcs', 'Mock Product 05', 'สินค้าทดสอบ 05', 'MOCK PRODUCT 05', 'Mock data item 05', 18.00, 27.00, '', true),
    ('P0006', '8851000006', 'CAT003', 'pcs', 'Mock Product 06', 'สินค้าทดสอบ 06', 'MOCK PRODUCT 06', 'Mock data item 06', 20.00, 30.00, '', true),
    ('P0007', '8851000007', 'CAT001', 'pcs', 'Mock Product 07', 'สินค้าทดสอบ 07', 'MOCK PRODUCT 07', 'Mock data item 07', 22.00, 33.00, '', true),
    ('P0008', '8851000008', 'CAT002', 'pcs', 'Mock Product 08', 'สินค้าทดสอบ 08', 'MOCK PRODUCT 08', 'Mock data item 08', 24.00, 36.00, '', true),
    ('P0009', '8851000009', 'CAT003', 'pcs', 'Mock Product 09', 'สินค้าทดสอบ 09', 'MOCK PRODUCT 09', 'Mock data item 09', 26.00, 39.00, '', true),
    ('P0010', '8851000010', 'CAT001', 'pcs', 'Mock Product 10', 'สินค้าทดสอบ 10', 'MOCK PRODUCT 10', 'Mock data item 10', 28.00, 42.00, '', true),
    ('P0011', '8851000011', 'CAT002', 'pcs', 'Mock Product 11', 'สินค้าทดสอบ 11', 'MOCK PRODUCT 11', 'Mock data item 11', 30.00, 45.00, '', true),
    ('P0012', '8851000012', 'CAT003', 'pcs', 'Mock Product 12', 'สินค้าทดสอบ 12', 'MOCK PRODUCT 12', 'Mock data item 12', 32.00, 48.00, '', true),
    ('P0013', '8851000013', 'CAT001', 'pcs', 'Mock Product 13', 'สินค้าทดสอบ 13', 'MOCK PRODUCT 13', 'Mock data item 13', 34.00, 51.00, '', true),
    ('P0014', '8851000014', 'CAT002', 'pcs', 'Mock Product 14', 'สินค้าทดสอบ 14', 'MOCK PRODUCT 14', 'Mock data item 14', 36.00, 54.00, '', true),
    ('P0015', '8851000015', 'CAT003', 'pcs', 'Mock Product 15', 'สินค้าทดสอบ 15', 'MOCK PRODUCT 15', 'Mock data item 15', 38.00, 57.00, '', true),
    ('P0016', '8851000016', 'CAT001', 'pcs', 'Mock Product 16', 'สินค้าทดสอบ 16', 'MOCK PRODUCT 16', 'Mock data item 16', 40.00, 60.00, '', true),
    ('P0017', '8851000017', 'CAT002', 'pcs', 'Mock Product 17', 'สินค้าทดสอบ 17', 'MOCK PRODUCT 17', 'Mock data item 17', 42.00, 63.00, '', true),
    ('P0018', '8851000018', 'CAT003', 'pcs', 'Mock Product 18', 'สินค้าทดสอบ 18', 'MOCK PRODUCT 18', 'Mock data item 18', 44.00, 66.00, '', true),
    ('P0019', '8851000019', 'CAT001', 'pcs', 'Mock Product 19', 'สินค้าทดสอบ 19', 'MOCK PRODUCT 19', 'Mock data item 19', 46.00, 69.00, '', true),
    ('P0020', '8851000020', 'CAT002', 'pcs', 'Mock Product 20', 'สินค้าทดสอบ 20', 'MOCK PRODUCT 20', 'Mock data item 20', 48.00, 72.00, '', true)
ON CONFLICT ("code") DO NOTHING;

-- Add more products as needed following the same pattern:
-- INSERT INTO "part_master"(
--     "code", "bar_code", "category_id", "unit_id",
--     "name", "name_th", "receipt_name", "details", "cost", "price", "image", "is_active"
-- )
-- VALUES 
--     ('P0003', '8850000003', 'CAT003', 'pcs', 
--      'Product 3', 'สินค้า 3', 'PRODUCT 3', 'Product description', 30.00, 45.00, '', true)
-- ON CONFLICT ("code") DO NOTHING;

-- ============================================================================
-- SECTION 5: ADDRESSES (INVENTORY LOCATIONS)
-- ============================================================================
-- Create inventory addresses for products in stores.
-- Each address links a product to a store location with quantity information.
-- Note: The 'main' store for branch '00000' is pre-created by the service.
-- ============================================================================

-- Example addresses (20 items)
INSERT INTO "address_master"(
    "code", "part_code", "store_id", "shelf",
    "qty", "rop", "remarks"
)
VALUES 
    ('ADDR0001', 'P0001', 'main', 'A-01', 100, 20, 'Mock stock location'),
    ('ADDR0002', 'P0002', 'main', 'A-02', 110, 20, 'Mock stock location'),
    ('ADDR0003', 'P0003', 'main', 'A-03', 120, 24, 'Mock stock location'),
    ('ADDR0004', 'P0004', 'main', 'A-04', 130, 26, 'Mock stock location'),
    ('ADDR0005', 'P0005', 'main', 'A-05', 140, 28, 'Mock stock location'),
    ('ADDR0006', 'P0006', 'main', 'A-06', 150, 30, 'Mock stock location'),
    ('ADDR0007', 'P0007', 'main', 'A-07', 160, 32, 'Mock stock location'),
    ('ADDR0008', 'P0008', 'main', 'A-08', 170, 34, 'Mock stock location'),
    ('ADDR0009', 'P0009', 'main', 'A-09', 180, 36, 'Mock stock location'),
    ('ADDR0010', 'P0010', 'main', 'A-10', 190, 38, 'Mock stock location'),
    ('ADDR0011', 'P0011', 'main', 'A-11', 200, 40, 'Mock stock location'),
    ('ADDR0012', 'P0012', 'main', 'A-12', 210, 42, 'Mock stock location'),
    ('ADDR0013', 'P0013', 'main', 'A-13', 220, 44, 'Mock stock location'),
    ('ADDR0014', 'P0014', 'main', 'A-14', 230, 46, 'Mock stock location'),
    ('ADDR0015', 'P0015', 'main', 'A-15', 240, 48, 'Mock stock location'),
    ('ADDR0016', 'P0016', 'main', 'A-16', 250, 50, 'Mock stock location'),
    ('ADDR0017', 'P0017', 'main', 'A-17', 260, 52, 'Mock stock location'),
    ('ADDR0018', 'P0018', 'main', 'A-18', 270, 54, 'Mock stock location'),
    ('ADDR0019', 'P0019', 'main', 'A-19', 280, 56, 'Mock stock location'),
    ('ADDR0020', 'P0020', 'main', 'A-20', 290, 58, 'Mock stock location')
ON CONFLICT ("code") DO NOTHING;

-- Add more addresses as needed. Each product can have multiple addresses
-- (same product in different stores or locations):
-- INSERT INTO "address_master"(
--     "code", "part_code", "store_id", "shelf",
--     "qty", "rop", "remarks"
-- )
-- VALUES 
--     ('ADDR0003', 'P0001', 'main', 'A-03', 50, 10, 'Secondary location')
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
