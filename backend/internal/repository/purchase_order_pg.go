package repository

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"
)

type purchaseOrderRepositoryPG struct{ db *sql.DB }

func NewPurchaseOrderRepository(db *sql.DB) PurchaseOrderRepository {
	return &purchaseOrderRepositoryPG{db: db}
}

func (r *purchaseOrderRepositoryPG) Create(
	ctx context.Context,
	requestID string,
	orderDate time.Time,
	notes string,
	userID string,
	input []PurchaseOrderInputItem,
) (*PurchaseOrder, []PurchaseOrderItem, bool, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, nil, false, err
	}
	defer func() { _ = tx.Rollback() }()

	var existingID string
	err = tx.QueryRowContext(ctx, `SELECT "id" FROM "purchase_order" WHERE "request_id" = $1`, requestID).Scan(&existingID)
	if err == nil {
		if err := tx.Commit(); err != nil {
			return nil, nil, false, err
		}
		order, items, err := r.GetByID(ctx, existingID)
		return order, items, false, err
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return nil, nil, false, err
	}
	if _, err := tx.ExecContext(ctx, `SELECT pg_advisory_xact_lock(hashtext('purchase-order-and-part-sequence'))`); err != nil {
		return nil, nil, false, err
	}
	// A concurrent request with the same idempotency key may have committed while
	// this transaction waited for the advisory lock. Re-check under the lock so a
	// browser retry can never create a second receipt or add stock twice.
	err = tx.QueryRowContext(ctx, `SELECT "id" FROM "purchase_order" WHERE "request_id" = $1`, requestID).Scan(&existingID)
	if err == nil {
		if err := tx.Commit(); err != nil {
			return nil, nil, false, err
		}
		order, items, err := r.GetByID(ctx, existingID)
		return order, items, false, err
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return nil, nil, false, err
	}

	dateKey := orderDate.Format("20060102")
	var sequence int
	if err := tx.QueryRowContext(ctx, `
		INSERT INTO "counter"("key", "value") VALUES ($1, 1)
		ON CONFLICT ("key") DO UPDATE SET "value" = "counter"."value" + 1
		RETURNING "value"
	`, "po_"+dateKey).Scan(&sequence); err != nil {
		return nil, nil, false, err
	}
	orderID := fmt.Sprintf("PO%s%06d", dateKey, sequence)

	var nextPartNumber int
	if err := tx.QueryRowContext(ctx, `
		SELECT COALESCE(MAX(CASE WHEN "code" ~ '^P[0-9]+$' THEN SUBSTRING("code" FROM 2)::integer END), 0)
		FROM "part_master"
	`).Scan(&nextPartNumber); err != nil {
		return nil, nil, false, err
	}

	resolved := make([]PurchaseOrderItem, 0, len(input))
	seenCodes := make(map[string]struct{}, len(input))
	seenBarcodes := make(map[string]string, len(input))
	totalCost, totalSale := 0.0, 0.0
	for index, raw := range input {
		code := strings.TrimSpace(raw.PartCode)
		if code == "" {
			nextPartNumber++
			code = fmt.Sprintf("P%04d", nextPartNumber)
		}
		if _, duplicate := seenCodes[code]; duplicate {
			return nil, nil, false, fmt.Errorf("duplicate_part_code:%s", code)
		}
		seenCodes[code] = struct{}{}
		barcode := strings.TrimSpace(raw.BarCode)
		if barcode == "" {
			barcode = code
		}
		if previousCode, duplicate := seenBarcodes[barcode]; duplicate && previousCode != code {
			return nil, nil, false, fmt.Errorf("duplicate_barcode:%s", barcode)
		}
		seenBarcodes[barcode] = code
		var conflictCode string
		err := tx.QueryRowContext(ctx, `
			SELECT "code" FROM "part_master" WHERE "bar_code" = $1 AND "code" <> $2 LIMIT 1
		`, barcode, code).Scan(&conflictCode)
		if err == nil {
			return nil, nil, false, fmt.Errorf("barcode_exists:%s:%s", barcode, conflictCode)
		}
		if !errors.Is(err, sql.ErrNoRows) {
			return nil, nil, false, err
		}

		name := strings.TrimSpace(raw.PartName)
		lineCost := float64(raw.Qty) * raw.Cost
		lineSale := float64(raw.Qty) * raw.Price
		resolved = append(resolved, PurchaseOrderItem{
			LineNo: index + 1, PartCode: code, PartName: name, BarCode: barcode,
			Qty: raw.Qty, Cost: raw.Cost, Price: raw.Price, MinPrice: raw.MinPrice,
			LineCost: lineCost, LineSaleValue: lineSale,
		})
		totalCost += lineCost
		totalSale += lineSale
	}

	if _, err := tx.ExecContext(ctx, `
		INSERT INTO "purchase_order"(
			"id", "request_id", "order_date", "notes", "created_by", "total_cost", "total_sale_value"
		) VALUES ($1, $2, $3, $4, $5, $6, $7)
	`, orderID, requestID, orderDate, strings.TrimSpace(notes), userID, totalCost, totalSale); err != nil {
		return nil, nil, false, err
	}

	for _, item := range resolved {
		if _, err := tx.ExecContext(ctx, `
			INSERT INTO "part_master"(
				"code", "bar_code", "name", "name_th", "receipt_name", "unit_id",
				"cost", "price", "min_price", "is_active"
			) VALUES ($1, $2, $3, $3, $3, 'pcs', $4, $5, $6, true)
			ON CONFLICT ("code") DO UPDATE SET
				"bar_code" = EXCLUDED."bar_code", "name" = EXCLUDED."name",
				"name_th" = EXCLUDED."name_th", "receipt_name" = EXCLUDED."receipt_name",
				"cost" = EXCLUDED."cost", "price" = EXCLUDED."price",
				"min_price" = EXCLUDED."min_price", "is_active" = true
		`, item.PartCode, item.BarCode, item.PartName, item.Cost, item.Price, item.MinPrice); err != nil {
			return nil, nil, false, err
		}

		var addressCode string
		err := tx.QueryRowContext(ctx, `
			SELECT "code" FROM "address_master"
			WHERE "part_code" = $1 AND "store_id" = 'main'
			ORDER BY "is_active" DESC, "code" LIMIT 1 FOR UPDATE
		`, item.PartCode).Scan(&addressCode)
		if errors.Is(err, sql.ErrNoRows) {
			addressCode = "ADDR-" + item.PartCode + "-main"
			if _, err := tx.ExecContext(ctx, `
				INSERT INTO "address_master"(
					"code", "part_code", "store_id", "shelf", "qty", "rop", "remarks", "is_active"
				) VALUES ($1, $2, 'main', '', $3, 0, 'รับเข้าจากใบสั่งซื้อสินค้า', true)
			`, addressCode, item.PartCode, item.Qty); err != nil {
				return nil, nil, false, err
			}
		} else if err != nil {
			return nil, nil, false, err
		} else if _, err := tx.ExecContext(ctx, `
			UPDATE "address_master" SET "qty" = "qty" + $1, "is_active" = true WHERE "code" = $2
		`, item.Qty, addressCode); err != nil {
			return nil, nil, false, err
		}

		if _, err := tx.ExecContext(ctx, `
			INSERT INTO "purchase_order_item"(
				"order_id", "line_no", "part_code", "part_name", "bar_code", "qty",
				"cost", "price", "min_price", "line_cost", "line_sale_value"
			) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
		`, orderID, item.LineNo, item.PartCode, item.PartName, item.BarCode, item.Qty,
			item.Cost, item.Price, item.MinPrice, item.LineCost, item.LineSaleValue); err != nil {
			return nil, nil, false, err
		}
	}

	if err := tx.Commit(); err != nil {
		return nil, nil, false, err
	}
	order, items, err := r.GetByID(ctx, orderID)
	return order, items, true, err
}

func (r *purchaseOrderRepositoryPG) GetByID(ctx context.Context, id string) (*PurchaseOrder, []PurchaseOrderItem, error) {
	var order PurchaseOrder
	err := r.db.QueryRowContext(ctx, `
		SELECT "id", "request_id", "order_date", "notes", "created_by", "created_at", "total_cost", "total_sale_value"
		FROM "purchase_order" WHERE "id" = $1
	`, id).Scan(&order.ID, &order.RequestID, &order.OrderDate, &order.Notes, &order.CreatedBy,
		&order.CreatedAt, &order.TotalCost, &order.TotalSaleValue)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil, ErrNotFound
	}
	if err != nil {
		return nil, nil, err
	}
	rows, err := r.db.QueryContext(ctx, `
		SELECT "line_no", "part_code", "part_name", "bar_code", "qty", "cost", "price", "min_price", "line_cost", "line_sale_value"
		FROM "purchase_order_item" WHERE "order_id" = $1 ORDER BY "line_no"
	`, id)
	if err != nil {
		return nil, nil, err
	}
	defer rows.Close()
	items := make([]PurchaseOrderItem, 0)
	for rows.Next() {
		var item PurchaseOrderItem
		if err := rows.Scan(&item.LineNo, &item.PartCode, &item.PartName, &item.BarCode, &item.Qty,
			&item.Cost, &item.Price, &item.MinPrice, &item.LineCost, &item.LineSaleValue); err != nil {
			return nil, nil, err
		}
		items = append(items, item)
	}
	return &order, items, rows.Err()
}

func (r *purchaseOrderRepositoryPG) List(ctx context.Context, limit, offset int) ([]PurchaseOrder, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT "id", "request_id", "order_date", "notes", "created_by", "created_at", "total_cost", "total_sale_value"
		FROM "purchase_order" ORDER BY "created_at" DESC LIMIT $1 OFFSET $2
	`, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	orders := make([]PurchaseOrder, 0)
	for rows.Next() {
		var order PurchaseOrder
		if err := rows.Scan(&order.ID, &order.RequestID, &order.OrderDate, &order.Notes, &order.CreatedBy,
			&order.CreatedAt, &order.TotalCost, &order.TotalSaleValue); err != nil {
			return nil, err
		}
		orders = append(orders, order)
	}
	return orders, rows.Err()
}
