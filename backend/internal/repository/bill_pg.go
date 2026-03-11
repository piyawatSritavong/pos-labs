package repository

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"time"

	"backend/internal/config"
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

func (r *billRepositoryPG) List(ctx context.Context, limit, offset int, dateFrom, dateTo *time.Time, memberID *string) ([]Bill, error) {
	if limit <= 0 {
		limit = config.DefaultLimit
	}
	if offset < 0 {
		offset = 0
	}

	// Build query with optional date filtering
	query := `
		SELECT
			"id", "branch_id", "pos_id", "status", "payment_method", "payment_ref",
			"member_id", "customer_name",
			"purchase_amount", "total_discount", "total_amount",
			"vat_amount", "xvat_amount",
			"created_at", "updated_at", "created_by", "updated_by"
		FROM "bill_master"
	`
	args := []interface{}{}
	argIndex := 1

	// Add date filtering if provided
	// Note: dates are already normalized by the handler (start of day for dateFrom, end of day for dateTo)
	if dateFrom != nil || dateTo != nil || memberID != nil {
		conditions := []string{}
		if dateFrom != nil {
			conditions = append(conditions, fmt.Sprintf(`"created_at" >= $%d`, argIndex))
			args = append(args, *dateFrom)
			argIndex++
		}
		if dateTo != nil {
			conditions = append(conditions, fmt.Sprintf(`"created_at" < $%d`, argIndex))
			args = append(args, *dateTo)
			argIndex++
		}
		if memberID != nil && strings.TrimSpace(*memberID) != "" {
			conditions = append(conditions, fmt.Sprintf(`"member_id" = $%d`, argIndex))
			args = append(args, strings.TrimSpace(*memberID))
			argIndex++
		}
		if len(conditions) > 0 {
			query += " WHERE " + strings.Join(conditions, " AND ")
		}
	}

	query += " ORDER BY \"created_at\" DESC"
	query += fmt.Sprintf(" LIMIT $%d OFFSET $%d", argIndex, argIndex+1)
	args = append(args, limit, offset)

	rows, err := r.db.QueryContext(ctx, query, args...)
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

func (r *billRepositoryPG) UpdateMember(ctx context.Context, billID, memberID, updatedBy string) error {
	result, err := r.db.ExecContext(ctx, `
		UPDATE "bill_master"
		SET "member_id" = $1, "updated_at" = now(), "updated_by" = $2
		WHERE "id" = $3
	`, memberID, updatedBy, billID)
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

func (r *billRepositoryPG) RemoveMember(ctx context.Context, billID, updatedBy string) error {
	result, err := r.db.ExecContext(ctx, `
		UPDATE "bill_master"
		SET "member_id" = NULL, "updated_at" = now(), "updated_by" = $1
		WHERE "id" = $2
	`, updatedBy, billID)
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

func (r *billRepositoryPG) UpdateTimestamp(ctx context.Context, billID, updatedBy string) error {
	_, err := r.db.ExecContext(ctx, `
		UPDATE "bill_master"
		SET "updated_at" = now(), "updated_by" = $1
		WHERE "id" = $2
	`, updatedBy, billID)
	return err
}

func (r *billRepositoryPG) GetItemByPartCode(ctx context.Context, billID, partCode, addressCode string) (*BillDetail, error) {
	row := r.db.QueryRowContext(ctx, `
		SELECT
			"bill_id", "part_code", "address_code",
			"unit_id", "uni_label", "unit_label_th",
			"name", "cost", "price", "qty"
		FROM "bill_item_detail"
		WHERE "bill_id" = $1 AND "part_code" = $2 AND "address_code" = $3
	`, billID, partCode, addressCode)

	var d BillDetail
	err := row.Scan(
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
	)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, ErrNotFound
		}
		return nil, err
	}
	return &d, nil
}

func (r *billRepositoryPG) AddItem(ctx context.Context, detail *BillDetail) error {
	_, err := r.db.ExecContext(ctx, `
		INSERT INTO "bill_item_detail"(
			"bill_id", "part_code", "address_code",
			"unit_id", "uni_label", "unit_label_th",
			"name", "cost", "price", "qty"
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
		ON CONFLICT ("bill_id", "part_code", "address_code")
		DO UPDATE SET "qty" = "bill_item_detail"."qty" + EXCLUDED."qty"
	`, detail.BillID, detail.PartCode, detail.AddressCode,
		detail.UnitID, detail.UnitLabel, detail.UnitLabelTH,
		detail.Name, detail.Cost, detail.Price, detail.Qty)
	return err
}

func (r *billRepositoryPG) UpdateItemQty(ctx context.Context, billID, partCode, addressCode string, qty int) error {
	_, err := r.db.ExecContext(ctx, `
		UPDATE "bill_item_detail"
		SET "qty" = $1
		WHERE "bill_id" = $2 AND "part_code" = $3 AND "address_code" = $4
	`, qty, billID, partCode, addressCode)
	return err
}

func (r *billRepositoryPG) RemoveItem(ctx context.Context, billID, partCode, addressCode string) error {
	_, err := r.db.ExecContext(ctx, `
		DELETE FROM "bill_item_detail"
		WHERE "bill_id" = $1 AND "part_code" = $2 AND "address_code" = $3
	`, billID, partCode, addressCode)
	return err
}

func (r *billRepositoryPG) AddDiscount(ctx context.Context, discount *BillDiscountDetail) error {
	_, err := r.db.ExecContext(ctx, `
		INSERT INTO "bill_discount_detail"("bill_id", "promotion_code", "unit", "amount")
		VALUES ($1, $2, $3, $4)
		ON CONFLICT ("bill_id", "promotion_code")
		DO UPDATE SET "unit" = EXCLUDED."unit", "amount" = EXCLUDED."amount"
	`, discount.BillID, discount.PromotionCode, discount.Unit, discount.Amount)
	return err
}

func (r *billRepositoryPG) RemoveDiscount(ctx context.Context, billID, promotionCode string) error {
	_, err := r.db.ExecContext(ctx, `
		DELETE FROM "bill_discount_detail"
		WHERE "bill_id" = $1 AND "promotion_code" = $2
	`, billID, promotionCode)
	return err
}

func (r *billRepositoryPG) GetDiscountByCode(ctx context.Context, billID, promotionCode string) (*BillDiscountDetail, error) {
	row := r.db.QueryRowContext(ctx, `
		SELECT "bill_id", "promotion_code", "unit", "amount"
		FROM "bill_discount_detail"
		WHERE "bill_id" = $1 AND "promotion_code" = $2
	`, billID, promotionCode)

	var d BillDiscountDetail
	err := row.Scan(&d.BillID, &d.PromotionCode, &d.Unit, &d.Amount)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, ErrNotFound
		}
		return nil, err
	}
	return &d, nil
}

func (r *billRepositoryPG) GetAllItems(ctx context.Context, billID string) ([]BillDetail, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT "bill_id", "part_code", "address_code",
		       "unit_id", "uni_label", "unit_label_th",
		       "name", "cost", "price", "qty"
		FROM "bill_item_detail"
		WHERE "bill_id" = $1
		ORDER BY "part_code", "address_code"
	`, billID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var items []BillDetail
	for rows.Next() {
		var d BillDetail
		if err := rows.Scan(
			&d.BillID, &d.PartCode, &d.AddressCode,
			&d.UnitID, &d.UnitLabel, &d.UnitLabelTH,
			&d.Name, &d.Cost, &d.Price, &d.Qty,
		); err != nil {
			return nil, err
		}
		items = append(items, d)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	return items, nil
}

func (r *billRepositoryPG) GetAllDiscounts(ctx context.Context, billID string) ([]BillDiscountDetail, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT "bill_id", "promotion_code", "unit", "amount"
		FROM "bill_discount_detail"
		WHERE "bill_id" = $1
		ORDER BY "promotion_code"
	`, billID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var discounts []BillDiscountDetail
	for rows.Next() {
		var d BillDiscountDetail
		if err := rows.Scan(&d.BillID, &d.PromotionCode, &d.Unit, &d.Amount); err != nil {
			return nil, err
		}
		discounts = append(discounts, d)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	return discounts, nil
}

func (r *billRepositoryPG) UpdateAmounts(ctx context.Context, billID string, purchaseAmount, totalDiscount, totalAmount, vatAmount, xvatAmount float64) error {
	_, err := r.db.ExecContext(ctx, `
		UPDATE "bill_master"
		SET "purchase_amount" = $1,
		    "total_discount" = $2,
		    "total_amount" = $3,
		    "vat_amount" = $4,
		    "xvat_amount" = $5
		WHERE "id" = $6
	`, purchaseAmount, totalDiscount, totalAmount, vatAmount, xvatAmount, billID)
	return err
}

func (r *billRepositoryPG) UpdatePayment(ctx context.Context, billID, paymentMethod, paymentRef, updatedBy string) error {
	// Convert empty strings to NULL for nullable fields
	var pm, pr sql.NullString
	if paymentMethod != "" {
		pm = sql.NullString{String: paymentMethod, Valid: true}
	}
	if paymentRef != "" {
		pr = sql.NullString{String: paymentRef, Valid: true}
	}

	_, err := r.db.ExecContext(ctx, `
		UPDATE "bill_master"
		SET "payment_method" = $1, "payment_ref" = $2, "status" = 'completed', "updated_at" = now(), "updated_by" = $3
		WHERE "id" = $4
	`, pm, pr, updatedBy, billID)
	return err
}

func (r *billRepositoryPG) Delete(ctx context.Context, billID string) error {
	result, err := r.db.ExecContext(ctx, `
		DELETE FROM "bill_master"
		WHERE "id" = $1
	`, billID)
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
