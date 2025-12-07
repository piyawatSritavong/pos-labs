package repository

import (
	"context"
	"database/sql"
	"errors"
)

type userRepositoryPG struct {
	db *sql.DB
}

func NewUserRepository(db *sql.DB) UserRepository {
	return &userRepositoryPG{db: db}
}

func (r *userRepositoryPG) GetByID(ctx context.Context, id string) (*User, error) {
	row := r.db.QueryRowContext(ctx, `
		SELECT "id", "username", "role_id", "name", "password", "is_active", "is_superuser"
		FROM "user"
		WHERE "id" = $1
	`, id)

	var u User
	if err := row.Scan(&u.ID, &u.Username, &u.RoleID, &u.Name, &u.PasswordHash, &u.IsActive, &u.IsSuperuser); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	return &u, nil
}

func (r *userRepositoryPG) GetByUsername(ctx context.Context, username string) (*User, error) {
	row := r.db.QueryRowContext(ctx, `
		SELECT "id", "username", "role_id", "name", "password", "is_active", "is_superuser"
		FROM "user"
		WHERE "username" = $1
	`, username)

	var u User
	if err := row.Scan(&u.ID, &u.Username, &u.RoleID, &u.Name, &u.PasswordHash, &u.IsActive, &u.IsSuperuser); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	return &u, nil
}

func (r *userRepositoryPG) List(ctx context.Context, limit, offset int) ([]User, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT "id", "username", "role_id", "name", "password", "is_active", "is_superuser"
		FROM "user"
		ORDER BY "username"
		LIMIT $1 OFFSET $2
	`, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var users []User
	for rows.Next() {
		var u User
		if err := rows.Scan(&u.ID, &u.Username, &u.RoleID, &u.Name, &u.PasswordHash, &u.IsActive, &u.IsSuperuser); err != nil {
			return nil, err
		}
		users = append(users, u)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	return users, nil
}

func (r *userRepositoryPG) Create(ctx context.Context, user *User) error {
	_, err := r.db.ExecContext(ctx, `
		INSERT INTO "user"("id", "username", "role_id", "name", "password", "is_active", "is_superuser")
		VALUES ($1, $2, $3, $4, $5, $6, $7)
	`, user.ID, user.Username, user.RoleID, user.Name, user.PasswordHash, user.IsActive, user.IsSuperuser)
	return err
}

func (r *userRepositoryPG) Update(ctx context.Context, user *User) error {
	_, err := r.db.ExecContext(ctx, `
		UPDATE "user"
		SET "username" = $1, "role_id" = $2, "name" = $3, "password" = $4, "is_active" = $5, "is_superuser" = $6
		WHERE "id" = $7
	`, user.Username, user.RoleID, user.Name, user.PasswordHash, user.IsActive, user.IsSuperuser, user.ID)
	return err
}

func (r *userRepositoryPG) Delete(ctx context.Context, id string) error {
	_, err := r.db.ExecContext(ctx, `DELETE FROM "user" WHERE "id" = $1`, id)
	return err
}



