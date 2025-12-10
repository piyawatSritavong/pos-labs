package repository

import (
	"context"
	"database/sql"
	"errors"
)

type promotionRepositoryPG struct {
	db *sql.DB
}

func NewPromotionRepository(db *sql.DB) PromotionRepository {
	return &promotionRepositoryPG{db: db}
}

func (r *promotionRepositoryPG) GetByCode(ctx context.Context, code string) (*Promotion, error) {
	row := r.db.QueryRowContext(ctx, `
		SELECT "code", "details", "unit", "amount"
		FROM "promotion_master"
		WHERE "code" = $1
	`, code)

	var p Promotion
	err := row.Scan(&p.Code, &p.Details, &p.Unit, &p.Amount)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}

	return &p, nil
}

