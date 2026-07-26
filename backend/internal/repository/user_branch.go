package repository

import (
	"context"
)

type UserBranch struct {
	UserID   string
	BranchID string
}

type UserBranchRepository interface {
	GetByUserID(ctx context.Context, userID string) ([]UserBranch, error)
	GetByBranchID(ctx context.Context, branchID string) ([]UserBranch, error)
	GetByUserAndBranch(ctx context.Context, userID, branchID string) (*UserBranch, error)
	Create(ctx context.Context, userBranch *UserBranch) error
	Delete(ctx context.Context, userID, branchID string) error
}
