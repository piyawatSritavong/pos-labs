-- The printed receipt has to match the slip the shop already hands customers:
-- shop hours under the name, the member discount on its own line, the rounding
-- that makes the total a whole baht, and the cash tendered with the change.
-- None of that was recorded, so the receipt could not show it.

ALTER TABLE "company_setting"
  -- Free text under the shop name, e.g. "เปิดทุกวัน 05.00-20.00น."
  ADD COLUMN IF NOT EXISTS "business_hours" text NOT NULL DEFAULT '',
  -- Percent off for a bill with a member attached. 0 disables the line.
  ADD COLUMN IF NOT EXISTS "member_discount_rate" decimal(5,4) NOT NULL DEFAULT 0,
  -- Whether totals are rounded to a whole baht.
  ADD COLUMN IF NOT EXISTS "round_to_whole_baht" boolean NOT NULL DEFAULT false;

ALTER TABLE "company_setting"
  DROP CONSTRAINT IF EXISTS "CHK_company_setting_member_discount_rate";
ALTER TABLE "company_setting"
  ADD CONSTRAINT "CHK_company_setting_member_discount_rate"
  CHECK ("member_discount_rate" >= 0 AND "member_discount_rate" <= 1);

ALTER TABLE "bill_master"
  -- Split out of total_discount so the receipt can show both lines and the
  -- shop can tell what membership actually cost them.
  ADD COLUMN IF NOT EXISTS "member_discount" decimal(12,2) NOT NULL DEFAULT 0,
  -- What rounding added or removed; total_amount is the rounded figure.
  ADD COLUMN IF NOT EXISTS "rounding_amount" decimal(12,2) NOT NULL DEFAULT 0,
  -- Cash handed over and change given back. NULL for non-cash payments and
  -- for bills taken before this was recorded.
  ADD COLUMN IF NOT EXISTS "cash_received" decimal(12,2),
  ADD COLUMN IF NOT EXISTS "change_amount" decimal(12,2);
