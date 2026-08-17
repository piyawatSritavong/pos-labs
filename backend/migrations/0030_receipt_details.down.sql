ALTER TABLE "bill_master"
  DROP COLUMN IF EXISTS "member_discount",
  DROP COLUMN IF EXISTS "rounding_amount",
  DROP COLUMN IF EXISTS "cash_received",
  DROP COLUMN IF EXISTS "change_amount";

ALTER TABLE "company_setting"
  DROP CONSTRAINT IF EXISTS "CHK_company_setting_member_discount_rate";
ALTER TABLE "company_setting"
  DROP COLUMN IF EXISTS "business_hours",
  DROP COLUMN IF EXISTS "member_discount_rate",
  DROP COLUMN IF EXISTS "round_to_whole_baht";
