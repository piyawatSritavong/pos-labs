ALTER TABLE "address_master"
  ADD COLUMN IF NOT EXISTS "is_active" boolean NOT NULL DEFAULT true;

UPDATE "address_master"
SET "is_active" = false
WHERE "remarks" LIKE 'archived by catalog replacement %';

CREATE INDEX IF NOT EXISTS "idx_address_master_active_part_store"
  ON "address_master" ("part_code", "store_id")
  WHERE "is_active" = true;
