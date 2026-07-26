ALTER TABLE "part_master"
  DROP CONSTRAINT IF EXISTS "CHK_part_master_prices";

ALTER TABLE "part_master"
  DROP COLUMN IF EXISTS "min_price";
