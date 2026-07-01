-- Allow multiple daily closes per branch/pos/date (shift-based closing).
-- Previously a UNIQUE (branch_id, pos_id, close_date) constraint limited each
-- POS to a single close per calendar day. With the shift model, each close
-- captures the sales made since the previous close, so a POS can close several
-- times a day. Drop the constraint; the primary key on "id" still guarantees
-- row uniqueness.
ALTER TABLE "daily_close"
  DROP CONSTRAINT IF EXISTS "daily_close_branch_id_pos_id_close_date_key";
