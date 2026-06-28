package repository

import (
	"context"
	"database/sql"
	"strings"
)

// Role is a selectable user role with its display name.
type Role struct {
	ID     string
	Name   string
	Detail string
}

type RBACRepository interface {
	UserHasPermission(ctx context.Context, userID, resource, action string) (bool, error)
	ListRoles(ctx context.Context) ([]Role, error)
	RoleExists(ctx context.Context, id string) (bool, error)
	// CreateRole inserts a role and its permission grants in one transaction.
	CreateRole(ctx context.Context, id, name, detail string, permissionIDs []string) error
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

func (r *rbacRepositoryPG) ListRoles(ctx context.Context) ([]Role, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT "id", COALESCE("name", ''), COALESCE("detail", '')
		FROM "role"
		ORDER BY "id"
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Role
	for rows.Next() {
		var role Role
		if err := rows.Scan(&role.ID, &role.Name, &role.Detail); err != nil {
			return nil, err
		}
		out = append(out, role)
	}
	return out, rows.Err()
}

func (r *rbacRepositoryPG) RoleExists(ctx context.Context, id string) (bool, error) {
	var v int
	err := r.db.QueryRowContext(ctx, `SELECT 1 FROM "role" WHERE "id" = $1`, id).Scan(&v)
	if err == sql.ErrNoRows {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return true, nil
}

func (r *rbacRepositoryPG) CreateRole(ctx context.Context, id, name, detail string, permissionIDs []string) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()

	if _, err := tx.ExecContext(ctx,
		`INSERT INTO "role"("id", "name", "detail") VALUES ($1, $2, $3)`,
		id, name, detail,
	); err != nil {
		return err
	}
	for _, pid := range permissionIDs {
		pid = strings.TrimSpace(pid)
		if pid == "" {
			continue
		}
		if _, err := tx.ExecContext(ctx,
			`INSERT INTO "role_permission"("role_id", "permission_id")
			 VALUES ($1, $2) ON CONFLICT DO NOTHING`,
			id, pid,
		); err != nil {
			return err
		}
	}
	return tx.Commit()
}
