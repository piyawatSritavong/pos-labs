-- Existing review documents predate submit-time price snapshots. Snapshot the
-- current product price once so the amount reviewed by HQ is stable thereafter.
UPDATE "inventory_transfer_item" i
SET "sale_price" = p."price",
    "line_total" = i."requested_qty" * p."price"
FROM "inventory_transfer" t, "part_master" p
WHERE i."transfer_id" = t."id"
  AND i."part_code" = p."code"
  AND t."transfer_mode" = 'pos_restock'
  AND t."status" = 'review'
  AND i."sale_price" IS NULL;

UPDATE "inventory_transfer_item" i
SET "line_total" = i."requested_qty" * i."sale_price"
FROM "inventory_transfer" t
WHERE i."transfer_id" = t."id"
  AND t."transfer_mode" = 'pos_restock'
  AND t."status" = 'review'
  AND i."sale_price" IS NOT NULL
  AND i."line_total" IS NULL;

UPDATE "inventory_transfer" t
SET "total_sale_value" = totals.amount
FROM (
  SELECT i."transfer_id", COALESCE(SUM(i."line_total"), 0) AS amount
  FROM "inventory_transfer_item" i
  GROUP BY i."transfer_id"
) totals
WHERE t."id" = totals."transfer_id"
  AND t."transfer_mode" = 'pos_restock'
  AND t."status" = 'review';
