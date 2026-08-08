-- =============================================================================
-- deploy/supabase-add-admin1-account.sql
--
-- Adds a second administrator account: admin1 / admin123.
--
-- WHY THIS EXISTS
--   SeedCoreData (backend/internal/db/seed.go) only runs on an empty database
--   and the production service runs with AUTO_SEED_CORE=false, so a new account
--   has to be inserted directly — the same reason
--   deploy/supabase-sync-accounts.sql exists.
--
--   admin1 mirrors the existing admin: role.admin, superuser, the main branch
--   (00000) and the office terminal POS003, which sells from the warehouse.
--
-- The password hash is bcrypt cost 10 of "admin123", generated with the same
-- library the backend verifies against (golang.org/x/crypto/bcrypt). This is a
-- demo credential and is deliberately in the repo, like the pos1 hash in
-- scripts/generate-real-seed-sql.py — do not reuse this pattern for a real one.
--
-- SAFE TO RE-RUN: guarded by ON CONFLICT / WHERE NOT EXISTS. Re-running does
-- not reset the password if someone has since changed it.
--
-- HOW TO RUN
--   psql "$DATABASE_URL" -f deploy/supabase-add-admin1-account.sql
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

-- Guard: the role, branch and terminal admin1 is attached to must exist.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "role" WHERE "id" = 'role.admin') THEN
    RAISE EXCEPTION 'role.admin is missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM "branch_setting" WHERE "branch_id" = '00000') THEN
    RAISE EXCEPTION 'branch 00000 is missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM "pos_setting" WHERE "pos_id" = 'POS003') THEN
    RAISE EXCEPTION 'POS003 is missing';
  END IF;
END $$;

INSERT INTO "user" (
  "id", "username", "role_id", "name", "password",
  "is_active", "is_superuser", "default_pos_id"
)
VALUES (
  'cfe7cdd423cd435fad7cdd12987d9467',
  'admin1',
  'role.admin',
  'Administrator 1',
  '$2a$10$auOqEUdrr3UA5BHfq.zQLOX7d3vsVRcIso3oBJtH0B9FuxAaBvSL6',
  true,
  true,
  'POS003'
)
ON CONFLICT ("id") DO NOTHING;

INSERT INTO "user_branch" ("user_id", "branch_id")
SELECT u."id", '00000'
  FROM "user" u
 WHERE u."username" = 'admin1'
   AND NOT EXISTS (
         SELECT 1 FROM "user_branch" b
          WHERE b."user_id" = u."id" AND b."branch_id" = '00000'
       );

DO $$
DECLARE
  branches integer;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM "user"
     WHERE "username" = 'admin1' AND "role_id" = 'role.admin' AND "is_active"
  ) THEN
    RAISE EXCEPTION 'admin1 was not created';
  END IF;
  SELECT count(*) INTO branches
    FROM "user_branch" b JOIN "user" u ON u."id" = b."user_id"
   WHERE u."username" = 'admin1';
  IF branches <> 1 THEN
    RAISE EXCEPTION 'admin1 should belong to exactly one branch, has %', branches;
  END IF;
END $$;

COMMIT;
