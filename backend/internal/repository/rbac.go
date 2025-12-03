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
	row := r.db.QueryRowContext(ctx, `
		SELECT 1
		FROM "user" u
		JOIN "role" r2 ON r2.id = u.role_id
		JOIN "role_permission" rp ON rp.role_id = r2.id
		JOIN "permission" p ON p.id = rp.permission_id
		WHERE u.id = $1
		  AND u.is_active = true
		  AND p.resource = $2
		  AND p.action = $3
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


