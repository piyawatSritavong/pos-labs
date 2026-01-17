package repository

import (
	"context"
)

type Promotion struct {
	Code    string
	Details string
	Unit    string // THB or percentage
	Amount  float64
}

type PromotionRepository interface {
	GetByCode(ctx context.Context, code string) (*Promotion, error)
	List(ctx context.Context, limit, offset int) ([]Promotion, error)
	Create(ctx context.Context, promotion *Promotion) error
	Update(ctx context.Context, promotion *Promotion) error
	Delete(ctx context.Context, code string) error
}

