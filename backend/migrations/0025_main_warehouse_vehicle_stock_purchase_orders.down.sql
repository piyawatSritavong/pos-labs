DELETE FROM "role_permission"
WHERE "permission_id" IN ('perm.purchase_orders.read', 'perm.purchase_orders.write');
DELETE FROM "permission"
WHERE "id" IN ('perm.purchase_orders.read', 'perm.purchase_orders.write');

DROP TABLE IF EXISTS "purchase_order_item";
DROP TABLE IF EXISTS "purchase_order";

DROP INDEX IF EXISTS "idx_inventory_transfer_target_pos_completed";
ALTER TABLE "inventory_transfer" DROP CONSTRAINT IF EXISTS "FK_inventory_transfer_target_pos";
ALTER TABLE "inventory_transfer_item"
  DROP COLUMN IF EXISTS "line_total",
  DROP COLUMN IF EXISTS "sale_price";
ALTER TABLE "inventory_transfer"
  DROP COLUMN IF EXISTS "total_sale_value",
  DROP COLUMN IF EXISTS "target_pos_id";

DROP INDEX IF EXISTS "uq_store_master_single_warehouse";
ALTER TABLE "store_master" DROP CONSTRAINT IF EXISTS "CHK_store_master_location_type";
ALTER TABLE "store_master" DROP COLUMN IF EXISTS "location_type";
