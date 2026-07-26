DELETE FROM "role_permission"
WHERE "role_id" = 'role.cashier'
  AND "permission_id" IN ('perm.stock_count.read', 'perm.stock_count.write');
