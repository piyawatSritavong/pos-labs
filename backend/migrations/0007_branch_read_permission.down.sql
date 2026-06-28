DELETE FROM role_permission rp
USING permission p
WHERE rp.permission_id = p.id
  AND rp.role_id IN ('role.van_staff', 'role.hq_manager')
  AND p.resource = 'branch' AND p.action = 'read';
