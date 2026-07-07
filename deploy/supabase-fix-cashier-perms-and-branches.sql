-- =============================================================================
-- deploy/supabase-fix-cashier-perms-and-branches.sql
--
-- One-time production fix for data that a backoffice "edit user" save corrupted:
--   1. pos1/pos2 had custom_permissions = '{}' (empty override) which stripped
--      every permission — the POS then got "forbidden" on all endpoints and
--      could not load its store's products. Reset to NULL so they inherit the
--      role.cashier permissions again.
--   2. Branch names / user_branch were left inconsistent with each POS's store,
--      so the store dropdown showed e.g. "คลังสาขา pos2 (สาขา pos1)". Align them:
--         00002 สาขา pos1 -> คลังสาขา pos1 (vehicle_POS001) -> POS001 / pos1
--         00001 สาขา pos2 -> คลังสาขา pos2 (store_00001)    -> POS002 / pos2
--
-- The underlying UI bug (empty permission override on cashier edit) is fixed in
-- code: frontend _defaultPermsForRole now knows role.cashier and never sends an
-- empty override. Idempotent & transactional.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

-- 1) Restore role-based permissions (drop the empty '{}' override).
UPDATE "user" SET custom_permissions = NULL WHERE username IN ('pos1', 'pos2');

-- 2) Branch names consistent with each branch's store + POS.
UPDATE branch_setting SET branch_name_th = 'สาขา pos1', branch_name = 'POS1 Branch' WHERE branch_id = '00002';
UPDATE branch_setting SET branch_name_th = 'สาขา pos2', branch_name = 'POS2 Branch' WHERE branch_id = '00001';

-- 3) user_branch consistent with pos_setting.branch_id.
UPDATE user_branch SET branch_id = '00002' WHERE user_id = (SELECT id FROM "user" WHERE username = 'pos1');
UPDATE user_branch SET branch_id = '00001' WHERE user_id = (SELECT id FROM "user" WHERE username = 'pos2');

COMMIT;
