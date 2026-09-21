-- Production one-off for environments where AUTO_MIGRATE is disabled.
-- Mirrors migration 0034. Safe to run again after it succeeds.
--
-- Usage:
--   psql "$DATABASE_URL" -f deploy/supabase-prevent-duplicate-stock-locations.sql

BEGIN;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM "address_master"
    WHERE "is_active" = true
    GROUP BY "part_code", "store_id"
    HAVING COUNT(*) > 1
  ) THEN
    RAISE EXCEPTION
      'duplicate active stock locations found for the same part/store; reconcile them before adding the unique index';
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS "uq_address_master_active_part_store"
  ON "address_master" ("part_code", "store_id")
  WHERE "is_active" = true;

COMMIT;
