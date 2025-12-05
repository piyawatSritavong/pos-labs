package repository

import (
	"context"
)

type User struct {
	ID           string
	Username     string
	RoleID       string
	Name         string
	PasswordHash string
	IsActive     bool
	IsSuperuser  bool
}

type UserRepository interface {
	GetByID(ctx context.Context, id string) (*User, error)
	GetByUsername(ctx context.Context, username string) (*User, error)
	List(ctx context.Context, limit, offset int) ([]User, error)
	Create(ctx context.Context, user *User) error
	Update(ctx context.Context, user *User) error
	Delete(ctx context.Context, id string) error
}


