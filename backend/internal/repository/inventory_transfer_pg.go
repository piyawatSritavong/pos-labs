package repository

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"time"
)

type inventoryTransferRepositoryPG struct {
	db *sql.DB
}

func NewInventoryTransferRepository(db *sql.DB) InventoryTransferRepository {
	return &inventoryTransferRepositoryPG{db: db}
}

func (r *inventoryTransferRepositoryPG) GenerateTransferID(ctx context.Context) (string, error) {
	utc7 := time.Now().UTC().Add(7 * time.Hour)
	dateKey := utc7.Format("20060102")
	counterKey := "tr_" + dateKey

	var counter int
	err := r.db.QueryRowContext(ctx, `
		INSERT INTO "counter"("key", "value")
		VALUES ($1, 1)
		ON CONFLICT ("key") DO UPDATE
		SET "value" = "counter"."value" + 1
		RETURNING "value"
	`, counterKey).Scan(&counter)
	if err != nil {
		return "", fmt.Errorf("failed to generate transfer counter: %w", err)
	}

	return fmt.Sprintf("TR%s%06d", dateKey, counter), nil
}

func (r *inventoryTransferRepositoryPG) Create(ctx context.Context, transfer *InventoryTransfer, items []InventoryTransferItem) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	_, err = tx.ExecContext(ctx, `
		INSERT INTO "inventory_transfer"(
			"id", "from_branch_id", "to_branch_id", "created_by",
			"status", "notes", "created_at"
		) VALUES ($1, $2, $3, $4, $5, $6, $7)
	`,
		transfer.ID,
		transfer.FromBranchID,
		transfer.ToBranchID,
		transfer.CreatedBy,
		transfer.Status,
		transfer.Notes,
		transfer.CreatedAt,
	)
	if err != nil {
		return err
	}

	for _, item := range items {
		_, err = tx.ExecContext(ctx, `
			INSERT INTO "inventory_transfer_item"(
				"transfer_id", "part_code", "requested_qty"
			) VALUES ($1, $2, $3)
		`, item.TransferID, item.PartCode, item.RequestedQty)
		if err != nil {
			return err
		}
	}

	return tx.Commit()
}

func (r *inventoryTransferRepositoryPG) GetByID(ctx context.Context, id string) (*InventoryTransfer, []InventoryTransferItem, error) {
	row := r.db.QueryRowContext(ctx, `
		SELECT
			"id", "from_branch_id", "to_branch_id", "created_by",
			"status", "notes", "created_at",
			"approved_at", "approved_by",
			"dispatched_at", "dispatched_by",
			"received_at", "received_by"
		FROM "inventory_transfer"
		WHERE "id" = $1
	`, id)

	transfer, err := scanInventoryTransfer(row)
	if err != nil {
		return nil, nil, err
	}

	rows, err := r.db.QueryContext(ctx, `
		SELECT
			iti."transfer_id", iti."part_code",
			iti."requested_qty", iti."dispatched_qty", iti."received_qty",
			COALESCE(pm."name", '') AS part_name,
			COALESCE(pm."name_th", '') AS part_name_th,
			COALESCE(pm."unit_id", '') AS unit
		FROM "inventory_transfer_item" iti
		LEFT JOIN "part_master" pm ON pm."code" = iti."part_code"
		WHERE iti."transfer_id" = $1
		ORDER BY iti."part_code"
	`, id)
	if err != nil {
		return nil, nil, err
	}
	defer rows.Close()

	items := make([]InventoryTransferItem, 0)
	for rows.Next() {
		var item InventoryTransferItem
		var dispatchedQty, receivedQty sql.NullInt64
		if err := rows.Scan(
			&item.TransferID,
			&item.PartCode,
			&item.RequestedQty,
			&dispatchedQty,
			&receivedQty,
			&item.PartName,
			&item.PartNameTH,
			&item.Unit,
		); err != nil {
			return nil, nil, err
		}
		if dispatchedQty.Valid {
			v := int(dispatchedQty.Int64)
			item.DispatchedQty = &v
		}
		if receivedQty.Valid {
			v := int(receivedQty.Int64)
			item.ReceivedQty = &v
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, nil, err
	}

	return transfer, items, nil
}

func (r *inventoryTransferRepositoryPG) List(ctx context.Context, limit, offset int, status, fromBranchID, toBranchID *string) ([]InventoryTransfer, error) {
	if limit <= 0 {
		limit = 50
	}
	if offset < 0 {
		offset = 0
	}

	query := `
		SELECT
			"id", "from_branch_id", "to_branch_id", "created_by",
			"status", "notes", "created_at",
			"approved_at", "approved_by",
			"dispatched_at", "dispatched_by",
			"received_at", "received_by"
		FROM "inventory_transfer"
	`
	args := make([]interface{}, 0)
	argIndex := 1
	conditions := make([]string, 0)

	if status != nil && strings.TrimSpace(*status) != "" {
		conditions = append(conditions, fmt.Sprintf(`"status" = $%d`, argIndex))
		args = append(args, strings.TrimSpace(*status))
		argIndex++
	}
	if fromBranchID != nil && strings.TrimSpace(*fromBranchID) != "" {
		conditions = append(conditions, fmt.Sprintf(`"from_branch_id" = $%d`, argIndex))
		args = append(args, strings.TrimSpace(*fromBranchID))
		argIndex++
	}
	if toBranchID != nil && strings.TrimSpace(*toBranchID) != "" {
		conditions = append(conditions, fmt.Sprintf(`"to_branch_id" = $%d`, argIndex))
		args = append(args, strings.TrimSpace(*toBranchID))
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

	transfers := make([]InventoryTransfer, 0)
	for rows.Next() {
		t, scanErr := scanInventoryTransfer(rows)
		if scanErr != nil {
			return nil, scanErr
		}
		transfers = append(transfers, *t)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	return transfers, nil
}

func (r *inventoryTransferRepositoryPG) UpdateStatus(ctx context.Context, id, status, userID string, timestamp time.Time) error {
	var query string
	switch status {
	case "approved":
		query = `UPDATE "inventory_transfer" SET "status"=$1, "approved_at"=$2, "approved_by"=$3 WHERE "id"=$4`
	case "dispatched":
		query = `UPDATE "inventory_transfer" SET "status"=$1, "dispatched_at"=$2, "dispatched_by"=$3 WHERE "id"=$4`
	case "received":
		query = `UPDATE "inventory_transfer" SET "status"=$1, "received_at"=$2, "received_by"=$3 WHERE "id"=$4`
	default:
		// cancelled or other statuses without timestamps
		_, err := r.db.ExecContext(ctx, `UPDATE "inventory_transfer" SET "status"=$1 WHERE "id"=$2`, status, id)
		return err
	}

	_, err := r.db.ExecContext(ctx, query, status, timestamp, userID, id)
	return err
}

func (r *inventoryTransferRepositoryPG) UpdateItemsDispatched(ctx context.Context, transferID string, items []InventoryTransferItem) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	for _, item := range items {
		_, err = tx.ExecContext(ctx, `
			UPDATE "inventory_transfer_item"
			SET "dispatched_qty" = $1
			WHERE "transfer_id" = $2 AND "part_code" = $3
		`, item.DispatchedQty, transferID, item.PartCode)
		if err != nil {
			return err
		}

		// Adjust HQ (from_branch) address_master: subtract dispatched qty
		var fromBranchID string
		err = tx.QueryRowContext(ctx, `SELECT "from_branch_id" FROM "inventory_transfer" WHERE "id" = $1`, transferID).Scan(&fromBranchID)
		if err != nil {
			return err
		}

		qty := 0
		if item.DispatchedQty != nil {
			qty = *item.DispatchedQty
		}
		if err := r.adjustAddressQtyTx(ctx, tx, fromBranchID, item.PartCode, -qty); err != nil {
			return err
		}
	}

	return tx.Commit()
}

func (r *inventoryTransferRepositoryPG) UpdateItemsReceived(ctx context.Context, transferID string, items []InventoryTransferItem) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	for _, item := range items {
		_, err = tx.ExecContext(ctx, `
			UPDATE "inventory_transfer_item"
			SET "received_qty" = $1
			WHERE "transfer_id" = $2 AND "part_code" = $3
		`, item.ReceivedQty, transferID, item.PartCode)
		if err != nil {
			return err
		}

		// Adjust Van (to_branch) address_master: add received qty
		var toBranchID string
		err = tx.QueryRowContext(ctx, `SELECT "to_branch_id" FROM "inventory_transfer" WHERE "id" = $1`, transferID).Scan(&toBranchID)
		if err != nil {
			return err
		}

		qty := 0
		if item.ReceivedQty != nil {
			qty = *item.ReceivedQty
		}
		if err := r.adjustAddressQtyTx(ctx, tx, toBranchID, item.PartCode, qty); err != nil {
			return err
		}
	}

	return tx.Commit()
}

// adjustAddressQtyTx updates address_master qty for the default store of branchID within a transaction.
// If 0 rows affected (part not stocked at that branch), silently skip.
func (r *inventoryTransferRepositoryPG) adjustAddressQtyTx(ctx context.Context, tx *sql.Tx, branchID, partCode string, delta int) error {
	_, err := tx.ExecContext(ctx, `
		UPDATE "address_master"
		SET "qty" = GREATEST(0, "qty" + $1)
		WHERE "code" = (
			SELECT am."code"
			FROM "address_master" am
			JOIN "branch_store" bs ON bs."store_id" = am."store_id"
			WHERE am."part_code" = $2 AND bs."branch_id" = $3 AND bs."is_default" = true
			LIMIT 1
		)
	`, delta, partCode, branchID)
	return err
}

type inventoryTransferScanner interface {
	Scan(dest ...interface{}) error
}

func scanInventoryTransfer(scanner inventoryTransferScanner) (*InventoryTransfer, error) {
	var t InventoryTransfer
	var approvedAt, dispatchedAt, receivedAt sql.NullTime
	var approvedBy, dispatchedBy, receivedBy sql.NullString

	err := scanner.Scan(
		&t.ID,
		&t.FromBranchID,
		&t.ToBranchID,
		&t.CreatedBy,
		&t.Status,
		&t.Notes,
		&t.CreatedAt,
		&approvedAt,
		&approvedBy,
		&dispatchedAt,
		&dispatchedBy,
		&receivedAt,
		&receivedBy,
	)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, ErrNotFound
		}
		return nil, err
	}

	if approvedAt.Valid {
		t.ApprovedAt = &approvedAt.Time
	}
	if approvedBy.Valid {
		t.ApprovedBy = approvedBy.String
	}
	if dispatchedAt.Valid {
		t.DispatchedAt = &dispatchedAt.Time
	}
	if dispatchedBy.Valid {
		t.DispatchedBy = dispatchedBy.String
	}
	if receivedAt.Valid {
		t.ReceivedAt = &receivedAt.Time
	}
	if receivedBy.Valid {
		t.ReceivedBy = receivedBy.String
	}

	return &t, nil
}
