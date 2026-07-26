ALTER TABLE "part_master"
  ADD COLUMN IF NOT EXISTS "min_price" decimal(10,2);

UPDATE "part_master"
SET "price" = COALESCE("price", 0),
    "cost" = COALESCE("cost", 0),
    "min_price" = ROUND(COALESCE("price", 0) * 0.90, 2)
WHERE "min_price" IS NULL;

ALTER TABLE "part_master"
  ALTER COLUMN "min_price" SET DEFAULT 0,
  ALTER COLUMN "min_price" SET NOT NULL;

ALTER TABLE "part_master"
  DROP CONSTRAINT IF EXISTS "CHK_part_master_prices";

ALTER TABLE "part_master"
  ADD CONSTRAINT "CHK_part_master_prices"
  CHECK (
    COALESCE("cost", 0) >= 0
    AND COALESCE("price", 0) >= 0
    AND "min_price" >= 0
    AND "min_price" <= COALESCE("price", 0)
  );
