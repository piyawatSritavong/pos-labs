-- Allow multiple concurrent sessions per user. A duplicate login no longer
-- fails at the DB level; the clients detect the overlap via GET /auth/sessions
-- and resolve it interactively ("stay" revokes the other sessions, "leave"
-- logs the current one out).
ALTER TABLE "session" DROP CONSTRAINT IF EXISTS "session_user_id_key";

-- The unique constraint's index also served user_id lookups (GetByUserID);
-- keep an ordinary index for that.
CREATE INDEX IF NOT EXISTS "idx_session_user_id" ON "session" ("user_id");
