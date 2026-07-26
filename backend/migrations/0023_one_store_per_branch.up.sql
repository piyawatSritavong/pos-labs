DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM "store_master"
    GROUP BY "branch_id"
    HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION 'cannot enforce one store per branch: duplicate store_master.branch_id values exist';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM "branch_store"
    GROUP BY "branch_id"
    HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION 'cannot enforce one store per branch: duplicate branch_store.branch_id values exist';
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS "uq_store_master_one_store_per_branch"
  ON "store_master" ("branch_id");

CREATE UNIQUE INDEX IF NOT EXISTS "uq_branch_store_one_store_per_branch"
  ON "branch_store" ("branch_id");

INSERT INTO "counter"("key", "value")
SELECT
  'branch_id',
  COALESCE(MAX(
    CASE WHEN "branch_id" ~ '^[0-9]{5}$' THEN "branch_id"::integer END
  ), -1)
FROM "branch_setting"
ON CONFLICT ("key") DO UPDATE
SET "value" = GREATEST("counter"."value", EXCLUDED."value");
