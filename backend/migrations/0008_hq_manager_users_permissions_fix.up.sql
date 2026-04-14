INSERT INTO role_permission (role_id, permission_id)
SELECT 'role.hq_manager', p.id
FROM permission p
WHERE p.resource IN ('users', 'user_branch')
  AND p.action IN ('read', 'write', 'delete')
ON CONFLICT DO NOTHING;
