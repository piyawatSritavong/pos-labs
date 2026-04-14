DELETE FROM role_permission rp
USING permission p
WHERE rp.permission_id = p.id
  AND rp.role_id = 'role.hq_manager'
  AND p.resource IN ('users', 'user_branch');
