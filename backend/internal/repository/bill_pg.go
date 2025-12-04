package repository

import (
	"context"
	"database/sql"
	"fmt"
	"time"
)

type billRepositoryPG struct {
	db *sql.DB
}

func NewBillRepository(db *sql.DB) BillRepository {
	return &billRepositoryPG{db: db}
}

// GenerateBillID generates a new bill ID using bill_counter table.
// Format: YYYYMMDD + 6-digit counter (e.g., "20251204000001")
// Date is in UTC+7 timezone.
func (r *billRepositoryPG) GenerateBillID(ctx context.Context) (string, error) {
	// Get current time in UTC+7 (Thailand timezone)
	utc := time.Now().UTC()
	utc7 := utc.Add(7 * time.Hour)
	dateKey := utc7.Format("20060102") // YYYYMMDD

	// Atomic increment: insert with value 1 if key doesn't exist, otherwise increment
	var counter int
	err := r.db.QueryRowContext(ctx, `
		INSERT INTO "counter"("key", "value")
		VALUES ($1, 1)
		ON CONFLICT ("key") DO UPDATE
		SET "value" = "counter"."value" + 1
		RETURNING "value"
	`, dateKey).Scan(&counter)
	if err != nil {
		return "", fmt.Errorf("failed to generate bill counter: %w", err)
	}

	// Format: YYYYMMDD + 6-digit zero-padded counter
	billID := fmt.Sprintf("%s%06d", dateKey, counter)
	return billID, nil
}

func (r *billRepositoryPG) Create(ctx context.Context, bill *Bill) error {
	_, err := r.db.ExecContext(ctx, `
		INSERT INTO "bill_master"(
			"id", "status", "payment_method",
			"purchase_amount", "total_discount", "total_amount",
			"vat_amount", "xvat_amount",
			"created_at", "updated_at", "created_by", "updated_by"
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
	`,
		bill.ID,
		bill.Status,
		bill.PaymentMethod,
		bill.PurchaseAmount,
		bill.TotalDiscount,
		bill.TotalAmount,
		bill.VATAmount,
		bill.XVATAmount,
		bill.CreatedAt,
		bill.UpdatedAt,
		bill.CreatedBy,
		bill.UpdatedBy,
	)
	return err
}

func (r *billRepositoryPG) GetByID(ctx context.Context, id string) (*Bill, error) {
	row := r.db.QueryRowContext(ctx, `
		SELECT
			"id", "status", "payment_method",
			"purchase_amount", "total_discount", "total_amount",
			"vat_amount", "xvat_amount",
			"created_at", "updated_at", "created_by", "updated_by"
		FROM "bill_master"
		WHERE "id" = $1
	`, id)

	var b Bill
	var createdAt, updatedAt time.Time
	var createdBy, updatedBy sql.NullString

	err := row.Scan(
		&b.ID,
		&b.Status,
		&b.PaymentMethod,
		&b.PurchaseAmount,
		&b.TotalDiscount,
		&b.TotalAmount,
		&b.VATAmount,
		&b.XVATAmount,
		&createdAt,
		&updatedAt,
		&createdBy,
		&updatedBy,
	)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, ErrNotFound
		}
		return nil, err
	}

	b.CreatedAt = createdAt
	b.UpdatedAt = updatedAt
	if createdBy.Valid {
		b.CreatedBy = createdBy.String
	}
	if updatedBy.Valid {
		b.UpdatedBy = updatedBy.String
	}

	return &b, nil
}

func (r *billRepositoryPG) List(ctx context.Context, limit, offset int) ([]Bill, error) {
	if limit <= 0 {
		limit = 50
	}
	if offset < 0 {
		offset = 0
	}

	rows, err := r.db.QueryContext(ctx, `
		SELECT
			"id", "status", "payment_method",
			"purchase_amount", "total_discount", "total_amount",
			"vat_amount", "xvat_amount",
			"created_at", "updated_at", "created_by", "updated_by"
		FROM "bill_master"
		ORDER BY "created_at" DESC
		LIMIT $1 OFFSET $2
	`, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var bills []Bill
	for rows.Next() {
		var b Bill
		var createdAt, updatedAt time.Time
		var createdBy, updatedBy sql.NullString

		if err := rows.Scan(
			&b.ID,
			&b.Status,
			&b.PaymentMethod,
			&b.PurchaseAmount,
			&b.TotalDiscount,
			&b.TotalAmount,
			&b.VATAmount,
			&b.XVATAmount,
			&createdAt,
			&updatedAt,
			&createdBy,
			&updatedBy,
		); err != nil {
			return nil, err
		}

		b.CreatedAt = createdAt
		b.UpdatedAt = updatedAt
		if createdBy.Valid {
			b.CreatedBy = createdBy.String
		}
		if updatedBy.Valid {
			b.UpdatedBy = updatedBy.String
		}

		bills = append(bills, b)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	return bills, nil
}

