package repository

import (
	"context"
	"database/sql"
	"time"
)

type vehicleInventoryRepositoryPG struct{ db *sql.DB }

func NewVehicleInventoryRepository(db *sql.DB) VehicleInventoryRepository {
	return &vehicleInventoryRepositoryPG{db: db}
}

func (r *vehicleInventoryRepositoryPG) List(ctx context.Context, posID string, start, end time.Time) ([]VehicleInventoryItem, error) {
	rows, err := r.db.QueryContext(ctx, `
		WITH selected_pos AS (
			SELECT "pos_id", "vehicle_store_id" FROM "pos_setting" WHERE "pos_id" = $1
		), current_stock AS (
			SELECT a."part_code", SUM(a."qty")::integer AS qty
			FROM "address_master" a
			JOIN selected_pos p ON p."vehicle_store_id" = a."store_id"
			WHERE a."is_active" = true
			GROUP BY a."part_code"
		), received AS (
			SELECT i."part_code", SUM(COALESCE(i."received_qty", i."requested_qty"))::integer AS qty
			FROM "inventory_transfer" t
			JOIN "inventory_transfer_item" i ON i."transfer_id" = t."id"
			WHERE t."transfer_mode" = 'pos_restock' AND t."status" = 'completed'
			  AND t."target_pos_id" = $1 AND t."completed_at" >= $2 AND t."completed_at" < $3
			GROUP BY i."part_code"
		), sold AS (
			SELECT i."part_code", SUM(i."qty")::integer AS qty
			FROM "bill_master" b
			JOIN "bill_item_detail" i ON i."bill_id" = b."id"
			WHERE b."status" = 'completed' AND b."pos_id" = $1
			  AND b."updated_at" >= $2 AND b."updated_at" < $3
			GROUP BY i."part_code"
		), returned AS (
			SELECT i."part_code", SUM(i."qty")::integer AS qty
			FROM "return_note_master" r
			JOIN "return_note_item_detail" i ON i."return_note_id" = r."id"
			WHERE r."status" = 'completed' AND r."pos_id" = $1
			  AND r."created_at" >= $2 AND r."created_at" < $3
			GROUP BY i."part_code"
		), codes AS (
			SELECT "part_code" FROM current_stock
			UNION SELECT "part_code" FROM received
			UNION SELECT "part_code" FROM sold
			UNION SELECT "part_code" FROM returned
		)
		SELECT p."code", COALESCE(p."name", ''), COALESCE(p."name_th", ''),
		       COALESCE(p."bar_code", ''), COALESCE(c.qty, 0), COALESCE(rc.qty, 0),
		       GREATEST(COALESCE(s.qty, 0) - COALESCE(rt.qty, 0), 0),
		       COALESCE(p."price", 0), COALESCE(c.qty, 0) * COALESCE(p."price", 0)
		FROM codes x
		JOIN "part_master" p ON p."code" = x."part_code"
		LEFT JOIN current_stock c ON c."part_code" = x."part_code"
		LEFT JOIN received rc ON rc."part_code" = x."part_code"
		LEFT JOIN sold s ON s."part_code" = x."part_code"
		LEFT JOIN returned rt ON rt."part_code" = x."part_code"
		ORDER BY p."code"
	`, posID, start, end)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	items := make([]VehicleInventoryItem, 0)
	for rows.Next() {
		var item VehicleInventoryItem
		if err := rows.Scan(
			&item.PartCode, &item.PartName, &item.PartNameTH, &item.BarCode,
			&item.CurrentQty, &item.ReceivedQty, &item.NetSoldQty,
			&item.Price, &item.CurrentSaleValue,
		); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}
