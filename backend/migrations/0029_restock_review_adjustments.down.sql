ALTER TABLE "inventory_transfer_item"
  DROP CONSTRAINT IF EXISTS "CHK_inventory_transfer_item_approved_qty";
ALTER TABLE "inventory_transfer_item"
  DROP COLUMN IF EXISTS "approved_qty",
  DROP COLUMN IF EXISTS "remarks";
