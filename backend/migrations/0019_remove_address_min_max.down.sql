ALTER TABLE "address_master"
  ADD COLUMN "min" integer,
  ADD COLUMN "max" integer;

UPDATE "address_master"
SET "min" = COALESCE("rop", 0),
    "max" = 0;
