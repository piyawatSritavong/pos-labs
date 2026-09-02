DROP INDEX IF EXISTS "idx_part_master_merged_into";
ALTER TABLE "part_master" DROP CONSTRAINT IF EXISTS "CK_part_master_merged_into_not_self";
ALTER TABLE "part_master" DROP CONSTRAINT IF EXISTS "FK_part_master_merged_into";
ALTER TABLE "part_master" DROP COLUMN IF EXISTS "merged_into";
