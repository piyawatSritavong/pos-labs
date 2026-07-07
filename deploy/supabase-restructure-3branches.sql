-- =============================================================================
-- deploy/supabase-restructure-3branches.sql
--
-- Consolidate to exactly 3 branches, each with its own single store & POS:
--   00000 "สาขาหลัก"  -> store 'main'           (คลังหลัก)        POS003 admin
--   00002 "สาขา pos1" -> store 'vehicle_POS001' (คลังสาขา pos1)  POS001 pos1   [NEW branch]
--   00001 "สาขา pos2" -> store 'store_00001'    (คลังสาขา pos2)  POS002 pos2
--
-- Removes the leftover mock stores (tmp_store, no_default_store). Idempotent &
-- transactional. Assumes deploy/supabase-sync-accounts.sql already ran.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

-- 1) New branch 00002 for pos1 (same company as the main branch).
INSERT INTO "branch_setting"(branch_id, company_id, branch_name, branch_name_th, branch_address, branch_address_th, phone, email)
SELECT '00002', (SELECT company_id FROM branch_setting WHERE branch_id='00000'),
       'POS1 Branch', 'สาขา pos1', '', '', '', NULL
WHERE NOT EXISTS (SELECT 1 FROM branch_setting WHERE branch_id='00002');

-- 2) Clear, consistent names for the 3 stores + 2 branches we keep.
UPDATE branch_setting SET branch_name_th='สาขา pos2', branch_name='POS2 Branch' WHERE branch_id='00001';
UPDATE store_master SET label_th='คลังหลัก',      label='Main Warehouse' WHERE id='main';
UPDATE store_master SET label_th='คลังสาขา pos2', label='POS2 Store'      WHERE id='store_00001';

-- 3) Move van store 'vehicle_POS001' to branch 00002 and rename it.
UPDATE store_master SET branch_id='00002', label_th='คลังสาขา pos1', label='POS1 Store' WHERE id='vehicle_POS001';
DELETE FROM branch_store WHERE store_id='vehicle_POS001';
INSERT INTO branch_store(branch_id, store_id, is_default)
SELECT '00002','vehicle_POS001', true
WHERE NOT EXISTS (SELECT 1 FROM branch_store WHERE branch_id='00002' AND store_id='vehicle_POS001');

-- 4) pos1 belongs to branch 00002 now; POS001 sits in 00002 and sells from its store.
UPDATE user_branch SET branch_id='00002'
  WHERE user_id=(SELECT id FROM "user" WHERE username='pos1') AND branch_id='00000';
UPDATE pos_setting SET branch_id='00002', vehicle_store_id='vehicle_POS001' WHERE pos_id='POS001';

-- 5) Drop the two leftover mock stores (no bills/transfers reference them).
DELETE FROM address_master WHERE store_id IN ('tmp_store','no_default_store');
DELETE FROM branch_store   WHERE store_id IN ('tmp_store','no_default_store');
DELETE FROM store_master   WHERE id       IN ('tmp_store','no_default_store');

COMMIT;
