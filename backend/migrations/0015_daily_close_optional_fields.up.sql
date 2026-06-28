ALTER TABLE "daily_close"
  ADD COLUMN IF NOT EXISTS "fuel_amount" decimal(10,2),
  ADD COLUMN IF NOT EXISTS "food_amount" decimal(10,2),
  ADD COLUMN IF NOT EXISTS "transfer_amount" decimal(10,2),
  ADD COLUMN IF NOT EXISTS "special_amount" decimal(10,2),
  ADD COLUMN IF NOT EXISTS "tail_discount_amount" decimal(10,2),
  ADD COLUMN IF NOT EXISTS "final_summary_amount" decimal(10,2),
  ADD COLUMN IF NOT EXISTS "special_note" text,
  ADD COLUMN IF NOT EXISTS "total_credit_term" decimal(10,2) NOT NULL DEFAULT 0;
