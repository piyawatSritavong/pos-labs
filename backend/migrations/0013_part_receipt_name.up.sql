-- =============================================================================
-- 0013_part_receipt_name.up.sql
--
-- Adds production-safe ASCII product names for raw LPT1 receipt printing.
-- UI/cart/customer-display names remain in the existing Thai `name` fields.
-- =============================================================================

ALTER TABLE "part_master"
    ADD COLUMN IF NOT EXISTS "receipt_name" text NOT NULL DEFAULT '';

ALTER TABLE "bill_item_detail"
    ADD COLUMN IF NOT EXISTS "receipt_name" text NOT NULL DEFAULT '';

ALTER TABLE "return_note_item_detail"
    ADD COLUMN IF NOT EXISTS "receipt_name" text NOT NULL DEFAULT '';

-- Safe existing product backfill. Real production data is populated later by
-- seed-real-data.sql with curated receipt names; this placeholder is ASCII and
-- allows the seed to replace it without overwriting real manual receipt names.
UPDATE "part_master"
   SET "receipt_name" = 'ITEM ' || "code"
 WHERE trim(COALESCE("receipt_name", '')) = '';

UPDATE "bill_item_detail" bid
   SET "receipt_name" = COALESCE(NULLIF(pm."receipt_name", ''), 'ITEM ' || bid."part_code")
  FROM "part_master" pm
 WHERE pm."code" = bid."part_code"
   AND trim(COALESCE(bid."receipt_name", '')) = '';

UPDATE "bill_item_detail"
   SET "receipt_name" = 'ITEM ' || "part_code"
 WHERE trim(COALESCE("receipt_name", '')) = '';

UPDATE "return_note_item_detail" ri
   SET "receipt_name" = COALESCE(NULLIF(bid."receipt_name", ''), NULLIF(pm."receipt_name", ''), 'ITEM ' || ri."part_code")
  FROM "bill_item_detail" bid
  LEFT JOIN "part_master" pm ON pm."code" = ri."part_code"
 WHERE bid."bill_id" = ri."reference_bill_id"
   AND bid."part_code" = ri."part_code"
   AND bid."address_code" = ri."address_code"
   AND trim(COALESCE(ri."receipt_name", '')) = '';

UPDATE "return_note_item_detail"
   SET "receipt_name" = 'ITEM ' || "part_code"
 WHERE trim(COALESCE("receipt_name", '')) = '';
