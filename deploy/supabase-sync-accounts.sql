-- =============================================================================
-- deploy/supabase-sync-accounts.sql
--
-- One-time production data reconciliation for the Supabase DB behind
-- pos-labs.vercel.app / pos-labs.onrender.com (branch client-ppsale/demo).
--
-- WHY THIS EXISTS
--   The seed code (backend/internal/db/seed*.go) only runs on an EMPTY database
--   (it skips when data already exists). Production was seeded long ago, so the
--   3-POS account changes made on this branch never reached it: hqmanager was
--   still present, pos2 / POS002 / POS003 were missing, and default_pos_id was
--   NULL for everyone. This script brings production in line with the local
--   mock seed and the intended terminal/stock mapping:
--       admin -> POS003  (branch 00000, stock 'main')
--       pos1  -> POS001  (branch 00000, stock 'main')
--       pos2  -> POS002  (branch 00001, stock 'store_00001')
--
-- SAFE TO RE-RUN: every statement is guarded (WHERE NOT EXISTS / ON CONFLICT /
-- id-scoped UPDATE), wrapped in a single transaction with ON_ERROR_STOP.
--
-- HOW TO RUN
--   psql "$DATABASE_URL" -f deploy/supabase-sync-accounts.sql
--   (or pipe through a postgres container if psql isn't installed locally)
--
-- NOTE: migrations 0018 (concurrent sessions) and 0019 (user.default_pos_id)
-- must already be applied (schema_migrations version >= 19).
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

-- 1) Remove hqmanager. It has HQ history (inventory_transfer approvals, etc.),
--    so reassign every reference to admin first to preserve history and satisfy
--    the *_by/actor FKs, then delete the account.
UPDATE cash_reconciliation      SET confirmed_by  = (SELECT id FROM "user" WHERE username='admin') WHERE confirmed_by  = (SELECT id FROM "user" WHERE username='hqmanager');
UPDATE daily_close              SET closed_by     = (SELECT id FROM "user" WHERE username='admin') WHERE closed_by     = (SELECT id FROM "user" WHERE username='hqmanager');
UPDATE inventory_transfer       SET approved_by   = (SELECT id FROM "user" WHERE username='admin') WHERE approved_by   = (SELECT id FROM "user" WHERE username='hqmanager');
UPDATE inventory_transfer       SET completed_by  = (SELECT id FROM "user" WHERE username='admin') WHERE completed_by  = (SELECT id FROM "user" WHERE username='hqmanager');
UPDATE inventory_transfer       SET created_by    = (SELECT id FROM "user" WHERE username='admin') WHERE created_by    = (SELECT id FROM "user" WHERE username='hqmanager');
UPDATE inventory_transfer       SET dispatched_by = (SELECT id FROM "user" WHERE username='admin') WHERE dispatched_by = (SELECT id FROM "user" WHERE username='hqmanager');
UPDATE inventory_transfer       SET received_by   = (SELECT id FROM "user" WHERE username='admin') WHERE received_by   = (SELECT id FROM "user" WHERE username='hqmanager');
UPDATE inventory_transfer       SET submitted_by  = (SELECT id FROM "user" WHERE username='admin') WHERE submitted_by  = (SELECT id FROM "user" WHERE username='hqmanager');
UPDATE inventory_transfer_audit SET actor_id      = (SELECT id FROM "user" WHERE username='admin') WHERE actor_id      = (SELECT id FROM "user" WHERE username='hqmanager');
UPDATE stock_count              SET counted_by    = (SELECT id FROM "user" WHERE username='admin') WHERE counted_by    = (SELECT id FROM "user" WHERE username='hqmanager');
DELETE FROM "session"     WHERE user_id = (SELECT id FROM "user" WHERE username='hqmanager');
DELETE FROM "user_branch" WHERE user_id = (SELECT id FROM "user" WHERE username='hqmanager');
DELETE FROM "user"        WHERE username='hqmanager';

-- 2) Create pos2 (branch 00001). Reuse pos1's bcrypt hash — same password 'pos123456'.
INSERT INTO "user"(id, username, role_id, name, password, is_active, is_superuser)
SELECT replace(gen_random_uuid()::text,'-',''), 'pos2', 'role.cashier', 'POS Cashier 2',
       (SELECT password FROM "user" WHERE username='pos1'), true, false
WHERE NOT EXISTS (SELECT 1 FROM "user" WHERE username='pos2');

INSERT INTO "user_branch"(user_id, branch_id)
SELECT id, '00001' FROM "user" WHERE username='pos2'
ON CONFLICT DO NOTHING;

-- 3) POS terminals. Reuse POS001's pos_secret (NOT NULL column; shared-URL login
--    resolves the terminal via default_pos_id and does not check the secret).
INSERT INTO "pos_setting"(pos_id, branch_id, pos_name, pos_secret, is_active, vehicle_store_id)
SELECT 'POS002','00001','POS 2',(SELECT pos_secret FROM pos_setting WHERE pos_id='POS001'),true,'store_00001'
WHERE NOT EXISTS (SELECT 1 FROM pos_setting WHERE pos_id='POS002');

INSERT INTO "pos_setting"(pos_id, branch_id, pos_name, pos_secret, is_active, vehicle_store_id)
SELECT 'POS003','00000','POS สำนักงาน',(SELECT pos_secret FROM pos_setting WHERE pos_id='POS001'),true,'main'
WHERE NOT EXISTS (SELECT 1 FROM pos_setting WHERE pos_id='POS003');

-- 4) POS001 sells from 'main' (match local; admin POS003 + pos1 POS001 share stock 1).
UPDATE pos_setting SET vehicle_store_id='main' WHERE pos_id='POS001';

-- 5) Pin each account to its terminal (login auto-resolve reads default_pos_id).
UPDATE "user" SET default_pos_id='POS003' WHERE username='admin';
UPDATE "user" SET default_pos_id='POS001' WHERE username='pos1';
UPDATE "user" SET default_pos_id='POS002' WHERE username='pos2';

-- 6) Stock the second-branch store (store_00001) with every product it lacks,
--    so pos2 has a fully functional catalog like the main branch.
INSERT INTO "address_master"(code, part_code, store_id, shelf, qty, rop, remarks)
SELECT 'S2-'||p.code, p.code, 'store_00001', 'S2-01', 100, 20, 'second-branch auto-stock'
FROM part_master p
WHERE NOT EXISTS (
  SELECT 1 FROM address_master a WHERE a.part_code=p.code AND a.store_id='store_00001'
);

COMMIT;
