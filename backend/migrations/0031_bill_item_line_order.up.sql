-- Cart lines had no position of their own, so every read sorted them by part
-- code. Two products scanned a second apart came back in catalog order rather
-- than the order the cashier rang them up, which looks like the list shuffling
-- itself while they work.
--
-- line_no is that position: assigned when the line is first added, and the only
-- thing the reordering endpoint rewrites.

ALTER TABLE "bill_item_detail"
  ADD COLUMN IF NOT EXISTS "line_no" integer NOT NULL DEFAULT 0;

-- Existing bills keep the order they have been displaying in, so a bill opened
-- after this migration looks the same as it did before.
WITH ordered AS (
  SELECT "bill_id", "part_code", "address_code",
         ROW_NUMBER() OVER (
           PARTITION BY "bill_id" ORDER BY "part_code", "address_code"
         ) AS position
  FROM "bill_item_detail"
)
UPDATE "bill_item_detail" d
SET "line_no" = ordered.position
FROM ordered
WHERE d."bill_id" = ordered."bill_id"
  AND d."part_code" = ordered."part_code"
  AND d."address_code" = ordered."address_code"
  AND d."line_no" = 0;

CREATE INDEX IF NOT EXISTS "idx_bill_item_detail_line_no"
  ON "bill_item_detail" ("bill_id", "line_no");
