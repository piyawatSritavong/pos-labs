package repository

import (
	"context"
)

type User struct {
	ID                string
	Username          string
	RoleID            string
	Name              string
	PasswordHash      string
	IsActive          bool
	IsSuperuser       bool
	CustomPermissions []string // nil = use role defaults; non-nil = per-user override
	BranchID          string   // default branch from user_branch join (read-only, not persisted here)
	DefaultPOSID      string   // POS terminal this account is pinned to (empty = resolve by branch)
}

type UserRepository interface {
	GetByID(ctx context.Context, id string) (*User, error)
	// GetByIDs loads many users in one query, keyed by user ID — used to resolve
	// created_by/updated_by ids to display names without N+1.
	GetByIDs(ctx context.Context, ids []string) (map[string]*User, error)
	GetByUsername(ctx context.Context, username string) (*User, error)
	List(ctx context.Context, limit, offset int) ([]User, error)
	Create(ctx context.Context, user *User) error
	Update(ctx context.Context, user *User) error
	Delete(ctx context.Context, id string) error
}


