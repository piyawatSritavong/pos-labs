-- Restock lines had no position of their own, so the document sorted them by
-- part code. HQ checking a slip against what the van staff typed had to hunt
-- line by line because the two lists were in different orders.
--
-- line_no is the order the items were added on the POS, carried through submit,
-- review and the printed slip.

ALTER TABLE "inventory_transfer_item"
  ADD COLUMN IF NOT EXISTS "line_no" integer NOT NULL DEFAULT 0;

-- Existing documents keep the order they have been displaying in, so a slip
-- printed before and after this migration reads the same.
WITH ordered AS (
  SELECT "transfer_id", "part_code",
         ROW_NUMBER() OVER (
           PARTITION BY "transfer_id" ORDER BY "part_code"
         ) AS position
  FROM "inventory_transfer_item"
)
UPDATE "inventory_transfer_item" i
SET "line_no" = ordered.position
FROM ordered
WHERE i."transfer_id" = ordered."transfer_id"
  AND i."part_code" = ordered."part_code"
  AND i."line_no" = 0;

CREATE INDEX IF NOT EXISTS "idx_inventory_transfer_item_line_no"
  ON "inventory_transfer_item" ("transfer_id", "line_no");
