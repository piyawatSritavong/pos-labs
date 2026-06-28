package repository

import (
	"context"
	"database/sql"
	"errors"

	"github.com/lib/pq"
)

type userRepositoryPG struct {
	db *sql.DB
}

func NewUserRepository(db *sql.DB) UserRepository {
	return &userRepositoryPG{db: db}
}

func (r *userRepositoryPG) GetByID(ctx context.Context, id string) (*User, error) {
	row := r.db.QueryRowContext(ctx, `
		SELECT u."id", u."username", u."role_id", u."name", u."password", u."is_active", u."is_superuser", u."custom_permissions",
		       COALESCE(ub."branch_id", '') AS branch_id
		FROM "user" u
		LEFT JOIN (SELECT "user_id", MIN("branch_id") AS "branch_id" FROM "user_branch" GROUP BY "user_id") ub ON ub."user_id" = u."id"
		WHERE u."id" = $1
	`, id)

	var u User
	var perms pq.StringArray
	if err := row.Scan(&u.ID, &u.Username, &u.RoleID, &u.Name, &u.PasswordHash, &u.IsActive, &u.IsSuperuser, &perms, &u.BranchID); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	if perms != nil {
		u.CustomPermissions = []string(perms)
	}
	return &u, nil
}

func (r *userRepositoryPG) GetByIDs(ctx context.Context, ids []string) (map[string]*User, error) {
	result := make(map[string]*User, len(ids))
	if len(ids) == 0 {
		return result, nil
	}
	rows, err := r.db.QueryContext(ctx, `
		SELECT "id", "username", "role_id", "name", "is_active", "is_superuser"
		FROM "user"
		WHERE "id" = ANY($1)
	`, pq.Array(ids))
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var u User
		if err := rows.Scan(&u.ID, &u.Username, &u.RoleID, &u.Name, &u.IsActive, &u.IsSuperuser); err != nil {
			return nil, err
		}
		result[u.ID] = &u
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return result, nil
}

func (r *userRepositoryPG) GetByUsername(ctx context.Context, username string) (*User, error) {
	row := r.db.QueryRowContext(ctx, `
		SELECT "id", "username", "role_id", "name", "password", "is_active", "is_superuser", "custom_permissions"
		FROM "user"
		WHERE "username" = $1
	`, username)

	var u User
	var perms pq.StringArray
	if err := row.Scan(&u.ID, &u.Username, &u.RoleID, &u.Name, &u.PasswordHash, &u.IsActive, &u.IsSuperuser, &perms); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	if perms != nil {
		u.CustomPermissions = []string(perms)
	}
	return &u, nil
}

func (r *userRepositoryPG) List(ctx context.Context, limit, offset int) ([]User, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT u."id", u."username", u."role_id", u."name", u."password", u."is_active", u."is_superuser", u."custom_permissions",
		       COALESCE(ub."branch_id", '') AS branch_id
		FROM "user" u
		LEFT JOIN (SELECT "user_id", MIN("branch_id") AS "branch_id" FROM "user_branch" GROUP BY "user_id") ub ON ub."user_id" = u."id"
		ORDER BY u."username"
		LIMIT $1 OFFSET $2
	`, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var users []User
	for rows.Next() {
		var u User
		var perms pq.StringArray
		if err := rows.Scan(&u.ID, &u.Username, &u.RoleID, &u.Name, &u.PasswordHash, &u.IsActive, &u.IsSuperuser, &perms, &u.BranchID); err != nil {
			return nil, err
		}
		if perms != nil {
			u.CustomPermissions = []string(perms)
		}
		users = append(users, u)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	return users, nil
}

func (r *userRepositoryPG) Create(ctx context.Context, user *User) error {
	var perms pq.StringArray
	if user.CustomPermissions != nil {
		perms = pq.StringArray(user.CustomPermissions)
	}
	_, err := r.db.ExecContext(ctx, `
		INSERT INTO "user"("id", "username", "role_id", "name", "password", "is_active", "is_superuser", "custom_permissions")
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
	`, user.ID, user.Username, user.RoleID, user.Name, user.PasswordHash, user.IsActive, user.IsSuperuser, perms)
	return err
}

func (r *userRepositoryPG) Update(ctx context.Context, user *User) error {
	var perms pq.StringArray
	if user.CustomPermissions != nil {
		perms = pq.StringArray(user.CustomPermissions)
	}
	_, err := r.db.ExecContext(ctx, `
		UPDATE "user"
		SET "username" = $1, "role_id" = $2, "name" = $3, "password" = $4,
		    "is_active" = $5, "is_superuser" = $6, "custom_permissions" = $7
		WHERE "id" = $8
	`, user.Username, user.RoleID, user.Name, user.PasswordHash, user.IsActive, user.IsSuperuser, perms, user.ID)
	return err
}

func (r *userRepositoryPG) Delete(ctx context.Context, id string) error {
	_, err := r.db.ExecContext(ctx, `DELETE FROM "user" WHERE "id" = $1`, id)
	return err
}
