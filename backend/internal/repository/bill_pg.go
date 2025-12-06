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
	// Convert empty strings to NULL for nullable fields
	var paymentMethod, paymentRef, memberID sql.NullString
	if bill.PaymentMethod != "" {
		paymentMethod = sql.NullString{String: bill.PaymentMethod, Valid: true}
	}
	if bill.PaymentRef != "" {
		paymentRef = sql.NullString{String: bill.PaymentRef, Valid: true}
	}
	if bill.MemberID != "" {
		memberID = sql.NullString{String: bill.MemberID, Valid: true}
	}

	_, err := r.db.ExecContext(ctx, `
		INSERT INTO "bill_master"(
			"id", "branch_id", "pos_id", "status", "payment_method", "payment_ref",
			"member_id", "customer_name",
			"purchase_amount", "total_discount", "total_amount",
			"vat_amount", "xvat_amount",
			"created_at", "updated_at", "created_by", "updated_by"
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17)
	`,
		bill.ID,
		bill.BranchID,
		bill.POSID,
		bill.Status,
		paymentMethod,
		paymentRef,
		memberID,
		bill.CustomerName,
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
			"id", "branch_id", "pos_id", "status", "payment_method", "payment_ref",
			"member_id", "customer_name",
			"purchase_amount", "total_discount", "total_amount",
			"vat_amount", "xvat_amount",
			"created_at", "updated_at", "created_by", "updated_by"
		FROM "bill_master"
		WHERE "id" = $1
	`, id)

	var b Bill
	var createdAt, updatedAt time.Time
	var createdBy, updatedBy sql.NullString
	var paymentMethod, paymentRef, memberID sql.NullString

	err := row.Scan(
		&b.ID,
		&b.BranchID,
		&b.POSID,
		&b.Status,
		&paymentMethod,
		&paymentRef,
		&memberID,
		&b.CustomerName,
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
	if paymentMethod.Valid {
		b.PaymentMethod = paymentMethod.String
	}
	if paymentRef.Valid {
		b.PaymentRef = paymentRef.String
	}
	if memberID.Valid {
		b.MemberID = memberID.String
	}

	return &b, nil
}

func (r *billRepositoryPG) GetFullByID(ctx context.Context, id string) (*Bill, []BillDetail, []BillDiscountDetail, error) {
	// Get master record first
	bill, err := r.GetByID(ctx, id)
	if err != nil {
		return nil, nil, nil, err
	}

	// Load bill details
	detailRows, err := r.db.QueryContext(ctx, `
		SELECT
			"bill_id", "part_code", "address_code",
			"unit_id", "uni_label", "unit_label_th",
			"name", "cost", "price", "qty"
		FROM "bill_item_detail"
		WHERE "bill_id" = $1
		ORDER BY "part_code", "address_code"
	`, id)
	if err != nil {
		return nil, nil, nil, err
	}
	defer detailRows.Close()

	var details []BillDetail
	for detailRows.Next() {
		var d BillDetail
		if err := detailRows.Scan(
			&d.BillID,
			&d.PartCode,
			&d.AddressCode,
			&d.UnitID,
			&d.UnitLabel,
			&d.UnitLabelTH,
			&d.Name,
			&d.Cost,
			&d.Price,
			&d.Qty,
		); err != nil {
			return nil, nil, nil, err
		}
		details = append(details, d)
	}
	if err := detailRows.Err(); err != nil {
		return nil, nil, nil, err
	}

	// Load bill discount details
	discountRows, err := r.db.QueryContext(ctx, `
		SELECT
			"bill_id", "promotion_code", "unit", "amount"
		FROM "bill_discount_detail"
		WHERE "bill_id" = $1
		ORDER BY "promotion_code"
	`, id)
	if err != nil {
		return nil, nil, nil, err
	}
	defer discountRows.Close()

	var discounts []BillDiscountDetail
	for discountRows.Next() {
		var d BillDiscountDetail
		if err := discountRows.Scan(
			&d.BillID,
			&d.PromotionCode,
			&d.Unit,
			&d.Amount,
		); err != nil {
			return nil, nil, nil, err
		}
		discounts = append(discounts, d)
	}
	if err := discountRows.Err(); err != nil {
		return nil, nil, nil, err
	}

	return bill, details, discounts, nil
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
			"id", "branch_id", "pos_id", "status", "payment_method", "payment_ref",
			"member_id", "customer_name",
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
		var paymentMethod, paymentRef, memberID sql.NullString

		if err := rows.Scan(
			&b.ID,
			&b.BranchID,
			&b.POSID,
			&b.Status,
			&paymentMethod,
			&paymentRef,
			&memberID,
			&b.CustomerName,
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
		if paymentMethod.Valid {
			b.PaymentMethod = paymentMethod.String
		}
		if paymentRef.Valid {
			b.PaymentRef = paymentRef.String
		}
		if memberID.Valid {
			b.MemberID = memberID.String
		}

		bills = append(bills, b)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	return bills, nil
}

func (r *billRepositoryPG) GetNewBillByPOS(ctx context.Context, posID string) (*Bill, error) {
	row := r.db.QueryRowContext(ctx, `
		SELECT
			"id", "branch_id", "pos_id", "status", "payment_method", "payment_ref",
			"member_id", "customer_name",
			"purchase_amount", "total_discount", "total_amount",
			"vat_amount", "xvat_amount",
			"created_at", "updated_at", "created_by", "updated_by"
		FROM "bill_master"
		WHERE "pos_id" = $1 AND "status" = 'new'
		ORDER BY "created_at" DESC
		LIMIT 1
	`, posID)

	var b Bill
	var createdAt, updatedAt time.Time
	var createdBy, updatedBy sql.NullString
	var paymentMethod, paymentRef, memberID sql.NullString

	err := row.Scan(
		&b.ID,
		&b.BranchID,
		&b.POSID,
		&b.Status,
		&paymentMethod,
		&paymentRef,
		&memberID,
		&b.CustomerName,
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
	if paymentMethod.Valid {
		b.PaymentMethod = paymentMethod.String
	}
	if paymentRef.Valid {
		b.PaymentRef = paymentRef.String
	}
	if memberID.Valid {
		b.MemberID = memberID.String
	}

	return &b, nil
}

func (r *billRepositoryPG) UpdateStatus(ctx context.Context, billID, status, updatedBy string) error {
	_, err := r.db.ExecContext(ctx, `
		UPDATE "bill_master"
		SET "status" = $1, "updated_at" = now(), "updated_by" = $2
		WHERE "id" = $3
	`, status, updatedBy, billID)
	return err
}

