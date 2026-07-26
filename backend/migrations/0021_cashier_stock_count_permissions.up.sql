INSERT INTO "permission" ("id", "name", "action", "resource", "detail")
VALUES
  ('perm.stock_count.read', 'Read stock counts', 'read', 'stock_count', 'Read stock count records'),
  ('perm.stock_count.write', 'Write stock counts', 'write', 'stock_count', 'Create/submit stock count records')
ON CONFLICT ("id") DO UPDATE SET
  "name" = EXCLUDED."name",
  "action" = EXCLUDED."action",
  "resource" = EXCLUDED."resource",
  "detail" = EXCLUDED."detail";

INSERT INTO "role_permission" ("role_id", "permission_id")
SELECT 'role.cashier', permission_id
FROM (
  VALUES
    ('perm.stock_count.read'),
    ('perm.stock_count.write')
) AS permissions(permission_id)
WHERE EXISTS (
  SELECT 1
  FROM "role"
  WHERE "id" = 'role.cashier'
)
ON CONFLICT ("role_id", "permission_id") DO NOTHING;

-- A non-NULL custom_permissions array intentionally overrides role permissions.
-- Preserve that behaviour while ensuring existing cashier overrides receive the
-- stock-count permissions exposed by the cashier UI.
UPDATE "user"
SET "custom_permissions" = ARRAY(
  SELECT DISTINCT permission_id
  FROM unnest(
    "custom_permissions" || ARRAY[
      'perm.stock_count.read',
      'perm.stock_count.write'
    ]::text[]
  ) AS permission_id
  ORDER BY permission_id
)
WHERE "role_id" = 'role.cashier'
  AND "custom_permissions" IS NOT NULL;
