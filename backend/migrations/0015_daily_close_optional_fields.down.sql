ALTER TABLE "daily_close"
  DROP COLUMN IF EXISTS "total_credit_term",
  DROP COLUMN IF EXISTS "special_note",
  DROP COLUMN IF EXISTS "final_summary_amount",
  DROP COLUMN IF EXISTS "tail_discount_amount",
  DROP COLUMN IF EXISTS "special_amount",
  DROP COLUMN IF EXISTS "transfer_amount",
  DROP COLUMN IF EXISTS "food_amount",
  DROP COLUMN IF EXISTS "fuel_amount";
