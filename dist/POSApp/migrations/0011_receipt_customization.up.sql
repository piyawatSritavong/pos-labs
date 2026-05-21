-- =============================================================================
-- 0010_receipt_customization.up.sql
--
-- Adds an editable footer line to the receipt printed by the POS.
-- Header info (company name, address, tax id, phone, website) reuses the
-- existing company_setting columns and the existing Backoffice → Company edit
-- dialog. Only the trailing line at the bottom of the receipt is new.
-- =============================================================================

ALTER TABLE "company_setting"
    ADD COLUMN IF NOT EXISTS "receipt_footer" TEXT NOT NULL DEFAULT '';
