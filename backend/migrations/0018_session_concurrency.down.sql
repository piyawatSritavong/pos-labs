-- Pending/terminal requests cannot exist in the legacy schema. Remove those
-- first so a newer pending request never causes its incumbent active session
-- to be discarded by the de-duplication below.
DELETE FROM "session"
WHERE "status" <> 'active';

-- Keep the newest active session for each user before restoring the original
-- one-session-per-user schema.
DELETE FROM "session" s
USING "session" newer
WHERE s."user_id" = newer."user_id"
  AND (s."created_at", s."id") < (newer."created_at", newer."id");

DROP INDEX IF EXISTS "idx_session_terminal_last_seen_at";
DROP INDEX IF EXISTS "uq_session_user_pending";
DROP INDEX IF EXISTS "uq_session_user_active";
DROP INDEX IF EXISTS "idx_session_user_status";

ALTER TABLE "session"
  DROP CONSTRAINT IF EXISTS "CHK_session_status";

UPDATE "session"
SET "expires_at" = now() + interval '4 hours'
WHERE "expires_at" IS NULL;

ALTER TABLE "session"
  ALTER COLUMN "expires_at" SET NOT NULL,
  DROP COLUMN "status_reason",
  DROP COLUMN "status";

ALTER TABLE "session"
  ADD CONSTRAINT "session_user_id_key" UNIQUE ("user_id");

CREATE INDEX "idx_session_expires_at" ON "session" ("expires_at");
