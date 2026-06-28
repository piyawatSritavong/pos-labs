-- Inventory Transfer: HQ sends goods to Van
CREATE TABLE IF NOT EXISTS "inventory_transfer" (
  "id" text PRIMARY KEY,
  "from_branch_id" text NOT NULL,
  "to_branch_id" text NOT NULL,
  "created_by" text NOT NULL,
  "status" text NOT NULL DEFAULT 'pending',
  "notes" text NOT NULL DEFAULT '',
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "approved_at" timestamptz,
  "approved_by" text,
  "dispatched_at" timestamptz,
  "dispatched_by" text,
  "received_at" timestamptz,
  "received_by" text,
  CONSTRAINT "FK_inventory_transfer_from_branch" FOREIGN KEY ("from_branch_id") REFERENCES "branch_setting"("branch_id"),
  CONSTRAINT "FK_inventory_transfer_to_branch" FOREIGN KEY ("to_branch_id") REFERENCES "branch_setting"("branch_id"),
  CONSTRAINT "FK_inventory_transfer_created_by" FOREIGN KEY ("created_by") REFERENCES "user"("id"),
  CONSTRAINT "FK_inventory_transfer_approved_by" FOREIGN KEY ("approved_by") REFERENCES "user"("id"),
  CONSTRAINT "FK_inventory_transfer_dispatched_by" FOREIGN KEY ("dispatched_by") REFERENCES "user"("id"),
  CONSTRAINT "FK_inventory_transfer_received_by" FOREIGN KEY ("received_by") REFERENCES "user"("id")
);
CREATE INDEX IF NOT EXISTS "idx_inventory_transfer_status" ON "inventory_transfer"("status");
CREATE INDEX IF NOT EXISTS "idx_inventory_transfer_branches" ON "inventory_transfer"("from_branch_id","to_branch_id");
CREATE INDEX IF NOT EXISTS "idx_inventory_transfer_created_at" ON "inventory_transfer"("created_at" DESC);

CREATE TABLE IF NOT EXISTS "inventory_transfer_item" (
  "transfer_id" text NOT NULL,
  "part_code" text NOT NULL,
  "requested_qty" integer NOT NULL DEFAULT 0,
  "dispatched_qty" integer,
  "received_qty" integer,
  PRIMARY KEY ("transfer_id","part_code"),
  CONSTRAINT "FK_inventory_transfer_item_transfer" FOREIGN KEY ("transfer_id") REFERENCES "inventory_transfer"("id") ON DELETE CASCADE,
  CONSTRAINT "FK_inventory_transfer_item_part" FOREIGN KEY ("part_code") REFERENCES "part_master"("code")
);

-- Stock Count (Physical Inventory Count)
CREATE TABLE IF NOT EXISTS "stock_count" (
  "id" text PRIMARY KEY,
  "branch_id" text NOT NULL,
  "store_id" text NOT NULL,
  "counted_by" text NOT NULL,
  "status" text NOT NULL DEFAULT 'draft',
  "notes" text NOT NULL DEFAULT '',
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "submitted_at" timestamptz,
  CONSTRAINT "FK_stock_count_branch" FOREIGN KEY ("branch_id") REFERENCES "branch_setting"("branch_id"),
  CONSTRAINT "FK_stock_count_counted_by" FOREIGN KEY ("counted_by") REFERENCES "user"("id")
);
CREATE INDEX IF NOT EXISTS "idx_stock_count_branch_status" ON "stock_count"("branch_id","status");
CREATE INDEX IF NOT EXISTS "idx_stock_count_created_at" ON "stock_count"("created_at" DESC);

CREATE TABLE IF NOT EXISTS "stock_count_item" (
  "count_id" text NOT NULL,
  "part_code" text NOT NULL,
  "system_qty" integer NOT NULL DEFAULT 0,
  "counted_qty" integer NOT NULL DEFAULT 0,
  PRIMARY KEY ("count_id","part_code"),
  CONSTRAINT "FK_stock_count_item_count" FOREIGN KEY ("count_id") REFERENCES "stock_count"("id") ON DELETE CASCADE,
  CONSTRAINT "FK_stock_count_item_part" FOREIGN KEY ("part_code") REFERENCES "part_master"("code")
);

-- Daily Close (End of Day)
CREATE TABLE IF NOT EXISTS "daily_close" (
  "id" text PRIMARY KEY,
  "branch_id" text NOT NULL,
  "pos_id" text NOT NULL,
  "closed_by" text NOT NULL,
  "close_date" date NOT NULL,
  "total_sales" decimal(10,2) NOT NULL DEFAULT 0,
  "total_cash" decimal(10,2) NOT NULL DEFAULT 0,
  "total_transfer" decimal(10,2) NOT NULL DEFAULT 0,
  "total_bills" integer NOT NULL DEFAULT 0,
  "total_returns" decimal(10,2) NOT NULL DEFAULT 0,
  "net_amount" decimal(10,2) NOT NULL DEFAULT 0,
  "status" text NOT NULL DEFAULT 'pending_reconciliation',
  "notes" text NOT NULL DEFAULT '',
  "created_at" timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT "FK_daily_close_branch" FOREIGN KEY ("branch_id") REFERENCES "branch_setting"("branch_id"),
  CONSTRAINT "FK_daily_close_closed_by" FOREIGN KEY ("closed_by") REFERENCES "user"("id"),
  UNIQUE ("branch_id","pos_id","close_date")
);
CREATE INDEX IF NOT EXISTS "idx_daily_close_branch_date" ON "daily_close"("branch_id","close_date" DESC);
CREATE INDEX IF NOT EXISTS "idx_daily_close_status" ON "daily_close"("status");

-- Cash Reconciliation (HQ confirms cash from Van)
CREATE TABLE IF NOT EXISTS "cash_reconciliation" (
  "id" text PRIMARY KEY,
  "daily_close_id" text NOT NULL UNIQUE,
  "confirmed_by" text NOT NULL,
  "expected_amount" decimal(10,2) NOT NULL,
  "actual_amount" decimal(10,2) NOT NULL,
  "difference" decimal(10,2) NOT NULL DEFAULT 0,
  "notes" text NOT NULL DEFAULT '',
  "created_at" timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT "FK_cash_reconciliation_daily_close" FOREIGN KEY ("daily_close_id") REFERENCES "daily_close"("id"),
  CONSTRAINT "FK_cash_reconciliation_confirmed_by" FOREIGN KEY ("confirmed_by") REFERENCES "user"("id")
);
CREATE INDEX IF NOT EXISTS "idx_cash_reconciliation_created_at" ON "cash_reconciliation"("created_at" DESC);
