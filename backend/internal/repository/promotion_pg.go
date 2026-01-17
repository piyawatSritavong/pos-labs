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

func (r *promotionRepositoryPG) List(ctx context.Context, limit, offset int) ([]Promotion, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT "code", "details", "unit", "amount"
		FROM "promotion_master"
		ORDER BY "code"
		LIMIT $1 OFFSET $2
	`, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var promotions []Promotion
	for rows.Next() {
		var p Promotion
		if err := rows.Scan(&p.Code, &p.Details, &p.Unit, &p.Amount); err != nil {
			return nil, err
		}
		promotions = append(promotions, p)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	return promotions, nil
}

func (r *promotionRepositoryPG) Create(ctx context.Context, promotion *Promotion) error {
	_, err := r.db.ExecContext(ctx, `
		INSERT INTO "promotion_master"("code", "details", "unit", "amount")
		VALUES ($1, $2, $3, $4)
	`, promotion.Code, promotion.Details, promotion.Unit, promotion.Amount)
	return err
}

func (r *promotionRepositoryPG) Update(ctx context.Context, promotion *Promotion) error {
	result, err := r.db.ExecContext(ctx, `
		UPDATE "promotion_master"
		SET "details" = $1, "unit" = $2, "amount" = $3
		WHERE "code" = $4
	`, promotion.Details, promotion.Unit, promotion.Amount, promotion.Code)
	if err != nil {
		return err
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if rowsAffected == 0 {
		return ErrNotFound
	}

	return nil
}

func (r *promotionRepositoryPG) Delete(ctx context.Context, code string) error {
	result, err := r.db.ExecContext(ctx, `
		DELETE FROM "promotion_master"
		WHERE "code" = $1
	`, code)
	if err != nil {
		return err
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if rowsAffected == 0 {
		return ErrNotFound
	}

	return nil
}

