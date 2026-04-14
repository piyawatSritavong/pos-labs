package repository

import (
	"context"
	"database/sql"
)

type RBACRepository interface {
	UserHasPermission(ctx context.Context, userID, resource, action string) (bool, error)
}

type rbacRepositoryPG struct {
	db *sql.DB
}

func NewRBACRepository(db *sql.DB) RBACRepository {
	return &rbacRepositoryPG{db: db}
}

func (r *rbacRepositoryPG) UserHasPermission(ctx context.Context, userID, resource, action string) (bool, error) {
	// When custom_permissions is set, check only against those permissions.
	// When NULL, fall back to role-based permissions.
	row := r.db.QueryRowContext(ctx, `
		SELECT 1
		FROM "user" u
		WHERE u.id = $1 AND u.is_active = true
		AND (
		  (u.custom_permissions IS NOT NULL AND EXISTS (
		    SELECT 1 FROM "permission" p
		    WHERE p.id = ANY(u.custom_permissions)
		      AND p.resource = $2 AND p.action = $3
		  ))
		  OR
		  (u.custom_permissions IS NULL AND EXISTS (
		    SELECT 1
		    FROM "role" r2
		    JOIN "role_permission" rp ON rp.role_id = r2.id
		    JOIN "permission" p ON p.id = rp.permission_id
		    WHERE r2.id = u.role_id AND p.resource = $2 AND p.action = $3
		  ))
		)
		LIMIT 1
	`, userID, resource, action)

	var v int
	if err := row.Scan(&v); err != nil {
		if err == sql.ErrNoRows {
			return false, nil
		}
		return false, err
	}
	return true, nil
}
