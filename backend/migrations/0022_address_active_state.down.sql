DROP INDEX IF EXISTS "idx_address_master_active_part_store";

ALTER TABLE "address_master"
  DROP COLUMN IF EXISTS "is_active";
