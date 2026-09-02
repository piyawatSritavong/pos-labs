DROP INDEX IF EXISTS "idx_inventory_transfer_item_line_no";
ALTER TABLE "inventory_transfer_item" DROP COLUMN IF EXISTS "line_no";
