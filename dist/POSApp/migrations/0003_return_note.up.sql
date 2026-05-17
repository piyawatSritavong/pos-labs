CREATE TABLE IF NOT EXISTS "return_note_master" (
  "id" text PRIMARY KEY,
  "reference_bill_id" text NOT NULL,
  "purchase_bill_id" text,
  "branch_id" text NOT NULL,
  "pos_id" text NOT NULL,
  "status" text NOT NULL DEFAULT 'completed',
  "settlement_mode" text NOT NULL,
  "payment_method" text,
  "payment_ref" text,
  "member_id" text,
  "customer_name" text NOT NULL DEFAULT 'ทั่วไป',
  "purchase_amount" decimal(10,2) NOT NULL DEFAULT 0,
  "refund_amount" decimal(10,2) NOT NULL DEFAULT 0,
  "net_amount" decimal(10,2) NOT NULL DEFAULT 0,
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "updated_at" timestamptz NOT NULL DEFAULT now(),
  "created_by" text,
  "updated_by" text,
  CONSTRAINT "FK_return_note_master_reference_bill_id"
    FOREIGN KEY ("reference_bill_id")
      REFERENCES "bill_master"("id"),
  CONSTRAINT "FK_return_note_master_purchase_bill_id"
    FOREIGN KEY ("purchase_bill_id")
      REFERENCES "bill_master"("id"),
  CONSTRAINT "FK_return_note_master_branch_id"
    FOREIGN KEY ("branch_id")
      REFERENCES "branch_setting"("branch_id"),
  CONSTRAINT "FK_return_note_master_pos_id"
    FOREIGN KEY ("pos_id")
      REFERENCES "pos_setting"("pos_id"),
  CONSTRAINT "FK_return_note_master_member_id"
    FOREIGN KEY ("member_id")
      REFERENCES "member_master"("id")
      ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS "idx_return_note_master_reference_bill_id"
  ON "return_note_master" ("reference_bill_id");
CREATE INDEX IF NOT EXISTS "idx_return_note_master_created_at"
  ON "return_note_master" ("created_at" DESC);
CREATE INDEX IF NOT EXISTS "idx_return_note_master_branch_pos_status"
  ON "return_note_master" ("branch_id", "pos_id", "status");

CREATE TABLE IF NOT EXISTS "return_note_item_detail" (
  "return_note_id" text NOT NULL,
  "reference_bill_id" text NOT NULL,
  "part_code" text NOT NULL,
  "address_code" text NOT NULL,
  "unit_id" text,
  "unit_label" text,
  "unit_label_th" text,
  "name" text,
  "price" decimal(10,2) NOT NULL DEFAULT 0,
  "qty" integer NOT NULL,
  "line_total" decimal(10,2) NOT NULL DEFAULT 0,
  PRIMARY KEY ("return_note_id", "part_code", "address_code"),
  CONSTRAINT "FK_return_note_item_detail_return_note_id"
    FOREIGN KEY ("return_note_id")
      REFERENCES "return_note_master"("id")
      ON DELETE CASCADE,
  CONSTRAINT "FK_return_note_item_detail_reference_bill_item"
    FOREIGN KEY ("reference_bill_id", "part_code", "address_code")
      REFERENCES "bill_item_detail"("bill_id", "part_code", "address_code")
);

CREATE INDEX IF NOT EXISTS "idx_return_note_item_detail_reference_bill_id"
  ON "return_note_item_detail" ("reference_bill_id");
