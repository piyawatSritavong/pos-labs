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
}

type UserRepository interface {
	GetByID(ctx context.Context, id string) (*User, error)
	GetByUsername(ctx context.Context, username string) (*User, error)
}


