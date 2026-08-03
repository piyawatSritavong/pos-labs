-- ROP is the single low-stock threshold. Preserve legacy Min values only
-- where no explicit reorder point has been configured yet.
UPDATE "address_master"
SET "rop" = "min"
WHERE COALESCE("rop", 0) = 0
  AND COALESCE("min", 0) > 0;

ALTER TABLE "address_master"
  DROP COLUMN "min",
  DROP COLUMN "max";
