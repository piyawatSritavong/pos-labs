-- The same product had been entered several times over the life of the
-- catalog, once per naming habit — "ตะปู 1*17" and "ตะปู 1×17", "แบต TS8809"
-- and "แบต TS-8809". Merging them archives the duplicates, but their barcodes
-- are printed on labels already stuck to goods on the vans, and scanning one
-- would report a product with no stock anywhere.
--
-- merged_into records where a duplicate's stock went, so its old label still
-- rings up the surviving product. It always points at the final survivor, so a
-- lookup never has to follow a chain.

ALTER TABLE "part_master"
  ADD COLUMN IF NOT EXISTS "merged_into" text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'FK_part_master_merged_into'
  ) THEN
    ALTER TABLE "part_master"
      ADD CONSTRAINT "FK_part_master_merged_into"
      FOREIGN KEY ("merged_into") REFERENCES "part_master"("code");
  END IF;
END $$;

-- A product cannot be merged into itself.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'CK_part_master_merged_into_not_self'
  ) THEN
    ALTER TABLE "part_master"
      ADD CONSTRAINT "CK_part_master_merged_into_not_self"
      CHECK ("merged_into" IS NULL OR "merged_into" <> "code");
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS "idx_part_master_merged_into"
  ON "part_master" ("merged_into") WHERE "merged_into" IS NOT NULL;
