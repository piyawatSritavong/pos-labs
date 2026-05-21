ALTER TABLE "return_note_item_detail"
    DROP COLUMN IF EXISTS "receipt_name";

ALTER TABLE "bill_item_detail"
    DROP COLUMN IF EXISTS "receipt_name";

ALTER TABLE "part_master"
    DROP COLUMN IF EXISTS "receipt_name";
