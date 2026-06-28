ALTER TABLE "pos_setting"
  ADD COLUMN IF NOT EXISTS "vehicle_store_id" text;

INSERT INTO "store_master"("id", "branch_id", "label", "label_th", "is_default")
SELECT
  'vehicle_' || p."pos_id",
  p."branch_id",
  COALESCE(NULLIF(p."pos_name", ''), p."pos_id") || ' Vehicle Store',
  COALESCE(NULLIF(p."pos_name", ''), p."pos_id") || ' รถ',
  false
FROM "pos_setting" p
WHERE COALESCE(p."vehicle_store_id", '') = ''
ON CONFLICT ("id") DO NOTHING;

INSERT INTO "branch_store"("branch_id", "store_id", "is_default")
SELECT p."branch_id", 'vehicle_' || p."pos_id", false
FROM "pos_setting" p
WHERE COALESCE(p."vehicle_store_id", '') = ''
ON CONFLICT ("branch_id", "store_id") DO NOTHING;

UPDATE "pos_setting"
SET "vehicle_store_id" = 'vehicle_' || "pos_id"
WHERE COALESCE("vehicle_store_id", '') = '';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'FK_pos_setting_vehicle_store'
  ) THEN
    ALTER TABLE "pos_setting"
      ADD CONSTRAINT "FK_pos_setting_vehicle_store"
      FOREIGN KEY ("vehicle_store_id") REFERENCES "store_master"("id");
  END IF;
END $$;

ALTER TABLE "inventory_transfer"
  ADD COLUMN IF NOT EXISTS "transfer_mode" text NOT NULL DEFAULT 'standard',
  ADD COLUMN IF NOT EXISTS "from_store_id" text,
  ADD COLUMN IF NOT EXISTS "to_store_id" text,
  ADD COLUMN IF NOT EXISTS "submitted_at" timestamptz,
  ADD COLUMN IF NOT EXISTS "submitted_by" text,
  ADD COLUMN IF NOT EXISTS "completed_at" timestamptz,
  ADD COLUMN IF NOT EXISTS "completed_by" text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'FK_inventory_transfer_from_store'
  ) THEN
    ALTER TABLE "inventory_transfer"
      ADD CONSTRAINT "FK_inventory_transfer_from_store"
      FOREIGN KEY ("from_store_id") REFERENCES "store_master"("id");
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'FK_inventory_transfer_to_store'
  ) THEN
    ALTER TABLE "inventory_transfer"
      ADD CONSTRAINT "FK_inventory_transfer_to_store"
      FOREIGN KEY ("to_store_id") REFERENCES "store_master"("id");
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'FK_inventory_transfer_submitted_by'
  ) THEN
    ALTER TABLE "inventory_transfer"
      ADD CONSTRAINT "FK_inventory_transfer_submitted_by"
      FOREIGN KEY ("submitted_by") REFERENCES "user"("id");
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'FK_inventory_transfer_completed_by'
  ) THEN
    ALTER TABLE "inventory_transfer"
      ADD CONSTRAINT "FK_inventory_transfer_completed_by"
      FOREIGN KEY ("completed_by") REFERENCES "user"("id");
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS "idx_inventory_transfer_mode_status"
  ON "inventory_transfer"("transfer_mode", "status", "created_at" DESC);
CREATE INDEX IF NOT EXISTS "idx_inventory_transfer_created_by"
  ON "inventory_transfer"("created_by", "created_at" DESC);
CREATE INDEX IF NOT EXISTS "idx_inventory_transfer_stores"
  ON "inventory_transfer"("from_store_id", "to_store_id");

CREATE TABLE IF NOT EXISTS "inventory_transfer_audit" (
  "id" bigserial PRIMARY KEY,
  "transfer_id" text NOT NULL,
  "action" text NOT NULL,
  "actor_id" text,
  "notes" text NOT NULL DEFAULT '',
  "created_at" timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT "FK_inventory_transfer_audit_transfer"
    FOREIGN KEY ("transfer_id") REFERENCES "inventory_transfer"("id") ON DELETE CASCADE,
  CONSTRAINT "FK_inventory_transfer_audit_actor"
    FOREIGN KEY ("actor_id") REFERENCES "user"("id")
);

CREATE INDEX IF NOT EXISTS "idx_inventory_transfer_audit_transfer"
  ON "inventory_transfer_audit"("transfer_id", "created_at" DESC);

INSERT INTO "role_permission"("role_id", "permission_id")
SELECT 'role.cashier', p."id"
FROM "permission" p
WHERE p."id" IN (
  'perm.branch.read',
  'perm.transfers.read',
  'perm.transfers.write',
  'perm.daily_close.read',
  'perm.daily_close.write'
)
ON CONFLICT DO NOTHING;
