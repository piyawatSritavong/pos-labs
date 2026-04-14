package repository

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"time"
)

type dailyCloseRepositoryPG struct {
	db *sql.DB
}

func NewDailyCloseRepository(db *sql.DB) DailyCloseRepository {
	return &dailyCloseRepositoryPG{db: db}
}

func (r *dailyCloseRepositoryPG) GenerateDailyCloseID(ctx context.Context) (string, error) {
	utc7 := time.Now().UTC().Add(7 * time.Hour)
	dateKey := utc7.Format("20060102")
	counterKey := "dc_" + dateKey

	var counter int
	err := r.db.QueryRowContext(ctx, `
		INSERT INTO "counter"("key", "value")
		VALUES ($1, 1)
		ON CONFLICT ("key") DO UPDATE
		SET "value" = "counter"."value" + 1
		RETURNING "value"
	`, counterKey).Scan(&counter)
	if err != nil {
		return "", fmt.Errorf("failed to generate daily close counter: %w", err)
	}

	return fmt.Sprintf("DC%s%06d", dateKey, counter), nil
}

func (r *dailyCloseRepositoryPG) GetSummary(ctx context.Context, branchID, posID string, closeDate time.Time) (*DailySummary, error) {
	var summary DailySummary

	err := r.db.QueryRowContext(ctx, `
		SELECT
			COALESCE(COUNT(*), 0),
			COALESCE(SUM("total_amount"), 0),
			COALESCE(SUM(CASE WHEN "payment_method" = 'cash' THEN "total_amount" ELSE 0 END), 0),
			COALESCE(SUM(CASE WHEN "payment_method" != 'cash' THEN "total_amount" ELSE 0 END), 0)
		FROM "bill_master"
		WHERE "branch_id" = $1
		  AND "pos_id" = $2
		  AND "status" = 'completed'
		  AND DATE("created_at" AT TIME ZONE 'Asia/Bangkok') = $3
	`, branchID, posID, closeDate.Format("2006-01-02")).Scan(
		&summary.TotalBills,
		&summary.TotalSales,
		&summary.TotalCash,
		&summary.TotalTransfer,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to get bill summary: %w", err)
	}

	var totalReturns float64
	err = r.db.QueryRowContext(ctx, `
		SELECT COALESCE(SUM("refund_amount"), 0)
		FROM "return_note_master"
		WHERE "branch_id" = $1
		  AND "pos_id" = $2
		  AND "status" != 'cancelled'
		  AND DATE("created_at" AT TIME ZONE 'Asia/Bangkok') = $3
	`, branchID, posID, closeDate.Format("2006-01-02")).Scan(&totalReturns)
	if err != nil {
		return nil, fmt.Errorf("failed to get return summary: %w", err)
	}

	summary.TotalReturns = totalReturns
	summary.NetAmount = summary.TotalSales - summary.TotalReturns

	return &summary, nil
}

func (r *dailyCloseRepositoryPG) Create(ctx context.Context, dc *DailyClose) error {
	_, err := r.db.ExecContext(ctx, `
		INSERT INTO "daily_close"(
			"id", "branch_id", "pos_id", "closed_by",
			"close_date", "total_sales", "total_cash", "total_transfer",
			"total_bills", "total_returns", "net_amount",
			"status", "notes", "created_at"
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
	`,
		dc.ID,
		dc.BranchID,
		dc.PosID,
		dc.ClosedBy,
		dc.CloseDate.Format("2006-01-02"),
		dc.TotalSales,
		dc.TotalCash,
		dc.TotalTransfer,
		dc.TotalBills,
		dc.TotalReturns,
		dc.NetAmount,
		dc.Status,
		dc.Notes,
		dc.CreatedAt,
	)
	return err
}

func (r *dailyCloseRepositoryPG) GetByID(ctx context.Context, id string) (*DailyClose, error) {
	row := r.db.QueryRowContext(ctx, `
		SELECT
			"id", "branch_id", "pos_id", "closed_by",
			"close_date", "total_sales", "total_cash", "total_transfer",
			"total_bills", "total_returns", "net_amount",
			"status", "notes", "created_at"
		FROM "daily_close"
		WHERE "id" = $1
	`, id)

	return scanDailyClose(row)
}

func (r *dailyCloseRepositoryPG) List(ctx context.Context, limit, offset int, branchID *string, dateFrom, dateTo *time.Time) ([]DailyClose, error) {
	if limit <= 0 {
		limit = 50
	}
	if offset < 0 {
		offset = 0
	}

	query := `
		SELECT
			"id", "branch_id", "pos_id", "closed_by",
			"close_date", "total_sales", "total_cash", "total_transfer",
			"total_bills", "total_returns", "net_amount",
			"status", "notes", "created_at"
		FROM "daily_close"
	`
	args := make([]interface{}, 0)
	argIndex := 1
	conditions := make([]string, 0)

	if branchID != nil && strings.TrimSpace(*branchID) != "" {
		conditions = append(conditions, fmt.Sprintf(`"branch_id" = $%d`, argIndex))
		args = append(args, strings.TrimSpace(*branchID))
		argIndex++
	}
	if dateFrom != nil {
		conditions = append(conditions, fmt.Sprintf(`"close_date" >= $%d`, argIndex))
		args = append(args, dateFrom.Format("2006-01-02"))
		argIndex++
	}
	if dateTo != nil {
		conditions = append(conditions, fmt.Sprintf(`"close_date" <= $%d`, argIndex))
		args = append(args, dateTo.Format("2006-01-02"))
		argIndex++
	}

	if len(conditions) > 0 {
		query += " WHERE " + strings.Join(conditions, " AND ")
	}
	query += ` ORDER BY "close_date" DESC`
	query += fmt.Sprintf(" LIMIT $%d OFFSET $%d", argIndex, argIndex+1)
	args = append(args, limit, offset)

	rows, err := r.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	closes := make([]DailyClose, 0)
	for rows.Next() {
		dc, scanErr := scanDailyClose(rows)
		if scanErr != nil {
			return nil, scanErr
		}
		closes = append(closes, *dc)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	return closes, nil
}

func (r *dailyCloseRepositoryPG) UpdateStatus(ctx context.Context, id, status string) error {
	_, err := r.db.ExecContext(ctx, `
		UPDATE "daily_close" SET "status" = $1 WHERE "id" = $2
	`, status, id)
	return err
}

func (r *dailyCloseRepositoryPG) ExistsByBranchPosDate(ctx context.Context, branchID, posID string, closeDate time.Time) (bool, error) {
	var exists bool
	err := r.db.QueryRowContext(ctx, `
		SELECT EXISTS(
			SELECT 1 FROM "daily_close"
			WHERE "branch_id" = $1 AND "pos_id" = $2 AND "close_date" = $3
		)
	`, branchID, posID, closeDate.Format("2006-01-02")).Scan(&exists)
	return exists, err
}

type dailyCloseScanner interface {
	Scan(dest ...interface{}) error
}

func scanDailyClose(scanner dailyCloseScanner) (*DailyClose, error) {
	var dc DailyClose
	var closeDate time.Time

	err := scanner.Scan(
		&dc.ID,
		&dc.BranchID,
		&dc.PosID,
		&dc.ClosedBy,
		&closeDate,
		&dc.TotalSales,
		&dc.TotalCash,
		&dc.TotalTransfer,
		&dc.TotalBills,
		&dc.TotalReturns,
		&dc.NetAmount,
		&dc.Status,
		&dc.Notes,
		&dc.CreatedAt,
	)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, ErrNotFound
		}
		return nil, err
	}

	dc.CloseDate = closeDate
	return &dc, nil
}
