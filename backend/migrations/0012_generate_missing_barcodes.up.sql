-- =============================================================================
-- 0012_generate_missing_barcodes.up.sql
--
-- Auto-generate a barcode for every part that doesn't already have one.
-- Strategy: use the part's own `code` (e.g. 'P0036') as the Code128 barcode.
--
-- - Existing EAN-13 barcodes from the xlsx (~483 rows) are left untouched.
-- - Empty-string rows (~1,083 rows) get bar_code = code.
-- - The Backoffice → "พิมพ์บาร์โค้ด" page renders these via barcode_widget
--   (Code128). The POS bills.AddItemByBarcode handler does an exact SQL
--   match on bar_code so the same value works at scan time.
-- =============================================================================

UPDATE "part_master"
   SET "bar_code" = "code"
 WHERE COALESCE("bar_code", '') = ''
   AND "code" ~ '^P[0-9]+$';
