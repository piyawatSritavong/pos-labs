package repository

import (
	"context"
)

type POS struct {
	POSID          string
	BranchID       string
	POSName        string
	POSSecret      string
	IsActive       bool
	VehicleStoreID string
}

type POSRepository interface {
	GetByID(ctx context.Context, id string) (*POS, error)
	List(ctx context.Context, limit, offset int) ([]POS, error)
	Create(ctx context.Context, pos *POS) error
	Delete(ctx context.Context, id string) error
	GetSecret(ctx context.Context, id string) (string, error)
	RefreshSecret(ctx context.Context, id string) (string, error)
	ToggleActive(ctx context.Context, id string) error
}
