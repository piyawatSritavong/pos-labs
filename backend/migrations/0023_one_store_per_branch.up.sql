-- The original one-store-per-branch rule was superseded by migration 0025:
-- users manage one warehouse (`main`), while each POS keeps an internal
-- vehicle stock location. A branch can therefore legitimately own both the
-- warehouse and one or more vehicle locations. Drop the legacy indexes if an
-- older environment created them before applying the vehicle-stock model.
DROP INDEX IF EXISTS "uq_store_master_one_store_per_branch";
DROP INDEX IF EXISTS "uq_branch_store_one_store_per_branch";

INSERT INTO "counter"("key", "value")
SELECT
  'branch_id',
  COALESCE(MAX(
    CASE WHEN "branch_id" ~ '^[0-9]{5}$' THEN "branch_id"::integer END
  ), -1)
FROM "branch_setting"
ON CONFLICT ("key") DO UPDATE
SET "value" = GREATEST("counter"."value", EXCLUDED."value");
