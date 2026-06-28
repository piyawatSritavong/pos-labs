package repository

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"time"
)

type stockCountRepositoryPG struct {
	db *sql.DB
}

func NewStockCountRepository(db *sql.DB) StockCountRepository {
	return &stockCountRepositoryPG{db: db}
}

func (r *stockCountRepositoryPG) GenerateStockCountID(ctx context.Context) (string, error) {
	utc7 := time.Now().UTC().Add(7 * time.Hour)
	dateKey := utc7.Format("20060102")
	counterKey := "sc_" + dateKey

	var counter int
	err := r.db.QueryRowContext(ctx, `
		INSERT INTO "counter"("key", "value")
		VALUES ($1, 1)
		ON CONFLICT ("key") DO UPDATE
		SET "value" = "counter"."value" + 1
		RETURNING "value"
	`, counterKey).Scan(&counter)
	if err != nil {
		return "", fmt.Errorf("failed to generate stock count counter: %w", err)
	}

	return fmt.Sprintf("SC%s%06d", dateKey, counter), nil
}

func (r *stockCountRepositoryPG) Create(ctx context.Context, count *StockCount) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	_, err = tx.ExecContext(ctx, `
		INSERT INTO "stock_count"(
			"id", "branch_id", "store_id", "counted_by",
			"status", "notes", "created_at"
		) VALUES ($1, $2, $3, $4, $5, $6, $7)
	`,
		count.ID,
		count.BranchID,
		count.StoreID,
		count.CountedBy,
		count.Status,
		count.Notes,
		count.CreatedAt,
	)
	if err != nil {
		return err
	}

	// Snapshot current address_master quantities for this store
	_, err = tx.ExecContext(ctx, `
		INSERT INTO "stock_count_item" ("count_id", "part_code", "system_qty", "counted_qty")
		SELECT $1, am."part_code", am."qty", am."qty"
		FROM "address_master" am
		WHERE am."store_id" = $2
	`, count.ID, count.StoreID)
	if err != nil {
		return err
	}

	return tx.Commit()
}

func (r *stockCountRepositoryPG) GetByID(ctx context.Context, id string) (*StockCount, []StockCountItem, error) {
	row := r.db.QueryRowContext(ctx, `
		SELECT
			"id", "branch_id", "store_id", "counted_by",
			"status", "notes", "created_at", "submitted_at"
		FROM "stock_count"
		WHERE "id" = $1
	`, id)

	count, err := scanStockCount(row)
	if err != nil {
		return nil, nil, err
	}

	rows, err := r.db.QueryContext(ctx, `
		SELECT
			sci."count_id", sci."part_code",
			sci."system_qty", sci."counted_qty",
			COALESCE(pm."name", '') AS part_name,
			COALESCE(pm."name_th", '') AS part_name_th
		FROM "stock_count_item" sci
		LEFT JOIN "part_master" pm ON pm."code" = sci."part_code"
		WHERE sci."count_id" = $1
		ORDER BY sci."part_code"
	`, id)
	if err != nil {
		return nil, nil, err
	}
	defer rows.Close()

	items := make([]StockCountItem, 0)
	for rows.Next() {
		var item StockCountItem
		if err := rows.Scan(
			&item.CountID,
			&item.PartCode,
			&item.SystemQty,
			&item.CountedQty,
			&item.PartName,
			&item.PartNameTH,
		); err != nil {
			return nil, nil, err
		}
		item.Variance = item.CountedQty - item.SystemQty
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, nil, err
	}

	return count, items, nil
}

func (r *stockCountRepositoryPG) List(ctx context.Context, limit, offset int, branchID, status *string) ([]StockCount, error) {
	if limit <= 0 {
		limit = 50
	}
	if offset < 0 {
		offset = 0
	}

	query := `
		SELECT
			"id", "branch_id", "store_id", "counted_by",
			"status", "notes", "created_at", "submitted_at"
		FROM "stock_count"
	`
	args := make([]interface{}, 0)
	argIndex := 1
	conditions := make([]string, 0)

	if branchID != nil && strings.TrimSpace(*branchID) != "" {
		conditions = append(conditions, fmt.Sprintf(`"branch_id" = $%d`, argIndex))
		args = append(args, strings.TrimSpace(*branchID))
		argIndex++
	}
	if status != nil && strings.TrimSpace(*status) != "" {
		conditions = append(conditions, fmt.Sprintf(`"status" = $%d`, argIndex))
		args = append(args, strings.TrimSpace(*status))
		argIndex++
	}

	if len(conditions) > 0 {
		query += " WHERE " + strings.Join(conditions, " AND ")
	}
	query += ` ORDER BY "created_at" DESC`
	query += fmt.Sprintf(" LIMIT $%d OFFSET $%d", argIndex, argIndex+1)
	args = append(args, limit, offset)

	rows, err := r.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	counts := make([]StockCount, 0)
	for rows.Next() {
		c, scanErr := scanStockCount(rows)
		if scanErr != nil {
			return nil, scanErr
		}
		counts = append(counts, *c)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	return counts, nil
}

func (r *stockCountRepositoryPG) UpdateItemCounts(ctx context.Context, countID string, items []StockCountItem) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	for _, item := range items {
		_, err = tx.ExecContext(ctx, `
			UPDATE "stock_count_item"
			SET "counted_qty" = $1
			WHERE "count_id" = $2 AND "part_code" = $3
		`, item.CountedQty, countID, item.PartCode)
		if err != nil {
			return err
		}
	}

	return tx.Commit()
}

func (r *stockCountRepositoryPG) Submit(ctx context.Context, countID string) error {
	_, err := r.db.ExecContext(ctx, `
		UPDATE "stock_count"
		SET "status" = 'submitted', "submitted_at" = now()
		WHERE "id" = $1
	`, countID)
	return err
}

type stockCountScanner interface {
	Scan(dest ...interface{}) error
}

func scanStockCount(scanner stockCountScanner) (*StockCount, error) {
	var c StockCount
	var submittedAt sql.NullTime

	err := scanner.Scan(
		&c.ID,
		&c.BranchID,
		&c.StoreID,
		&c.CountedBy,
		&c.Status,
		&c.Notes,
		&c.CreatedAt,
		&submittedAt,
	)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, ErrNotFound
		}
		return nil, err
	}

	if submittedAt.Valid {
		c.SubmittedAt = &submittedAt.Time
	}

	return &c, nil
}
