-- Remove only the production role-smoke fixtures created by
-- scripts/smoke_production_roles.py. Both the strict code shape and a
-- SMOKE-20... marker are required so real catalog rows are never selected.
CREATE TEMP TABLE "_cleanup_smoke_parts" ON COMMIT DROP AS
SELECT p."code"
FROM "part_master" p
WHERE p."code" ~ '^SMK[0-9]{9}(A|P1|P2)$'
  AND (
    COALESCE(p."name", '') LIKE 'SMOKE-20%'
    OR COALESCE(p."name_th", '') LIKE 'SMOKE-20%'
    OR COALESCE(p."details", '') LIKE '%SMOKE-20%'
  );

CREATE TEMP TABLE "_cleanup_smoke_bills" ON COMMIT DROP AS
SELECT DISTINCT b."id"
FROM "bill_master" b
JOIN "bill_item_detail" i ON i."bill_id" = b."id"
JOIN "_cleanup_smoke_parts" p ON p."code" = i."part_code";

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM "bill_item_detail" i
    JOIN "_cleanup_smoke_bills" b ON b."id" = i."bill_id"
    LEFT JOIN "_cleanup_smoke_parts" p ON p."code" = i."part_code"
    WHERE p."code" IS NULL
  ) THEN
    RAISE EXCEPTION 'role-smoke cleanup aborted: a selected bill contains a non-smoke product';
  END IF;
END $$;

CREATE TEMP TABLE "_cleanup_smoke_returns" ON COMMIT DROP AS
SELECT r."id"
FROM "return_note_master" r
JOIN "_cleanup_smoke_bills" b ON b."id" = r."reference_bill_id";

CREATE TEMP TABLE "_cleanup_smoke_counts" ON COMMIT DROP AS
SELECT s."id"
FROM "stock_count" s
WHERE s."notes" ~ '^SMOKE-20[0-9]{12}-(admin|pos1|pos2)$';

DELETE FROM "return_note_item_detail"
WHERE "return_note_id" IN (SELECT "id" FROM "_cleanup_smoke_returns");

DELETE FROM "return_note_master"
WHERE "id" IN (SELECT "id" FROM "_cleanup_smoke_returns");

DELETE FROM "bill_discount_detail"
WHERE "bill_id" IN (SELECT "id" FROM "_cleanup_smoke_bills");

DELETE FROM "bill_item_detail"
WHERE "bill_id" IN (SELECT "id" FROM "_cleanup_smoke_bills");

DELETE FROM "bill_master"
WHERE "id" IN (SELECT "id" FROM "_cleanup_smoke_bills");

-- stock_count_item cascades from stock_count.
DELETE FROM "stock_count"
WHERE "id" IN (SELECT "id" FROM "_cleanup_smoke_counts");

DELETE FROM "address_master"
WHERE "part_code" IN (SELECT "code" FROM "_cleanup_smoke_parts");

DELETE FROM "part_master"
WHERE "code" IN (SELECT "code" FROM "_cleanup_smoke_parts");
