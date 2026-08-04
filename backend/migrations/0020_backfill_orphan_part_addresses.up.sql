-- A part without an address is invisible to the inventory page and to
-- branch-scoped POS searches. Backfill only truly orphaned parts so existing
-- branch-specific product assignments remain unchanged.
WITH preferred_stores AS (
  SELECT DISTINCT ON (bs."branch_id")
    bs."branch_id",
    bs."store_id"
  FROM "branch_store" bs
  JOIN "store_master" s ON s."id" = bs."store_id"
  ORDER BY
    bs."branch_id",
    COALESCE(bs."is_default", false) DESC,
    COALESCE(s."is_default", false) DESC,
    bs."store_id"
),
orphan_parts AS (
  SELECT p."code"
  FROM "part_master" p
  WHERE NOT EXISTS (
    SELECT 1
    FROM "address_master" a
    WHERE a."part_code" = p."code"
  )
)
INSERT INTO "address_master"(
  "code", "part_code", "store_id", "shelf", "qty", "rop", "remarks"
)
SELECT
  'AUTO-' || md5(op."code" || ':' || ps."store_id"),
  op."code",
  ps."store_id",
  '',
  0,
  0,
  'Automatically assigned by migration 0020'
FROM orphan_parts op
CROSS JOIN preferred_stores ps;
