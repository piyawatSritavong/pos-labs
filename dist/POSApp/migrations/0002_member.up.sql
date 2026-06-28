-- Ensure member_master exists and member phone is uniquely searchable.
CREATE TABLE IF NOT EXISTS "member_master" (
  "id" text PRIMARY KEY,
  "code" text,
  "name" text,
  "phone" text UNIQUE NOT NULL,
  "email" text,
  "points" integer NOT NULL DEFAULT 0,
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "updated_at" timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS "idx_member_master_phone" ON "member_master" ("phone");
CREATE INDEX IF NOT EXISTS "idx_member_master_name" ON "member_master" ("name");

-- Ensure bill_master.member_id references member_master.id and clears on member deletion.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'FK_bill_master_member_id'
      AND conrelid = 'bill_master'::regclass
  ) THEN
    ALTER TABLE "bill_master" DROP CONSTRAINT "FK_bill_master_member_id";
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'FK_bill_master_member_id'
      AND conrelid = 'bill_master'::regclass
  ) THEN
    ALTER TABLE "bill_master"
      ADD CONSTRAINT "FK_bill_master_member_id"
      FOREIGN KEY ("member_id")
      REFERENCES "member_master"("id")
      ON DELETE SET NULL;
  END IF;
END $$;
