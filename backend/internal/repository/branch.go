package repository

import (
	"context"
)

type Branch struct {
	BranchID        string
	CompanyID       string
	BranchName      string
	BranchNameTH    string
	BranchAddress   string
	BranchAddressTH string
	Phone           string
	Email           *string
}

type Store struct {
	ID        string
	BranchID  string
	Label     string
	LabelTH   string
	IsDefault bool
}

type BranchRepository interface {
	GetByID(ctx context.Context, id string) (*Branch, error)
	List(ctx context.Context, limit, offset int) ([]Branch, error)
	NextID(ctx context.Context) (string, error)
	Create(ctx context.Context, branch *Branch) error
	Update(ctx context.Context, branch *Branch) error
	Delete(ctx context.Context, id string) error
	Count(ctx context.Context) (int, error)
	GetStoresByBranchID(ctx context.Context, branchID string) ([]Store, error)
}
