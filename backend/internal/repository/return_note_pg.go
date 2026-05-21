package repository

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"time"

	"backend/internal/config"
)

type returnNoteRepositoryPG struct {
	db *sql.DB
}

func NewReturnNoteRepository(db *sql.DB) ReturnNoteRepository {
	return &returnNoteRepositoryPG{db: db}
}

func (r *returnNoteRepositoryPG) GenerateReturnNoteID(ctx context.Context) (string, error) {
	utc := time.Now().UTC()
	utc7 := utc.Add(7 * time.Hour)
	dateKey := utc7.Format("20060102")
	counterKey := "cn_" + dateKey

	var counter int
	err := r.db.QueryRowContext(ctx, `
		INSERT INTO "counter"("key", "value")
		VALUES ($1, 1)
		ON CONFLICT ("key") DO UPDATE
		SET "value" = "counter"."value" + 1
		RETURNING "value"
	`, counterKey).Scan(&counter)
	if err != nil {
		return "", fmt.Errorf("failed to generate return note counter: %w", err)
	}

	return fmt.Sprintf("CN%s%06d", dateKey, counter), nil
}

func (r *returnNoteRepositoryPG) Create(ctx context.Context, note *ReturnNote, items []ReturnNoteItem) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() {
		_ = tx.Rollback()
	}()

	var purchaseBillID, paymentMethod, paymentRef, memberID sql.NullString
	if strings.TrimSpace(note.PurchaseBillID) != "" {
		purchaseBillID = sql.NullString{String: strings.TrimSpace(note.PurchaseBillID), Valid: true}
	}
	if strings.TrimSpace(note.PaymentMethod) != "" {
		paymentMethod = sql.NullString{String: strings.TrimSpace(note.PaymentMethod), Valid: true}
	}
	if strings.TrimSpace(note.PaymentRef) != "" {
		paymentRef = sql.NullString{String: strings.TrimSpace(note.PaymentRef), Valid: true}
	}
	if strings.TrimSpace(note.MemberID) != "" {
		memberID = sql.NullString{String: strings.TrimSpace(note.MemberID), Valid: true}
	}

	_, err = tx.ExecContext(ctx, `
		INSERT INTO "return_note_master"(
			"id", "reference_bill_id", "purchase_bill_id",
			"branch_id", "pos_id", "status", "settlement_mode",
			"payment_method", "payment_ref",
			"member_id", "customer_name",
			"purchase_amount", "refund_amount", "net_amount",
			"created_at", "updated_at", "created_by", "updated_by"
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18)
	`,
		note.ID,
		note.ReferenceBillID,
		purchaseBillID,
		note.BranchID,
		note.POSID,
		note.Status,
		note.SettlementMode,
		paymentMethod,
		paymentRef,
		memberID,
		note.CustomerName,
		note.PurchaseAmount,
		note.RefundAmount,
		note.NetAmount,
		note.CreatedAt,
		note.UpdatedAt,
		note.CreatedBy,
		note.UpdatedBy,
	)
	if err != nil {
		return err
	}

	for _, item := range items {
		_, err = tx.ExecContext(ctx, `
			INSERT INTO "return_note_item_detail"(
				"return_note_id", "reference_bill_id",
				"part_code", "address_code",
				"unit_id", "unit_label", "unit_label_th",
				"name", "receipt_name", "price", "qty", "line_total"
			)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
		`,
			item.ReturnNoteID,
			item.ReferenceBillID,
			item.PartCode,
			item.AddressCode,
			item.UnitID,
			item.UnitLabel,
			item.UnitLabelTH,
			item.Name,
			item.ReceiptName,
			item.Price,
			item.Qty,
			item.LineTotal,
		)
		if err != nil {
			return err
		}

		result, updateErr := tx.ExecContext(ctx, `
			UPDATE "address_master"
			SET "qty" = COALESCE("qty", 0) + $1
			WHERE "code" = $2
		`, item.Qty, item.AddressCode)
		if updateErr != nil {
			return updateErr
		}

		rowsAffected, rowsErr := result.RowsAffected()
		if rowsErr != nil {
			return rowsErr
		}
		if rowsAffected == 0 {
			return ErrNotFound
		}
	}

	if err := tx.Commit(); err != nil {
		return err
	}
	return nil
}

func (r *returnNoteRepositoryPG) GetByID(ctx context.Context, id string) (*ReturnNote, []ReturnNoteItem, error) {
	row := r.db.QueryRowContext(ctx, `
		SELECT
			"id", "reference_bill_id", "purchase_bill_id",
			"branch_id", "pos_id", "status", "settlement_mode",
			"payment_method", "payment_ref",
			"member_id", "customer_name",
			"purchase_amount", "refund_amount", "net_amount",
			"created_at", "updated_at", "created_by", "updated_by"
		FROM "return_note_master"
		WHERE "id" = $1
	`, id)

	note, err := scanReturnNote(row)
	if err != nil {
		return nil, nil, err
	}

	items, err := r.GetItems(ctx, id)
	if err != nil {
		return nil, nil, err
	}

	return note, items, nil
}

func (r *returnNoteRepositoryPG) List(
	ctx context.Context,
	limit,
	offset int,
	dateFrom,
	dateTo *time.Time,
	branchID,
	posID,
	referenceBillID *string,
) ([]ReturnNote, error) {
	if limit <= 0 {
		limit = config.DefaultLimit
	}
	if offset < 0 {
		offset = 0
	}

	query := `
		SELECT
			"id", "reference_bill_id", "purchase_bill_id",
			"branch_id", "pos_id", "status", "settlement_mode",
			"payment_method", "payment_ref",
			"member_id", "customer_name",
			"purchase_amount", "refund_amount", "net_amount",
			"created_at", "updated_at", "created_by", "updated_by"
		FROM "return_note_master"
	`
	args := make([]interface{}, 0)
	argIndex := 1
	conditions := make([]string, 0)

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
	if branchID != nil && strings.TrimSpace(*branchID) != "" {
		conditions = append(conditions, fmt.Sprintf(`"branch_id" = $%d`, argIndex))
		args = append(args, strings.TrimSpace(*branchID))
		argIndex++
	}
	if posID != nil && strings.TrimSpace(*posID) != "" {
		conditions = append(conditions, fmt.Sprintf(`"pos_id" = $%d`, argIndex))
		args = append(args, strings.TrimSpace(*posID))
		argIndex++
	}
	if referenceBillID != nil && strings.TrimSpace(*referenceBillID) != "" {
		conditions = append(conditions, fmt.Sprintf(`"reference_bill_id" = $%d`, argIndex))
		args = append(args, strings.TrimSpace(*referenceBillID))
		argIndex++
	}

	if len(conditions) > 0 {
		query += " WHERE " + strings.Join(conditions, " AND ")
	}

	query += " ORDER BY \"created_at\" DESC"
	query += fmt.Sprintf(" LIMIT $%d OFFSET $%d", argIndex, argIndex+1)
	args = append(args, limit, offset)

	rows, err := r.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	notes := make([]ReturnNote, 0)
	for rows.Next() {
		note, scanErr := scanReturnNote(rows)
		if scanErr != nil {
			return nil, scanErr
		}
		notes = append(notes, *note)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	return notes, nil
}

func (r *returnNoteRepositoryPG) GetItems(ctx context.Context, returnNoteID string) ([]ReturnNoteItem, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT
			"return_note_id", "reference_bill_id",
			"part_code", "address_code",
			"unit_id", "unit_label", "unit_label_th",
			"name", COALESCE(NULLIF("receipt_name", ''), 'ITEM ' || "part_code"), "price", "qty", "line_total"
		FROM "return_note_item_detail"
		WHERE "return_note_id" = $1
		ORDER BY "part_code", "address_code"
	`, returnNoteID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	items := make([]ReturnNoteItem, 0)
	for rows.Next() {
		var item ReturnNoteItem
		if err := rows.Scan(
			&item.ReturnNoteID,
			&item.ReferenceBillID,
			&item.PartCode,
			&item.AddressCode,
			&item.UnitID,
			&item.UnitLabel,
			&item.UnitLabelTH,
			&item.Name,
			&item.ReceiptName,
			&item.Price,
			&item.Qty,
			&item.LineTotal,
		); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	return items, nil
}

func (r *returnNoteRepositoryPG) GetReturnedQtyByReferenceBill(ctx context.Context, referenceBillID string) (map[string]int, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT
			ri."part_code",
			ri."address_code",
			COALESCE(SUM(ri."qty"), 0) AS returned_qty
		FROM "return_note_item_detail" ri
		INNER JOIN "return_note_master" rm
			ON rm."id" = ri."return_note_id"
		WHERE ri."reference_bill_id" = $1
		  AND rm."status" <> 'cancelled'
		GROUP BY ri."part_code", ri."address_code"
	`, referenceBillID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make(map[string]int)
	for rows.Next() {
		var partCode, addressCode string
		var returnedQty int
		if err := rows.Scan(&partCode, &addressCode, &returnedQty); err != nil {
			return nil, err
		}
		out[partCode+"|"+addressCode] = returnedQty
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	return out, nil
}

type returnNoteScanner interface {
	Scan(dest ...interface{}) error
}

func scanReturnNote(scanner returnNoteScanner) (*ReturnNote, error) {
	var note ReturnNote
	var createdAt, updatedAt time.Time
	var purchaseBillID, paymentMethod, paymentRef, memberID sql.NullString
	var createdBy, updatedBy sql.NullString

	err := scanner.Scan(
		&note.ID,
		&note.ReferenceBillID,
		&purchaseBillID,
		&note.BranchID,
		&note.POSID,
		&note.Status,
		&note.SettlementMode,
		&paymentMethod,
		&paymentRef,
		&memberID,
		&note.CustomerName,
		&note.PurchaseAmount,
		&note.RefundAmount,
		&note.NetAmount,
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

	note.CreatedAt = createdAt
	note.UpdatedAt = updatedAt
	if purchaseBillID.Valid {
		note.PurchaseBillID = purchaseBillID.String
	}
	if paymentMethod.Valid {
		note.PaymentMethod = paymentMethod.String
	}
	if paymentRef.Valid {
		note.PaymentRef = paymentRef.String
	}
	if memberID.Valid {
		note.MemberID = memberID.String
	}
	if createdBy.Valid {
		note.CreatedBy = createdBy.String
	}
	if updatedBy.Valid {
		note.UpdatedBy = updatedBy.String
	}

	return &note, nil
}
