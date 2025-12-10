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
}

