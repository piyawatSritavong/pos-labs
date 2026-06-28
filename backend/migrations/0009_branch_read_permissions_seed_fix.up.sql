INSERT INTO role_permission (role_id, permission_id)
SELECT r.role_id, p.id
FROM (VALUES ('role.van_staff'), ('role.hq_manager')) AS r(role_id)
CROSS JOIN permission p
WHERE p.resource = 'branch' AND p.action = 'read'
ON CONFLICT DO NOTHING;
