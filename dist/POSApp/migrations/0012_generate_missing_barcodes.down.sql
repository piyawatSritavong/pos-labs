-- Best-effort rollback: only revert rows where bar_code still equals code
-- (i.e. they were set by the up migration and have not been edited since).
UPDATE "part_master"
   SET "bar_code" = ''
 WHERE "bar_code" = "code"
   AND "code" ~ '^P[0-9]+$';
