-- Allow one active session and one login request per user. Sessions no longer
-- expire by wall clock; last_seen_at is used only to decide whether an
-- incumbent session is still present during a concurrent-login request.

DELETE FROM "session"
WHERE "expires_at" <= now();

ALTER TABLE "session"
  DROP CONSTRAINT IF EXISTS "session_user_id_key";

ALTER TABLE "session"
  ALTER COLUMN "expires_at" DROP NOT NULL,
  ADD COLUMN "status" text NOT NULL DEFAULT 'active',
  ADD COLUMN "status_reason" text;

UPDATE "session"
SET "expires_at" = NULL,
    "status" = 'active',
    "status_reason" = NULL;

ALTER TABLE "session"
  ADD CONSTRAINT "CHK_session_status"
  CHECK ("status" IN ('active', 'pending', 'rejected', 'replaced'));

DROP INDEX IF EXISTS "idx_session_expires_at";

CREATE INDEX "idx_session_user_status"
  ON "session" ("user_id", "status");

CREATE UNIQUE INDEX "uq_session_user_active"
  ON "session" ("user_id")
  WHERE "status" = 'active';

CREATE UNIQUE INDEX "uq_session_user_pending"
  ON "session" ("user_id")
  WHERE "status" = 'pending';

CREATE INDEX "idx_session_terminal_last_seen_at"
  ON "session" ("last_seen_at")
  WHERE "status" IN ('rejected', 'replaced');
