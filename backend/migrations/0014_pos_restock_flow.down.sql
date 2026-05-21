DELETE FROM "role_permission"
WHERE "role_id" = 'role.cashier'
  AND "permission_id" IN (
    'perm.branch.read',
    'perm.transfers.read',
    'perm.transfers.write',
    'perm.daily_close.read',
    'perm.daily_close.write'
  );

DROP TABLE IF EXISTS "inventory_transfer_audit";

DROP INDEX IF EXISTS "idx_inventory_transfer_stores";
DROP INDEX IF EXISTS "idx_inventory_transfer_created_by";
DROP INDEX IF EXISTS "idx_inventory_transfer_mode_status";

ALTER TABLE "inventory_transfer"
  DROP CONSTRAINT IF EXISTS "FK_inventory_transfer_completed_by",
  DROP CONSTRAINT IF EXISTS "FK_inventory_transfer_submitted_by",
  DROP CONSTRAINT IF EXISTS "FK_inventory_transfer_to_store",
  DROP CONSTRAINT IF EXISTS "FK_inventory_transfer_from_store";

ALTER TABLE "inventory_transfer"
  DROP COLUMN IF EXISTS "completed_by",
  DROP COLUMN IF EXISTS "completed_at",
  DROP COLUMN IF EXISTS "submitted_by",
  DROP COLUMN IF EXISTS "submitted_at",
  DROP COLUMN IF EXISTS "to_store_id",
  DROP COLUMN IF EXISTS "from_store_id",
  DROP COLUMN IF EXISTS "transfer_mode";

ALTER TABLE "pos_setting"
  DROP CONSTRAINT IF EXISTS "FK_pos_setting_vehicle_store",
  DROP COLUMN IF EXISTS "vehicle_store_id";
