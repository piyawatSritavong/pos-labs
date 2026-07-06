-- Each account can be pinned to its own POS terminal. Login without explicit
-- branchId/posId resolves the terminal from this column first (admin → POS003,
-- pos1 → POS001, pos2 → POS002), so several accounts of the same branch get
-- distinct terminals on the shared web URL.
ALTER TABLE "user" ADD COLUMN IF NOT EXISTS "default_pos_id" text
  REFERENCES "pos_setting"("pos_id");
