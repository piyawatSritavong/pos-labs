-- Re-establish one-session-per-user: keep only each user's newest session,
-- then restore the unique constraint.
DELETE FROM "session" older
USING "session" newer
WHERE older."user_id" = newer."user_id"
  AND (older."created_at", older."id") < (newer."created_at", newer."id");

DROP INDEX IF EXISTS "idx_session_user_id";

ALTER TABLE "session" ADD CONSTRAINT "session_user_id_key" UNIQUE ("user_id");
