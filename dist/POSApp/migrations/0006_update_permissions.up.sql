-- Add users and user_branch permissions to HQ Manager
INSERT INTO role_permission (role_id, permission_id)
SELECT 'role.hq_manager', p.id
FROM permission p
WHERE p.resource IN ('users', 'user_branch')
  AND p.action IN ('read', 'write', 'delete')
ON CONFLICT DO NOTHING;

-- Ensure Van Staff has transfers.write (required for stock requisition create)
INSERT INTO role_permission (role_id, permission_id)
SELECT 'role.van_staff', p.id
FROM permission p
WHERE p.resource = 'transfers' AND p.action = 'write'
ON CONFLICT DO NOTHING;
