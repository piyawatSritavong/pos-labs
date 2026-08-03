-- Vehicle stock locations live under the POS branch and must coexist with the
-- single user-visible warehouse. Remove the superseded one-store constraint
-- for databases that applied the original migration 0023.
DROP INDEX IF EXISTS "uq_store_master_one_store_per_branch";
DROP INDEX IF EXISTS "uq_branch_store_one_store_per_branch";

ALTER TABLE "store_master"
  ADD COLUMN IF NOT EXISTS "location_type" text NOT NULL DEFAULT 'warehouse';

UPDATE "store_master"
SET "location_type" = CASE WHEN "id" = 'main' THEN 'warehouse' ELSE 'vehicle' END;

ALTER TABLE "store_master"
  DROP CONSTRAINT IF EXISTS "CHK_store_master_location_type";
ALTER TABLE "store_master"
  ADD CONSTRAINT "CHK_store_master_location_type"
  CHECK ("location_type" IN ('warehouse', 'vehicle'));

CREATE UNIQUE INDEX IF NOT EXISTS "uq_store_master_single_warehouse"
  ON "store_master" (("location_type"))
  WHERE "location_type" = 'warehouse';

ALTER TABLE "inventory_transfer"
  ADD COLUMN IF NOT EXISTS "target_pos_id" text,
  ADD COLUMN IF NOT EXISTS "total_sale_value" decimal(14,2) NOT NULL DEFAULT 0;

ALTER TABLE "inventory_transfer_item"
  ADD COLUMN IF NOT EXISTS "sale_price" decimal(10,2),
  ADD COLUMN IF NOT EXISTS "line_total" decimal(14,2);

UPDATE "inventory_transfer" t
SET "target_pos_id" = p."pos_id"
FROM "pos_setting" p
WHERE t."transfer_mode" = 'pos_restock'
  AND t."to_store_id" = p."vehicle_store_id"
  AND COALESCE(t."target_pos_id", '') = '';

UPDATE "inventory_transfer_item" i
SET "sale_price" = p."price",
    "line_total" = COALESCE(i."received_qty", i."dispatched_qty", i."requested_qty", 0) * p."price"
FROM "part_master" p
WHERE i."part_code" = p."code"
  AND i."sale_price" IS NULL;

UPDATE "inventory_transfer" t
SET "total_sale_value" = totals.amount
FROM (
  SELECT "transfer_id", COALESCE(SUM("line_total"), 0) AS amount
  FROM "inventory_transfer_item"
  GROUP BY "transfer_id"
) totals
WHERE t."id" = totals."transfer_id"
  AND t."transfer_mode" = 'pos_restock';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'FK_inventory_transfer_target_pos'
  ) THEN
    ALTER TABLE "inventory_transfer"
      ADD CONSTRAINT "FK_inventory_transfer_target_pos"
      FOREIGN KEY ("target_pos_id") REFERENCES "pos_setting"("pos_id");
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS "idx_inventory_transfer_target_pos_completed"
  ON "inventory_transfer"("target_pos_id", "completed_at" DESC)
  WHERE "transfer_mode" = 'pos_restock' AND "status" = 'completed';

CREATE TABLE IF NOT EXISTS "purchase_order" (
  "id" text PRIMARY KEY,
  "request_id" text NOT NULL UNIQUE,
  "order_date" date NOT NULL,
  "notes" text NOT NULL DEFAULT '',
  "created_by" text NOT NULL,
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "total_cost" decimal(14,2) NOT NULL DEFAULT 0,
  "total_sale_value" decimal(14,2) NOT NULL DEFAULT 0,
  CONSTRAINT "FK_purchase_order_created_by"
    FOREIGN KEY ("created_by") REFERENCES "user"("id")
);

CREATE TABLE IF NOT EXISTS "purchase_order_item" (
  "order_id" text NOT NULL,
  "line_no" integer NOT NULL,
  "part_code" text NOT NULL,
  "part_name" text NOT NULL,
  "bar_code" text NOT NULL,
  "qty" integer NOT NULL,
  "cost" decimal(10,2) NOT NULL,
  "price" decimal(10,2) NOT NULL,
  "min_price" decimal(10,2) NOT NULL,
  "line_cost" decimal(14,2) NOT NULL,
  "line_sale_value" decimal(14,2) NOT NULL,
  PRIMARY KEY ("order_id", "line_no"),
  CONSTRAINT "FK_purchase_order_item_order"
    FOREIGN KEY ("order_id") REFERENCES "purchase_order"("id") ON DELETE CASCADE,
  CONSTRAINT "FK_purchase_order_item_part"
    FOREIGN KEY ("part_code") REFERENCES "part_master"("code"),
  CONSTRAINT "CHK_purchase_order_item_qty" CHECK ("qty" > 0),
  CONSTRAINT "CHK_purchase_order_item_prices"
    CHECK ("cost" >= 0 AND "price" >= 0 AND "min_price" >= 0 AND "min_price" <= "price")
);

CREATE INDEX IF NOT EXISTS "idx_purchase_order_created_at"
  ON "purchase_order"("created_at" DESC);

INSERT INTO "permission"("id", "name", "action", "resource", "detail") VALUES
  ('perm.purchase_orders.read', 'Read purchase orders', 'read', 'purchase_orders', 'Read inbound purchase orders'),
  ('perm.purchase_orders.write', 'Write purchase orders', 'write', 'purchase_orders', 'Create inbound purchase orders')
ON CONFLICT ("id") DO UPDATE SET
  "name" = EXCLUDED."name",
  "action" = EXCLUDED."action",
  "resource" = EXCLUDED."resource",
  "detail" = EXCLUDED."detail";

INSERT INTO "role_permission"("role_id", "permission_id")
SELECT r."id", p."id"
FROM "role" r
CROSS JOIN "permission" p
WHERE r."id" = 'role.admin'
  AND p."id" IN ('perm.purchase_orders.read', 'perm.purchase_orders.write')
ON CONFLICT DO NOTHING;
