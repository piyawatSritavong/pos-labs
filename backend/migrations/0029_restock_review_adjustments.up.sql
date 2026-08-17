-- HQ reviews a restock against the paper slip the van staff wrote out by hand.
-- When the two disagree the reviewer has to be able to correct the quantity to
-- what is actually being issued — and say why — without destroying what was
-- originally asked for.
--
-- approved_qty NULL means "not adjusted": the requested quantity stands. Keeping
-- the request and the adjustment in separate columns is the point; overwriting
-- requested_qty would erase the very discrepancy the reviewer is documenting.

ALTER TABLE "inventory_transfer_item"
  ADD COLUMN IF NOT EXISTS "approved_qty" integer,
  ADD COLUMN IF NOT EXISTS "remarks" text NOT NULL DEFAULT '';

ALTER TABLE "inventory_transfer_item"
  DROP CONSTRAINT IF EXISTS "CHK_inventory_transfer_item_approved_qty";
ALTER TABLE "inventory_transfer_item"
  ADD CONSTRAINT "CHK_inventory_transfer_item_approved_qty"
  CHECK ("approved_qty" IS NULL OR "approved_qty" >= 0);
