DROP INDEX IF EXISTS "uq_branch_store_one_store_per_branch";
DROP INDEX IF EXISTS "uq_store_master_one_store_per_branch";
DELETE FROM "counter" WHERE "key" = 'branch_id';
