-- Restore the one-close-per-day uniqueness. Note: this will fail if multiple
-- closes already exist for the same branch/pos/date (created under the shift
-- model); such rows must be de-duplicated first.
ALTER TABLE "daily_close"
  ADD CONSTRAINT "daily_close_branch_id_pos_id_close_date_key"
  UNIQUE ("branch_id", "pos_id", "close_date");
