-- Performance indexes for bill_master.
--
-- bill_master previously had no secondary indexes, so listing bills and running
-- date-range reports forced sequential scans on the core transactional table —
-- the dominant cost grows with row count (slow once there are 1,000+ bills).
--
-- Plain CREATE INDEX (not CONCURRENTLY) so it is safe inside the migration
-- runner's transaction; the tables are small enough that the brief lock is fine.

-- Reports filter by created_at only (no branch/pos), e.g. /reports/bills.
CREATE INDEX IF NOT EXISTS "idx_bill_master_created_at"
    ON "bill_master" ("created_at");

-- List endpoint filters by branch + pos and sorts by created_at DESC.
CREATE INDEX IF NOT EXISTS "idx_bill_master_branch_pos_created_at"
    ON "bill_master" ("branch_id", "pos_id", "created_at" DESC);

-- GetNewBillByPOS looks up the open bill for a POS by status.
CREATE INDEX IF NOT EXISTS "idx_bill_master_pos_status"
    ON "bill_master" ("pos_id", "status");
