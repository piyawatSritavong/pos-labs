package repository

import (
	"context"
	"crypto/sha1"
	"database/sql"
	"encoding/hex"
	"errors"
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
			"id", "from_branch_id", "to_branch_id", "from_store_id", "to_store_id",
			"transfer_mode", "target_pos_id", "created_by",
			"status", "notes", "created_at"
		) VALUES ($1, $2, $3, NULLIF($4, ''), NULLIF($5, ''), $6, NULLIF($7, ''), $8, $9, $10, $11)
	`,
		transfer.ID,
		transfer.FromBranchID,
		transfer.ToBranchID,
		transfer.FromStoreID,
		transfer.ToStoreID,
		transferModeOrStandard(transfer.TransferMode),
		transfer.TargetPOSID,
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
			"id", "from_branch_id", "to_branch_id",
			COALESCE("from_store_id", ''), COALESCE("to_store_id", ''),
			COALESCE("transfer_mode", 'standard'), COALESCE("target_pos_id", ''), "created_by",
			"status", "notes", "created_at",
			"submitted_at", "submitted_by",
			"approved_at", "approved_by",
			"dispatched_at", "dispatched_by",
			"received_at", "received_by",
			"completed_at", "completed_by", COALESCE("total_sale_value", 0)
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
			iti."requested_qty", iti."approved_qty", COALESCE(iti."remarks", ''),
			iti."dispatched_qty", iti."received_qty",
			COALESCE(pm."bar_code", '') AS bar_code,
			COALESCE(pm."name", '') AS part_name,
			COALESCE(pm."name_th", '') AS part_name_th,
			COALESCE(pm."unit_id", '') AS unit,
			COALESCE(iti."sale_price", pm."price", 0),
			COALESCE(
				iti."line_total",
				iti."requested_qty" * COALESCE(iti."sale_price", pm."price", 0),
				0
			)
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
		var approvedQty, dispatchedQty, receivedQty sql.NullInt64
		if err := rows.Scan(
			&item.TransferID,
			&item.PartCode,
			&item.RequestedQty,
			&approvedQty,
			&item.Remarks,
			&dispatchedQty,
			&receivedQty,
			&item.BarCode,
			&item.PartName,
			&item.PartNameTH,
			&item.Unit,
			&item.SalePrice,
			&item.LineTotal,
		); err != nil {
			return nil, nil, err
		}
		if approvedQty.Valid {
			v := int(approvedQty.Int64)
			item.ApprovedQty = &v
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

func (r *inventoryTransferRepositoryPG) List(ctx context.Context, limit, offset int, status, fromBranchID, toBranchID, transferMode, createdBy *string) ([]InventoryTransfer, error) {
	if limit <= 0 {
		limit = 50
	}
	if offset < 0 {
		offset = 0
	}

	query := `
		SELECT
			"id", "from_branch_id", "to_branch_id",
			COALESCE("from_store_id", ''), COALESCE("to_store_id", ''),
			COALESCE("transfer_mode", 'standard'), COALESCE("target_pos_id", ''), "created_by",
			"status", "notes", "created_at",
			"submitted_at", "submitted_by",
			"approved_at", "approved_by",
			"dispatched_at", "dispatched_by",
			"received_at", "received_by",
			"completed_at", "completed_by", COALESCE("total_sale_value", 0)
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
	if transferMode != nil && strings.TrimSpace(*transferMode) != "" {
		conditions = append(conditions, fmt.Sprintf(`"transfer_mode" = $%d`, argIndex))
		args = append(args, strings.TrimSpace(*transferMode))
		argIndex++
	}
	if createdBy != nil && strings.TrimSpace(*createdBy) != "" {
		conditions = append(conditions, fmt.Sprintf(`"created_by" = $%d`, argIndex))
		args = append(args, strings.TrimSpace(*createdBy))
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

func (r *inventoryTransferRepositoryPG) UpdateItems(ctx context.Context, transferID string, items []InventoryTransferItem) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	var mode, status string
	if err := tx.QueryRowContext(ctx, `
		SELECT COALESCE("transfer_mode", 'standard'), "status"
		FROM "inventory_transfer"
		WHERE "id" = $1
		FOR UPDATE
	`, transferID).Scan(&mode, &status); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return ErrNotFound
		}
		return err
	}
	if mode != "pos_restock" {
		return fmt.Errorf("invalid_transfer_mode")
	}
	if status != "draft" {
		return fmt.Errorf("invalid_status")
	}

	_, err = tx.ExecContext(ctx, `
		DELETE FROM "inventory_transfer_item"
		WHERE "transfer_id" = $1
	`, transferID)
	if err != nil {
		return err
	}

	for _, item := range items {
		_, err = tx.ExecContext(ctx, `
			INSERT INTO "inventory_transfer_item"(
				"transfer_id", "part_code", "requested_qty"
			) VALUES ($1, $2, $3)
		`, transferID, strings.TrimSpace(item.PartCode), item.RequestedQty)
		if err != nil {
			return err
		}
	}

	return tx.Commit()
}

// SubmitPosRestock snapshots the current selling price and moves a draft to
// review atomically. HQ must see the exact value that will later be used when
// the stock movement is approved.
func (r *inventoryTransferRepositoryPG) SubmitPosRestock(ctx context.Context, transferID, userID string, timestamp time.Time) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	var mode, status string
	if err := tx.QueryRowContext(ctx, `
		SELECT COALESCE("transfer_mode", 'standard'), "status"
		FROM "inventory_transfer"
		WHERE "id" = $1
		FOR UPDATE
	`, transferID).Scan(&mode, &status); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return ErrNotFound
		}
		return err
	}
	if mode != "pos_restock" {
		return fmt.Errorf("invalid_transfer_mode")
	}
	if status != "draft" {
		return fmt.Errorf("invalid_status")
	}

	var itemCount int
	if err := tx.QueryRowContext(ctx, `
		SELECT COUNT(*) FROM "inventory_transfer_item" WHERE "transfer_id" = $1
	`, transferID).Scan(&itemCount); err != nil {
		return err
	}
	if itemCount == 0 {
		return fmt.Errorf("missing_items")
	}

	// Hold a share lock on each current product through the snapshot update so
	// an overlapping product edit cannot change the price midway through submit.
	partRows, err := tx.QueryContext(ctx, `
		SELECT p."code"
		FROM "inventory_transfer_item" i
		JOIN "part_master" p
		  ON p."code" = i."part_code" AND p."is_active" = true
		WHERE i."transfer_id" = $1
		ORDER BY p."code"
		FOR SHARE OF p
	`, transferID)
	if err != nil {
		return err
	}
	activePartCount := 0
	for partRows.Next() {
		var code string
		if err := partRows.Scan(&code); err != nil {
			_ = partRows.Close()
			return err
		}
		activePartCount++
	}
	if err := partRows.Close(); err != nil {
		return err
	}
	if err := partRows.Err(); err != nil {
		return err
	}
	if activePartCount != itemCount {
		return fmt.Errorf("missing_or_inactive_items")
	}

	if _, err := tx.ExecContext(ctx, `
		UPDATE "inventory_transfer_item" i
		SET "sale_price" = p."price",
		    "line_total" = i."requested_qty" * p."price"
		FROM "part_master" p
		WHERE i."transfer_id" = $1
		  AND p."code" = i."part_code"
		  AND p."is_active" = true
	`, transferID); err != nil {
		return err
	}

	if _, err := tx.ExecContext(ctx, `
		UPDATE "inventory_transfer"
		SET "status" = 'review',
		    "submitted_at" = $2,
		    "submitted_by" = $3,
		    "total_sale_value" = (
		      SELECT COALESCE(SUM("line_total"), 0)
		      FROM "inventory_transfer_item"
		      WHERE "transfer_id" = $1
		    )
		WHERE "id" = $1
	`, transferID, timestamp, userID); err != nil {
		return err
	}

	if _, err := tx.ExecContext(ctx, `
		INSERT INTO "inventory_transfer_audit"("transfer_id", "action", "actor_id", "notes", "created_at")
		VALUES ($1, 'submitted_for_review', $2, '', $3)
	`, transferID, userID, timestamp); err != nil {
		return err
	}

	return tx.Commit()
}

func (r *inventoryTransferRepositoryPG) UpdateStatus(ctx context.Context, id, status, userID string, timestamp time.Time) error {
	var query string
	switch status {
	case "review":
		query = `UPDATE "inventory_transfer" SET "status"=$1, "submitted_at"=$2, "submitted_by"=$3 WHERE "id"=$4`
	case "approved":
		query = `UPDATE "inventory_transfer" SET "status"=$1, "approved_at"=$2, "approved_by"=$3 WHERE "id"=$4`
	case "dispatched":
		query = `UPDATE "inventory_transfer" SET "status"=$1, "dispatched_at"=$2, "dispatched_by"=$3 WHERE "id"=$4`
	case "received":
		query = `UPDATE "inventory_transfer" SET "status"=$1, "received_at"=$2, "received_by"=$3 WHERE "id"=$4`
	case "completed":
		query = `UPDATE "inventory_transfer" SET "status"=$1, "completed_at"=$2, "completed_by"=$3 WHERE "id"=$4`
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

func (r *inventoryTransferRepositoryPG) CompletePosRestock(ctx context.Context, transferID, userID string, timestamp time.Time) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	var transfer InventoryTransfer
	err = tx.QueryRowContext(ctx, `
		SELECT
			"id", "from_branch_id", "to_branch_id",
			COALESCE("from_store_id", ''), COALESCE("to_store_id", ''),
			COALESCE("transfer_mode", 'standard'), COALESCE("target_pos_id", ''), "created_by",
			"status", "notes", "created_at"
		FROM "inventory_transfer"
		WHERE "id" = $1
		FOR UPDATE
	`, transferID).Scan(
		&transfer.ID,
		&transfer.FromBranchID,
		&transfer.ToBranchID,
		&transfer.FromStoreID,
		&transfer.ToStoreID,
		&transfer.TransferMode,
		&transfer.TargetPOSID,
		&transfer.CreatedBy,
		&transfer.Status,
		&transfer.Notes,
		&transfer.CreatedAt,
	)
	if err != nil {
		if err == sql.ErrNoRows {
			return ErrNotFound
		}
		return err
	}
	if transfer.TransferMode != "pos_restock" {
		return fmt.Errorf("invalid_transfer_mode")
	}
	if transfer.Status != "review" {
		return fmt.Errorf("invalid_status")
	}
	if strings.TrimSpace(transfer.FromStoreID) == "" || strings.TrimSpace(transfer.ToStoreID) == "" {
		return fmt.Errorf("missing_store")
	}
	if transfer.FromStoreID != "main" {
		return fmt.Errorf("invalid_source_warehouse")
	}
	var sourceType, destinationType string
	if err := tx.QueryRowContext(ctx, `SELECT "location_type" FROM "store_master" WHERE "id" = $1`, transfer.FromStoreID).Scan(&sourceType); err != nil {
		return err
	}
	if err := tx.QueryRowContext(ctx, `SELECT "location_type" FROM "store_master" WHERE "id" = $1`, transfer.ToStoreID).Scan(&destinationType); err != nil {
		return err
	}
	if sourceType != "warehouse" || destinationType != "vehicle" {
		return fmt.Errorf("invalid_stock_location_type")
	}
	var configuredVehicleStore string
	if err := tx.QueryRowContext(ctx, `
		SELECT COALESCE("vehicle_store_id", '') FROM "pos_setting" WHERE "pos_id" = $1
	`, transfer.TargetPOSID).Scan(&configuredVehicleStore); err != nil {
		return err
	}
	if configuredVehicleStore != transfer.ToStoreID {
		return fmt.Errorf("target_pos_store_mismatch")
	}

	// What actually moves is what HQ approved. A line reviewed down to zero
	// stays on the document — with its remark — but ships nothing.
	rows, err := tx.QueryContext(ctx, `
		SELECT i."part_code", COALESCE(i."approved_qty", i."requested_qty"),
		       COALESCE(i."sale_price", p."price")
		FROM "inventory_transfer_item" i
		JOIN "part_master" p ON p."code" = i."part_code" AND p."is_active" = true
		WHERE i."transfer_id" = $1
		ORDER BY i."part_code"
	`, transferID)
	if err != nil {
		return err
	}

	type sourceAddress struct {
		code string
		qty  int
	}
	type moveItem struct {
		partCode string
		// What HQ approved: the requested quantity unless review changed it.
		moveQty         int
		salePrice       float64
		sourceAddresses []sourceAddress
		availableQty    int
	}
	moveItems := make([]moveItem, 0)
	for rows.Next() {
		var item moveItem
		if err := rows.Scan(&item.partCode, &item.moveQty, &item.salePrice); err != nil {
			_ = rows.Close()
			return err
		}
		moveItems = append(moveItems, item)
	}
	if err := rows.Close(); err != nil {
		return err
	}
	if err := rows.Err(); err != nil {
		return err
	}
	if len(moveItems) == 0 {
		return fmt.Errorf("missing_items")
	}

	shortages := make([]InventoryShortage, 0)
	for i := range moveItems {
		addressRows, err := tx.QueryContext(ctx, `
			SELECT "code", COALESCE("qty", 0)
			FROM "address_master"
			WHERE "store_id" = $1 AND "part_code" = $2 AND "is_active" = true
			ORDER BY "code"
			FOR UPDATE
		`, transfer.FromStoreID, moveItems[i].partCode)
		if err != nil {
			return err
		}
		for addressRows.Next() {
			var address sourceAddress
			if err := addressRows.Scan(&address.code, &address.qty); err != nil {
				_ = addressRows.Close()
				return err
			}
			moveItems[i].sourceAddresses = append(moveItems[i].sourceAddresses, address)
			moveItems[i].availableQty += address.qty
		}
		if err := addressRows.Close(); err != nil {
			return err
		}
		if err := addressRows.Err(); err != nil {
			return err
		}
		if moveItems[i].availableQty < moveItems[i].moveQty {
			shortages = append(shortages, InventoryShortage{
				PartCode:     moveItems[i].partCode,
				RequestedQty: moveItems[i].moveQty,
				AvailableQty: moveItems[i].availableQty,
				MissingQty:   moveItems[i].moveQty - moveItems[i].availableQty,
			})
		}
	}
	if len(shortages) > 0 {
		return &InsufficientStockError{Shortages: shortages}
	}

	for _, item := range moveItems {
		_, err = tx.ExecContext(ctx, `
			UPDATE "inventory_transfer_item"
			SET "dispatched_qty" = $1, "received_qty" = $1,
			    "sale_price" = $2, "line_total" = $1::integer * $2::numeric
			WHERE "transfer_id" = $3 AND "part_code" = $4
		`, item.moveQty, item.salePrice, transferID, item.partCode)
		if err != nil {
			return err
		}

		remaining := item.moveQty
		for _, address := range item.sourceAddresses {
			if remaining == 0 {
				break
			}
			deduct := address.qty
			if deduct > remaining {
				deduct = remaining
			}
			if _, err = tx.ExecContext(ctx, `
				UPDATE "address_master"
				SET "qty" = "qty" - $1
				WHERE "code" = $2 AND "is_active" = true
			`, deduct, address.code); err != nil {
				return err
			}
			remaining -= deduct
		}

		var destAddrCode string
		err = tx.QueryRowContext(ctx, `
			SELECT "code"
			FROM "address_master"
			WHERE "store_id" = $1 AND "part_code" = $2
			ORDER BY "is_active" DESC, "code"
			LIMIT 1
			FOR UPDATE
		`, transfer.ToStoreID, item.partCode).Scan(&destAddrCode)
		if err != nil {
			if err != sql.ErrNoRows {
				return err
			}
			destAddrCode = vehicleAddressCode(transfer.ToStoreID, item.partCode)
			_, err = tx.ExecContext(ctx, `
				INSERT INTO "address_master"(
					"code", "part_code", "store_id", "shelf",
					"qty", "rop", "remarks"
				) VALUES ($1, $2, $3, 'รถ', $4, 0, 'สร้างจากใบเบิกสินค้าเข้ารถ')
			`, destAddrCode, item.partCode, transfer.ToStoreID, item.moveQty)
			if err != nil {
				return err
			}
		} else {
			_, err = tx.ExecContext(ctx, `
				UPDATE "address_master"
				SET "qty" = "qty" + $1, "is_active" = true
				WHERE "code" = $2
			`, item.moveQty, destAddrCode)
			if err != nil {
				return err
			}
		}
	}

	_, err = tx.ExecContext(ctx, `
		UPDATE "inventory_transfer"
		SET "status" = 'completed',
		    "approved_at" = $1, "approved_by" = $2,
		    "dispatched_at" = $1, "dispatched_by" = $2,
		    "received_at" = $1, "received_by" = $2,
			    "completed_at" = $1, "completed_by" = $2,
			    "total_sale_value" = (
			      SELECT COALESCE(SUM("line_total"), 0)
			      FROM "inventory_transfer_item" WHERE "transfer_id" = $3
			    )
		WHERE "id" = $3
	`, timestamp, userID, transferID)
	if err != nil {
		return err
	}

	if _, err := tx.ExecContext(ctx, `
		INSERT INTO "inventory_transfer_audit"("transfer_id", "action", "actor_id", "notes", "created_at")
		VALUES ($1, 'approved', $2, '', $3), ($1, 'completed', $2, '', $3)
	`, transferID, userID, timestamp); err != nil {
		return err
	}

	return tx.Commit()
}

func (r *inventoryTransferRepositoryPG) LogAudit(ctx context.Context, transferID, action, actorID, notes string) error {
	_, err := r.db.ExecContext(ctx, `
		INSERT INTO "inventory_transfer_audit"("transfer_id", "action", "actor_id", "notes")
		VALUES ($1, $2, NULLIF($3, ''), $4)
	`, transferID, action, actorID, notes)
	return err
}

func (r *inventoryTransferRepositoryPG) ListCompletedRestocksByPOSDate(
	ctx context.Context,
	posID string,
	start time.Time,
	end time.Time,
) ([]InventoryTransfer, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT
			"id", "from_branch_id", "to_branch_id",
			COALESCE("from_store_id", ''), COALESCE("to_store_id", ''),
			COALESCE("transfer_mode", 'standard'), COALESCE("target_pos_id", ''), "created_by",
			"status", "notes", "created_at",
			"submitted_at", "submitted_by",
			"approved_at", "approved_by",
			"dispatched_at", "dispatched_by",
			"received_at", "received_by",
			"completed_at", "completed_by", COALESCE("total_sale_value", 0)
		FROM "inventory_transfer"
		WHERE "transfer_mode" = 'pos_restock'
		  AND "status" = 'completed'
		  AND "target_pos_id" = $1
		  AND "completed_at" >= $2
		  AND "completed_at" < $3
		ORDER BY "completed_at", "id"
	`, strings.TrimSpace(posID), start, end)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	result := make([]InventoryTransfer, 0)
	for rows.Next() {
		transfer, err := scanInventoryTransfer(rows)
		if err != nil {
			return nil, err
		}
		result = append(result, *transfer)
	}
	return result, rows.Err()
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
			WHERE am."part_code" = $2 AND am."is_active" = true
			  AND bs."branch_id" = $3 AND bs."is_default" = true
			LIMIT 1
		)
	`, delta, partCode, branchID)
	return err
}

func transferModeOrStandard(mode string) string {
	if strings.TrimSpace(mode) == "" {
		return "standard"
	}
	return strings.TrimSpace(mode)
}

func vehicleAddressCode(storeID, partCode string) string {
	sum := sha1.Sum([]byte(storeID + ":" + partCode))
	return "VEH" + strings.ToUpper(hex.EncodeToString(sum[:10]))
}

type inventoryTransferScanner interface {
	Scan(dest ...interface{}) error
}

func scanInventoryTransfer(scanner inventoryTransferScanner) (*InventoryTransfer, error) {
	var t InventoryTransfer
	var submittedAt, approvedAt, dispatchedAt, receivedAt, completedAt sql.NullTime
	var submittedBy, approvedBy, dispatchedBy, receivedBy, completedBy sql.NullString

	err := scanner.Scan(
		&t.ID,
		&t.FromBranchID,
		&t.ToBranchID,
		&t.FromStoreID,
		&t.ToStoreID,
		&t.TransferMode,
		&t.TargetPOSID,
		&t.CreatedBy,
		&t.Status,
		&t.Notes,
		&t.CreatedAt,
		&submittedAt,
		&submittedBy,
		&approvedAt,
		&approvedBy,
		&dispatchedAt,
		&dispatchedBy,
		&receivedAt,
		&receivedBy,
		&completedAt,
		&completedBy,
		&t.TotalSaleValue,
	)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, ErrNotFound
		}
		return nil, err
	}

	if submittedAt.Valid {
		t.SubmittedAt = &submittedAt.Time
	}
	if submittedBy.Valid {
		t.SubmittedBy = submittedBy.String
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
	if completedAt.Valid {
		t.CompletedAt = &completedAt.Time
	}
	if completedBy.Valid {
		t.CompletedBy = completedBy.String
	}

	return &t, nil
}

// ReviewRestockItems records what HQ decided while checking a restock against
// the paper slip. It only touches a request that is waiting for review, and it
// never overwrites requested_qty — the gap between what was asked for and what
// is being issued is the thing worth keeping.
func (r *inventoryTransferRepositoryPG) ReviewRestockItems(
	ctx context.Context, transferID, actorID string, adjustments []RestockAdjustment,
) error {
	if len(adjustments) == 0 {
		return nil
	}
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	var mode, status string
	if err := tx.QueryRowContext(ctx, `
		SELECT COALESCE("transfer_mode", 'standard'), "status"
		FROM "inventory_transfer"
		WHERE "id" = $1
		FOR UPDATE
	`, transferID).Scan(&mode, &status); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return ErrNotFound
		}
		return err
	}
	if mode != "pos_restock" {
		return fmt.Errorf("invalid_transfer_mode")
	}
	if status != "review" {
		return fmt.Errorf("invalid_status")
	}

	changes := make([]string, 0, len(adjustments))
	for _, adjustment := range adjustments {
		partCode := strings.TrimSpace(adjustment.PartCode)
		if partCode == "" {
			continue
		}
		if adjustment.ApprovedQty < 0 {
			return fmt.Errorf("invalid_qty")
		}
		var requested int
		if err := tx.QueryRowContext(ctx, `
			SELECT "requested_qty" FROM "inventory_transfer_item"
			WHERE "transfer_id" = $1 AND "part_code" = $2
			FOR UPDATE
		`, transferID, partCode).Scan(&requested); err != nil {
			if errors.Is(err, sql.ErrNoRows) {
				return fmt.Errorf("item_not_found:%s", partCode)
			}
			return err
		}
		// Storing NULL when the reviewer agreed with the request keeps
		// "checked and unchanged" distinguishable from "never looked at".
		var approved interface{} = adjustment.ApprovedQty
		if adjustment.ApprovedQty == requested {
			approved = nil
		} else {
			changes = append(changes, fmt.Sprintf("%s %d→%d", partCode, requested, adjustment.ApprovedQty))
		}
		if _, err := tx.ExecContext(ctx, `
			UPDATE "inventory_transfer_item"
			SET "approved_qty" = $1, "remarks" = $2
			WHERE "transfer_id" = $3 AND "part_code" = $4
		`, approved, strings.TrimSpace(adjustment.Remarks), transferID, partCode); err != nil {
			return err
		}
	}

	note := "ตรวจสอบรายการแล้ว ไม่มีการแก้จำนวน"
	if len(changes) > 0 {
		note = "แก้จำนวนตอนตรวจสอบ: " + strings.Join(changes, ", ")
	}
	if _, err := tx.ExecContext(ctx, `
		INSERT INTO "inventory_transfer_audit"("transfer_id", "action", "actor_id", "notes")
		VALUES ($1, 'review_adjust', $2, $3)
	`, transferID, actorID, note); err != nil {
		return err
	}

	return tx.Commit()
}

// UpdateNotes replaces the note on the document itself, which is where a
// reviewer explains the slip as a whole rather than one line of it.
func (r *inventoryTransferRepositoryPG) UpdateNotes(ctx context.Context, transferID, notes string) error {
	result, err := r.db.ExecContext(ctx, `
		UPDATE "inventory_transfer" SET "notes" = $2 WHERE "id" = $1
	`, transferID, strings.TrimSpace(notes))
	if err != nil {
		return err
	}
	if affected, _ := result.RowsAffected(); affected == 0 {
		return ErrNotFound
	}
	return nil
}
