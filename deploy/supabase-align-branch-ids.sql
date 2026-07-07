-- =============================================================================
-- deploy/supabase-align-branch-ids.sql
--
-- Make the branch id match the POS number (previously reversed):
--   00000 สาขาหลัก  -> คลังหลัก (main)          POS003 / admin
--   00001 สาขา pos1 -> คลังสาขา pos1 (vehicle_POS001) POS001 / pos1
--   00002 สาขา pos2 -> คลังสาขา pos2 (store_00001)    POS002 / pos2
--
-- Swaps everything (store, POS, user_branch, branch name) between 00001 and
-- 00002, and lists admin under the main branch. Every UPDATE sets an absolute
-- value keyed by store id / pos id / username, so the script is idempotent.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

-- Branch names: 00001 = pos1, 00002 = pos2.
UPDATE branch_setting SET branch_name='POS1 Branch', branch_name_th='สาขา pos1' WHERE branch_id='00001';
UPDATE branch_setting SET branch_name='POS2 Branch', branch_name_th='สาขา pos2' WHERE branch_id='00002';

-- Stores move with their POS: คลังสาขา pos1 -> 00001, คลังสาขา pos2 -> 00002.
UPDATE store_master  SET branch_id='00001' WHERE id='vehicle_POS001';
UPDATE store_master  SET branch_id='00002' WHERE id='store_00001';
UPDATE branch_store  SET branch_id='00001' WHERE store_id='vehicle_POS001';
UPDATE branch_store  SET branch_id='00002' WHERE store_id='store_00001';

-- POS terminals follow their store's branch.
UPDATE pos_setting SET branch_id='00001' WHERE pos_id='POS001';
UPDATE pos_setting SET branch_id='00002' WHERE pos_id='POS002';

-- Staff branch assignment.
UPDATE user_branch SET branch_id='00001' WHERE user_id=(SELECT id FROM "user" WHERE username='pos1');
UPDATE user_branch SET branch_id='00002' WHERE user_id=(SELECT id FROM "user" WHERE username='pos2');

-- admin appears under the main branch (00000).
INSERT INTO user_branch(user_id, branch_id)
SELECT id, '00000' FROM "user" WHERE username='admin'
ON CONFLICT DO NOTHING;

COMMIT;
