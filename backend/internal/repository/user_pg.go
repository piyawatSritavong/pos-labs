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
		SELECT "id", "username", "role_id", "name", "password", "is_active"
		FROM "user"
		WHERE "id" = $1
	`, id)

	var u User
	if err := row.Scan(&u.ID, &u.Username, &u.RoleID, &u.Name, &u.PasswordHash, &u.IsActive); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, err
		}
		return nil, err
	}
	return &u, nil
}

func (r *userRepositoryPG) GetByUsername(ctx context.Context, username string) (*User, error) {
	row := r.db.QueryRowContext(ctx, `
		SELECT "id", "username", "role_id", "name", "password", "is_active"
		FROM "user"
		WHERE "username" = $1
	`, username)

	var u User
	if err := row.Scan(&u.ID, &u.Username, &u.RoleID, &u.Name, &u.PasswordHash, &u.IsActive); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, err
		}
		return nil, err
	}
	return &u, nil
}



