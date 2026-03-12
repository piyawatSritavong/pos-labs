DROP INDEX IF EXISTS "idx_member_master_name";
DROP INDEX IF EXISTS "idx_member_master_phone";

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
      REFERENCES "member_master"("id");
  END IF;
END $$;
