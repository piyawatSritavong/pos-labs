-- ROP is the single stock threshold. Preserve legacy Min only where no ROP
-- has been configured, then remove the obsolete columns.
UPDATE "address_master"
SET "rop" = COALESCE("min", 0)
WHERE COALESCE("rop", 0) = 0
  AND COALESCE("min", 0) > 0;

ALTER TABLE "address_master"
  DROP COLUMN "min",
  DROP COLUMN "max";
