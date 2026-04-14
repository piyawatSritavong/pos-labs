package repository

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"time"
)

type cashReconciliationRepositoryPG struct {
	db *sql.DB
}

func NewCashReconciliationRepository(db *sql.DB) CashReconciliationRepository {
	return &cashReconciliationRepositoryPG{db: db}
}

func (r *cashReconciliationRepositoryPG) GenerateCashReconciliationID(ctx context.Context) (string, error) {
	utc7 := time.Now().UTC().Add(7 * time.Hour)
	dateKey := utc7.Format("20060102")
	counterKey := "cr_" + dateKey

	var counter int
	err := r.db.QueryRowContext(ctx, `
		INSERT INTO "counter"("key", "value")
		VALUES ($1, 1)
		ON CONFLICT ("key") DO UPDATE
		SET "value" = "counter"."value" + 1
		RETURNING "value"
	`, counterKey).Scan(&counter)
	if err != nil {
		return "", fmt.Errorf("failed to generate cash reconciliation counter: %w", err)
	}

	return fmt.Sprintf("CR%s%06d", dateKey, counter), nil
}

func (r *cashReconciliationRepositoryPG) Create(ctx context.Context, cr *CashReconciliation) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	_, err = tx.ExecContext(ctx, `
		INSERT INTO "cash_reconciliation"(
			"id", "daily_close_id", "confirmed_by",
			"expected_amount", "actual_amount", "difference",
			"notes", "created_at"
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
	`,
		cr.ID,
		cr.DailyCloseID,
		cr.ConfirmedBy,
		cr.ExpectedAmount,
		cr.ActualAmount,
		cr.Difference,
		cr.Notes,
		cr.CreatedAt,
	)
	if err != nil {
		return err
	}

	_, err = tx.ExecContext(ctx, `
		UPDATE "daily_close" SET "status" = 'reconciled' WHERE "id" = $1
	`, cr.DailyCloseID)
	if err != nil {
		return err
	}

	return tx.Commit()
}

func (r *cashReconciliationRepositoryPG) GetByID(ctx context.Context, id string) (*CashReconciliation, error) {
	row := r.db.QueryRowContext(ctx, `
		SELECT
			cr."id", cr."daily_close_id", cr."confirmed_by",
			cr."expected_amount", cr."actual_amount", cr."difference",
			cr."notes", cr."created_at",
			dc."branch_id", dc."pos_id", dc."close_date"
		FROM "cash_reconciliation" cr
		JOIN "daily_close" dc ON dc."id" = cr."daily_close_id"
		WHERE cr."id" = $1
	`, id)

	return scanCashReconciliation(row)
}

func (r *cashReconciliationRepositoryPG) List(ctx context.Context, limit, offset int, branchID *string) ([]CashReconciliation, error) {
	if limit <= 0 {
		limit = 50
	}
	if offset < 0 {
		offset = 0
	}

	query := `
		SELECT
			cr."id", cr."daily_close_id", cr."confirmed_by",
			cr."expected_amount", cr."actual_amount", cr."difference",
			cr."notes", cr."created_at",
			dc."branch_id", dc."pos_id", dc."close_date"
		FROM "cash_reconciliation" cr
		JOIN "daily_close" dc ON dc."id" = cr."daily_close_id"
	`
	args := make([]interface{}, 0)
	argIndex := 1
	conditions := make([]string, 0)

	if branchID != nil && strings.TrimSpace(*branchID) != "" {
		conditions = append(conditions, fmt.Sprintf(`dc."branch_id" = $%d`, argIndex))
		args = append(args, strings.TrimSpace(*branchID))
		argIndex++
	}

	if len(conditions) > 0 {
		query += " WHERE " + strings.Join(conditions, " AND ")
	}
	query += ` ORDER BY cr."created_at" DESC`
	query += fmt.Sprintf(" LIMIT $%d OFFSET $%d", argIndex, argIndex+1)
	args = append(args, limit, offset)

	rows, err := r.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	recons := make([]CashReconciliation, 0)
	for rows.Next() {
		cr, scanErr := scanCashReconciliation(rows)
		if scanErr != nil {
			return nil, scanErr
		}
		recons = append(recons, *cr)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	return recons, nil
}

type cashReconciliationScanner interface {
	Scan(dest ...interface{}) error
}

func scanCashReconciliation(scanner cashReconciliationScanner) (*CashReconciliation, error) {
	var cr CashReconciliation
	var closeDate time.Time

	err := scanner.Scan(
		&cr.ID,
		&cr.DailyCloseID,
		&cr.ConfirmedBy,
		&cr.ExpectedAmount,
		&cr.ActualAmount,
		&cr.Difference,
		&cr.Notes,
		&cr.CreatedAt,
		&cr.BranchID,
		&cr.PosID,
		&closeDate,
	)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, ErrNotFound
		}
		return nil, err
	}

	cr.CloseDate = closeDate
	return &cr, nil
}
