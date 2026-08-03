-- The original Min/Max values cannot be reconstructed after the up migration.
ALTER TABLE "address_master"
  ADD COLUMN "min" integer NOT NULL DEFAULT 0,
  ADD COLUMN "max" integer NOT NULL DEFAULT 0;
