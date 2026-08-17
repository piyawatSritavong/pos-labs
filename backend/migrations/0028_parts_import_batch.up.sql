-- History for "เพิ่มสินค้าด้วยไฟล์". Without it there is no way to answer the
-- question a user actually asks — "did I already import this file yesterday?"
-- — and the honest answer they reached for instead was to import it again,
-- which doubles every quantity.
--
-- One row per upload that was applied, with the lines it wrote, so the import
-- can be read back like any other stock document.

CREATE TABLE IF NOT EXISTS "parts_import_batch" (
  "id" text PRIMARY KEY,
  -- sha256 of the uploaded bytes: the same spreadsheet uploaded twice is the
  -- mistake this table exists to catch, and only the file itself can prove it.
  "file_hash" text NOT NULL,
  "file_name" text NOT NULL DEFAULT '',
  "file_size" integer NOT NULL DEFAULT 0,
  "store_id" text NOT NULL,
  "created_by" text NOT NULL,
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "created_count" integer NOT NULL DEFAULT 0,
  "updated_count" integer NOT NULL DEFAULT 0,
  "total_qty" integer NOT NULL DEFAULT 0,
  CONSTRAINT "FK_parts_import_batch_user"
    FOREIGN KEY ("created_by") REFERENCES "user"("id"),
  CONSTRAINT "FK_parts_import_batch_store"
    FOREIGN KEY ("store_id") REFERENCES "store_master"("id")
);

CREATE TABLE IF NOT EXISTS "parts_import_batch_item" (
  "batch_id" text NOT NULL,
  "part_code" text NOT NULL,
  -- 'created' or 'updated' — which of the two things this line did.
  "action" text NOT NULL,
  "sheet_row" integer NOT NULL DEFAULT 0,
  "qty" integer NOT NULL DEFAULT 0,
  -- Warehouse quantity before and after, so a line reads as a movement rather
  -- than as a number with no context.
  "qty_before" integer NOT NULL DEFAULT 0,
  "qty_after" integer NOT NULL DEFAULT 0,
  "cost" decimal(10,2) NOT NULL DEFAULT 0,
  "price" decimal(10,2) NOT NULL DEFAULT 0,
  PRIMARY KEY ("batch_id", "part_code"),
  CONSTRAINT "CHK_parts_import_batch_item_action"
    CHECK ("action" IN ('created', 'updated')),
  CONSTRAINT "FK_parts_import_batch_item_batch"
    FOREIGN KEY ("batch_id") REFERENCES "parts_import_batch"("id") ON DELETE CASCADE,
  CONSTRAINT "FK_parts_import_batch_item_part"
    FOREIGN KEY ("part_code") REFERENCES "part_master"("code") ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS "idx_parts_import_batch_created_at"
  ON "parts_import_batch" ("created_at" DESC);

-- Answers "has this exact file been imported before?" in one lookup.
CREATE INDEX IF NOT EXISTS "idx_parts_import_batch_file_hash"
  ON "parts_import_batch" ("file_hash", "created_at" DESC);

CREATE INDEX IF NOT EXISTS "idx_parts_import_batch_item_part"
  ON "parts_import_batch_item" ("part_code");
