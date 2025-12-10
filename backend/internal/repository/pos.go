package repository

import (
	"context"
)

type POS struct {
	POSID    string
	BranchID string
	POSName  string
}

type POSRepository interface {
	GetByID(ctx context.Context, id string) (*POS, error)
	List(ctx context.Context, limit, offset int) ([]POS, error)
	Create(ctx context.Context, pos *POS) error
	Update(ctx context.Context, pos *POS) error
	Delete(ctx context.Context, id string) error
}

