package repository

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"

	"backend/internal/config"

	"github.com/lib/pq"
)

type partRepositoryPG struct {
	db *sql.DB
}

func NewPartRepository(db *sql.DB) PartRepository {
	return &partRepositoryPG{db: db}
}

func (r *partRepositoryPG) ListParts(ctx context.Context, limit, offset int, branchID *string) ([]PartSummary, error) {
	if limit <= 0 {
		limit = config.DefaultLimit
	}
	if offset < 0 {
		offset = 0
	}

	var (
		rows *sql.Rows
		err  error
	)

	if branchID != nil && *branchID != "" {
		// Filter parts that have stock addresses in stores belonging to the given branch
		rows, err = r.db.QueryContext(ctx, `
			SELECT
				p.code,
				p.bar_code,
				COALESCE(p.category_id, ''),
				COALESCE(c.label, ''),
				COALESCE(c.label_th, ''),
				COALESCE(p.unit_id, ''),
				COALESCE(u.label, ''),
				COALESCE(u.label_th, ''),
				p.name,
				COALESCE(p.name_th, ''),
				COALESCE(p.receipt_name, ''),
				COALESCE(p.cost, 0),
				p.price,
				p.min_price,
				COALESCE(p.is_active, false),
				COALESCE((
					SELECT SUM(a2.qty)
					FROM "address_master" a2
					JOIN "branch_store" bs2 ON bs2.store_id = a2.store_id
					WHERE a2.part_code = p.code AND a2.is_active = true AND bs2.branch_id = $3
				), 0) AS total_stock,
				COALESCE((
					SELECT SUM(a3.rop)
					FROM "address_master" a3
					JOIN "branch_store" bs3 ON bs3.store_id = a3.store_id
					WHERE a3.part_code = p.code AND a3.is_active = true AND bs3.branch_id = $3
				), 0) AS total_rop
			FROM "part_master" p
			LEFT JOIN "category_master" c ON c.id = p.category_id
			LEFT JOIN "unit_master" u ON u.id = p.unit_id
			WHERE COALESCE(p.is_active, false) = true
			  AND EXISTS (
				SELECT 1 FROM "address_master" a
				JOIN "branch_store" bs ON bs.store_id = a.store_id
				WHERE a.part_code = p.code AND a.is_active = true AND bs.branch_id = $3
			)
			ORDER BY p.code
			LIMIT $1 OFFSET $2
		`, limit, offset, *branchID)
	} else {
		rows, err = r.db.QueryContext(ctx, `
			SELECT
				p.code,
				p.bar_code,
				COALESCE(p.category_id, ''),
				COALESCE(c.label, ''),
				COALESCE(c.label_th, ''),
				COALESCE(p.unit_id, ''),
				COALESCE(u.label, ''),
				COALESCE(u.label_th, ''),
				p.name,
				COALESCE(p.name_th, ''),
				COALESCE(p.receipt_name, ''),
				COALESCE(p.cost, 0),
				p.price,
				p.min_price,
				COALESCE(p.is_active, false),
				COALESCE(SUM(a.qty), 0) AS total_stock,
				COALESCE(SUM(a.rop), 0) AS total_rop
			FROM "part_master" p
			LEFT JOIN "category_master" c ON c.id = p.category_id
			LEFT JOIN "unit_master" u ON u.id = p.unit_id
			LEFT JOIN "address_master" a ON a.part_code = p.code AND a.is_active = true
			WHERE COALESCE(p.is_active, false) = true
			GROUP BY
				p.code, p.bar_code, p.category_id, c.label, c.label_th,
				p.unit_id, u.label, u.label_th,
				p.name, p.name_th, p.receipt_name, p.cost, p.price, p.min_price, p.is_active
			ORDER BY p.code
			LIMIT $1 OFFSET $2
		`, limit, offset)
	}
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var items []PartSummary
	for rows.Next() {
		var s PartSummary
		if err := rows.Scan(
			&s.Code,
			&s.BarCode,
			&s.CategoryID,
			&s.CategoryLabel,
			&s.CategoryLabelTH,
			&s.UnitID,
			&s.UnitLabel,
			&s.UnitLabelTH,
			&s.Name,
			&s.NameTH,
			&s.ReceiptName,
			&s.Cost,
			&s.Price,
			&s.MinPrice,
			&s.IsActive,
			&s.TotalStock,
			&s.ReorderPoint,
		); err != nil {
			return nil, err
		}
		items = append(items, s)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	return items, nil
}

func (r *partRepositoryPG) GetPartDetail(ctx context.Context, code string, branchID *string) (*PartDetail, []PartAddress, error) {
	// Header with aggregated stock, category, and unit
	// Filter stock by branch_store if branchID is provided
	var query string
	var args []interface{}
	if branchID != nil && *branchID != "" {
		query = `
			SELECT
				p.code,
				p.bar_code,
				COALESCE(p.category_id, ''),
				COALESCE(c.label, ''),
				COALESCE(c.label_th, ''),
				COALESCE(p.unit_id, ''),
				COALESCE(u.label, ''),
				COALESCE(u.label_th, ''),
				p.name,
				COALESCE(p.name_th, ''),
				COALESCE(p.receipt_name, ''),
				COALESCE(p.details, ''),
				p.cost,
				p.price,
				p.min_price,
				COALESCE(p.image, ''),
				COALESCE(p.is_active, false),
				COALESCE(SUM(CASE WHEN bs.branch_id = $2 THEN a.qty ELSE 0 END), 0) AS total_stock
			FROM "part_master" p
			LEFT JOIN "category_master" c ON c.id = p.category_id
			LEFT JOIN "unit_master" u ON u.id = p.unit_id
			LEFT JOIN "address_master" a ON a.part_code = p.code AND a.is_active = true
			LEFT JOIN "store_master" s ON s.id = a.store_id
			LEFT JOIN "branch_store" bs ON bs.store_id = s.id AND bs.branch_id = $2
			WHERE p.code = $1
			GROUP BY
				p.code, p.bar_code, p.category_id, c.label, c.label_th,
				p.unit_id, u.label, u.label_th,
				p.name, p.name_th, p.receipt_name, p.details, p.cost, p.price, p.min_price, p.image, p.is_active
		`
		args = []interface{}{code, *branchID}
	} else {
		query = `
			SELECT
				p.code,
				p.bar_code,
				COALESCE(p.category_id, ''),
				COALESCE(c.label, ''),
				COALESCE(c.label_th, ''),
				COALESCE(p.unit_id, ''),
				COALESCE(u.label, ''),
				COALESCE(u.label_th, ''),
				p.name,
				COALESCE(p.name_th, ''),
				COALESCE(p.receipt_name, ''),
				COALESCE(p.details, ''),
				p.cost,
				p.price,
				p.min_price,
				COALESCE(p.image, ''),
				COALESCE(p.is_active, false),
				COALESCE(SUM(a.qty), 0) AS total_stock
			FROM "part_master" p
			LEFT JOIN "category_master" c ON c.id = p.category_id
			LEFT JOIN "unit_master" u ON u.id = p.unit_id
			LEFT JOIN "address_master" a ON a.part_code = p.code AND a.is_active = true
			WHERE p.code = $1
			GROUP BY
				p.code, p.bar_code, p.category_id, c.label, c.label_th,
				p.unit_id, u.label, u.label_th,
				p.name, p.name_th, p.receipt_name, p.details, p.cost, p.price, p.min_price, p.image, p.is_active
		`
		args = []interface{}{code}
	}

	row := r.db.QueryRowContext(ctx, query, args...)

	var d PartDetail
	if err := row.Scan(
		&d.Code,
		&d.BarCode,
		&d.CategoryID,
		&d.CategoryLabel,
		&d.CategoryLabelTH,
		&d.UnitID,
		&d.UnitLabel,
		&d.UnitLabelTH,
		&d.Name,
		&d.NameTH,
		&d.ReceiptName,
		&d.Details,
		&d.Cost,
		&d.Price,
		&d.MinPrice,
		&d.Image,
		&d.IsActive,
		&d.TotalStock,
	); err != nil {
		if err == sql.ErrNoRows {
			return nil, nil, ErrNotFound
		}
		return nil, nil, err
	}

	// Addresses - filter by branch_store if branchID is provided
	var rows *sql.Rows
	var err error
	if branchID != nil && *branchID != "" {
		rows, err = r.db.QueryContext(ctx, `
			SELECT
				a.code,
				a.part_code,
				a.store_id,
				s.label,
				s.label_th,
				a.shelf,
				a.qty,
				a.rop,
				COALESCE(a.remarks, ''),
				COALESCE(bs.is_default, false) as is_default
			FROM "address_master" a
			JOIN "store_master" s ON s.id = a.store_id
			JOIN "branch_store" bs ON bs.store_id = s.id AND bs.branch_id = $2
			WHERE a.part_code = $1 AND a.is_active = true
			ORDER BY bs.is_default DESC, a.code
		`, code, *branchID)
	} else {
		rows, err = r.db.QueryContext(ctx, `
			SELECT
				a.code,
				a.part_code,
				a.store_id,
				s.label,
				s.label_th,
				a.shelf,
				a.qty,
				a.rop,
				COALESCE(a.remarks, ''),
				false as is_default
			FROM "address_master" a
			JOIN "store_master" s ON s.id = a.store_id
			WHERE a.part_code = $1 AND a.is_active = true
			ORDER BY a.code
		`, code)
	}
	if err != nil {
		return &d, nil, err
	}
	defer rows.Close()

	var addrs []PartAddress
	for rows.Next() {
		var a PartAddress
		if err := rows.Scan(
			&a.Code,
			&a.PartCode,
			&a.StoreID,
			&a.StoreLabel,
			&a.StoreLabelTH,
			&a.Shelf,
			&a.Qty,
			&a.Rop,
			&a.Remarks,
			&a.IsDefault,
		); err != nil {
			return &d, nil, err
		}
		addrs = append(addrs, a)
	}
	if err := rows.Err(); err != nil {
		return &d, nil, err
	}

	return &d, addrs, nil
}

// GetAddressesByPartCodes loads addresses for many part codes in one round-trip
// using `part_code = ANY($1)`, returning them grouped by part code. This
// replaces the per-part GetPartDetail calls that previously caused N+1 queries
// when building search/list responses.
func (r *partRepositoryPG) CreatePart(ctx context.Context, p PartInput) error {
	// Sub-selects resolve unit/category to NULL when the given value isn't a
	// valid master id, so free-text input never trips the foreign keys.
	_, err := r.db.ExecContext(ctx, `
		INSERT INTO "part_master"
			("code", "bar_code", "name", "name_th", "unit_id", "category_id", "price", "cost", "min_price", "details", "is_active")
		VALUES (
			$1, $2, $3, $4,
			(SELECT "id" FROM "unit_master" WHERE "id" = $5),
			(SELECT "id" FROM "category_master" WHERE "id" = $6),
			$7, $8, $9, $10, $11
		)
	`, p.Code, p.BarCode, p.Name, p.NameTH, p.UnitID, p.CategoryID,
		p.Price, p.Cost, p.MinPrice, p.Details, p.IsActive)
	return err
}

func (r *partRepositoryPG) GenerateNextPartCode(ctx context.Context) (string, error) {
	var next int
	err := r.db.QueryRowContext(ctx, `
		SELECT COALESCE(MAX(CAST(SUBSTRING("code" FROM 2) AS INTEGER)), 0) + 1
		FROM "part_master"
		WHERE "code" ~ '^P[0-9]+$'
	`).Scan(&next)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("P%04d", next), nil
}

func (r *partRepositoryPG) UpdatePart(ctx context.Context, code string, p PartInput) error {
	res, err := r.db.ExecContext(ctx, `
		UPDATE "part_master" SET
			"bar_code" = $2,
			"name" = $3,
			"name_th" = $4,
			"unit_id" = (SELECT "id" FROM "unit_master" WHERE "id" = $5),
			"price" = $6,
			"cost" = $7,
			"min_price" = $8
		WHERE "code" = $1
	`, code, p.BarCode, p.Name, p.NameTH, p.UnitID, p.Price, p.Cost, p.MinPrice)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrNotFound
	}
	return nil
}

func (r *partRepositoryPG) DeletePart(ctx context.Context, code string) (string, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return "", err
	}
	defer func() { _ = tx.Rollback() }()

	var exists, referenced bool
	err = tx.QueryRowContext(ctx, `
		SELECT
			EXISTS(SELECT 1 FROM "part_master" WHERE "code" = $1),
			EXISTS(SELECT 1 FROM "bill_item_detail" WHERE "part_code" = $1)
			OR EXISTS(SELECT 1 FROM "inventory_transfer_item" WHERE "part_code" = $1)
			OR EXISTS(SELECT 1 FROM "purchase_order_item" WHERE "part_code" = $1)
			OR EXISTS(SELECT 1 FROM "stock_count_item" WHERE "part_code" = $1)
	`, code).Scan(&exists, &referenced)
	if err != nil {
		return "", err
	}
	if !exists {
		return "", ErrNotFound
	}

	mode := "deleted"
	if referenced {
		mode = "archived"
		if _, err := tx.ExecContext(ctx, `
			UPDATE "part_master"
			SET "is_active" = false
			WHERE "code" = $1
		`, code); err != nil {
			return "", err
		}
		if _, err := tx.ExecContext(ctx, `
			UPDATE "address_master"
			SET "is_active" = false
			WHERE "part_code" = $1
		`, code); err != nil {
			return "", err
		}
	} else {
		if _, err := tx.ExecContext(ctx, `
			DELETE FROM "address_master" WHERE "part_code" = $1
		`, code); err != nil {
			return "", err
		}
		if _, err := tx.ExecContext(ctx, `
			DELETE FROM "part_master" WHERE "code" = $1
		`, code); err != nil {
			return "", err
		}
	}

	if err := tx.Commit(); err != nil {
		return "", err
	}
	return mode, nil
}

func (r *partRepositoryPG) GetAddressesByPartCodes(ctx context.Context, codes []string, branchID *string) (map[string][]PartAddress, error) {
	result := make(map[string][]PartAddress, len(codes))
	if len(codes) == 0 {
		return result, nil
	}

	var rows *sql.Rows
	var err error
	if branchID != nil && *branchID != "" {
		rows, err = r.db.QueryContext(ctx, `
			SELECT
				a.code,
				a.part_code,
				a.store_id,
				s.label,
				s.label_th,
				a.shelf,
				a.qty,
				a.rop,
				COALESCE(a.remarks, ''),
				COALESCE(bs.is_default, false) as is_default
			FROM "address_master" a
			JOIN "store_master" s ON s.id = a.store_id
			JOIN "branch_store" bs ON bs.store_id = s.id AND bs.branch_id = $2
			WHERE a.part_code = ANY($1) AND a.is_active = true
			ORDER BY a.part_code, bs.is_default DESC, a.code
		`, pq.Array(codes), *branchID)
	} else {
		rows, err = r.db.QueryContext(ctx, `
			SELECT
				a.code,
				a.part_code,
				a.store_id,
				s.label,
				s.label_th,
				a.shelf,
				a.qty,
				a.rop,
				COALESCE(a.remarks, ''),
				false as is_default
			FROM "address_master" a
			JOIN "store_master" s ON s.id = a.store_id
			WHERE a.part_code = ANY($1) AND a.is_active = true
			ORDER BY a.part_code, a.code
		`, pq.Array(codes))
	}
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var a PartAddress
		if err := rows.Scan(
			&a.Code,
			&a.PartCode,
			&a.StoreID,
			&a.StoreLabel,
			&a.StoreLabelTH,
			&a.Shelf,
			&a.Qty,
			&a.Rop,
			&a.Remarks,
			&a.IsDefault,
		); err != nil {
			return nil, err
		}
		result[a.PartCode] = append(result[a.PartCode], a)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	return result, nil
}

func (r *partRepositoryPG) GetPartByBarcode(ctx context.Context, barcode string, branchID string) (*PartDetail, []PartAddress, error) {
	if strings.TrimSpace(branchID) == "" {
		var partCode string
		err := r.db.QueryRowContext(ctx, `
			SELECT "code"
			FROM "part_master"
			WHERE "bar_code" = $1
		`, barcode).Scan(&partCode)
		if err != nil {
			if err == sql.ErrNoRows {
				return nil, nil, ErrNotFound
			}
			return nil, nil, err
		}
		return r.GetPartDetail(ctx, partCode, nil)
	}

	query := `
		SELECT
			p.code,
			p.bar_code,
			COALESCE(p.category_id, ''),
			COALESCE(c.label, ''),
			COALESCE(c.label_th, ''),
			COALESCE(p.unit_id, ''),
			COALESCE(u.label, ''),
			COALESCE(u.label_th, ''),
			p.name,
			COALESCE(p.name_th, ''),
			COALESCE(p.receipt_name, ''),
			COALESCE(p.details, ''),
			p.cost,
			p.price,
			p.min_price,
			COALESCE(p.image, ''),
			COALESCE(p.is_active, false),
			COALESCE(SUM(CASE WHEN bs.branch_id = $2 THEN a.qty ELSE 0 END), 0) AS total_stock
		FROM "part_master" p
		LEFT JOIN "category_master" c ON c.id = p.category_id
		LEFT JOIN "unit_master" u ON u.id = p.unit_id
		LEFT JOIN "address_master" a ON a.part_code = p.code AND a.is_active = true
		LEFT JOIN "store_master" s ON s.id = a.store_id
		LEFT JOIN "branch_store" bs ON bs.store_id = s.id AND bs.branch_id = $2
		WHERE p.bar_code = $1
		GROUP BY
			p.code, p.bar_code, p.category_id, c.label, c.label_th,
			p.unit_id, u.label, u.label_th,
			p.name, p.name_th, p.receipt_name, p.details, p.cost, p.price, p.min_price, p.image, p.is_active
	`
	row := r.db.QueryRowContext(ctx, query, barcode, branchID)

	var d PartDetail
	if err := row.Scan(
		&d.Code,
		&d.BarCode,
		&d.CategoryID,
		&d.CategoryLabel,
		&d.CategoryLabelTH,
		&d.UnitID,
		&d.UnitLabel,
		&d.UnitLabelTH,
		&d.Name,
		&d.NameTH,
		&d.ReceiptName,
		&d.Details,
		&d.Cost,
		&d.Price,
		&d.MinPrice,
		&d.Image,
		&d.IsActive,
		&d.TotalStock,
	); err != nil {
		if err == sql.ErrNoRows {
			return nil, nil, ErrNotFound
		}
		return nil, nil, err
	}

	rows, err := r.db.QueryContext(ctx, `
		SELECT
			a.code,
			a.part_code,
			a.store_id,
			s.label,
			s.label_th,
			a.shelf,
			a.qty,
			a.rop,
			COALESCE(a.remarks, ''),
			COALESCE(bs.is_default, false) as is_default
		FROM "address_master" a
		JOIN "store_master" s ON s.id = a.store_id
		JOIN "branch_store" bs ON bs.store_id = s.id AND bs.branch_id = $2
		WHERE a.part_code = $1 AND a.is_active = true
		ORDER BY bs.is_default DESC, a.code
	`, d.Code, branchID)
	if err != nil {
		return &d, nil, err
	}
	defer rows.Close()

	var addrs []PartAddress
	for rows.Next() {
		var a PartAddress
		if err := rows.Scan(
			&a.Code,
			&a.PartCode,
			&a.StoreID,
			&a.StoreLabel,
			&a.StoreLabelTH,
			&a.Shelf,
			&a.Qty,
			&a.Rop,
			&a.Remarks,
			&a.IsDefault,
		); err != nil {
			return &d, nil, err
		}
		addrs = append(addrs, a)
	}
	if err := rows.Err(); err != nil {
		return &d, nil, err
	}

	return &d, addrs, nil
}

func (r *partRepositoryPG) CheckPartExistsInBranch(ctx context.Context, partCode, branchID string) (bool, error) {
	var exists bool
	err := r.db.QueryRowContext(ctx, `
		SELECT EXISTS(
			SELECT 1
			FROM "address_master" a
			JOIN "store_master" s ON s.id = a.store_id
			JOIN "branch_store" bs ON bs.store_id = s.id AND bs.branch_id = $2
			WHERE a.part_code = $1 AND a.is_active = true
		)
	`, partCode, branchID).Scan(&exists)
	if err != nil {
		return false, err
	}
	return exists, nil
}

func (r *partRepositoryPG) CountParts(ctx context.Context, query string, categoryID *string, isActive *bool, branchID, storeID *string, saleableOnly bool) (int, error) {
	whereClauses := []string{}
	args := []interface{}{}
	argIndex := 1

	if query != "" {
		searchPattern := "%" + query + "%"
		partSearch := fmt.Sprintf(`(p.code ILIKE $%d OR p.bar_code ILIKE $%d OR p.name ILIKE $%d OR p.name_th ILIKE $%d OR p.receipt_name ILIKE $%d)`,
			argIndex, argIndex, argIndex, argIndex, argIndex)
		categorySearch := fmt.Sprintf(`(c.label ILIKE $%d OR c.label_th ILIKE $%d)`, argIndex, argIndex)
		addressSearch := fmt.Sprintf(`EXISTS(
			SELECT 1 FROM "address_master" a_search
			JOIN "store_master" s_search ON s_search.id = a_search.store_id
			WHERE a_search.part_code = p.code
				AND a_search.is_active = true
				AND (a_search.code ILIKE $%d OR a_search.shelf ILIKE $%d OR a_search.remarks ILIKE $%d
					OR s_search.label ILIKE $%d OR s_search.label_th ILIKE $%d))`,
			argIndex, argIndex, argIndex, argIndex, argIndex)
		whereClauses = append(whereClauses, fmt.Sprintf(`(%s OR %s OR %s)`, partSearch, categorySearch, addressSearch))
		args = append(args, searchPattern)
		argIndex++
	}
	if categoryID != nil && *categoryID != "" {
		whereClauses = append(whereClauses, fmt.Sprintf("p.category_id = $%d", argIndex))
		args = append(args, *categoryID)
		argIndex++
	}
	// Store (คลังสินค้า) filter — part must have an address in that store.
	if storeID != nil && *storeID != "" {
		stockClause := ""
		if saleableOnly {
			stockClause = " AND a_st.qty > 0"
		}
		whereClauses = append(whereClauses, fmt.Sprintf(`EXISTS(
			SELECT 1 FROM "address_master" a_st
			WHERE a_st.part_code = p.code AND a_st.is_active = true AND a_st.store_id = $%d%s)`, argIndex, stockClause))
		args = append(args, *storeID)
		argIndex++
	}
	if isActive != nil {
		whereClauses = append(whereClauses, fmt.Sprintf("COALESCE(p.is_active, false) = $%d", argIndex))
		args = append(args, *isActive)
		argIndex++
	}
	if branchID != nil && *branchID != "" {
		whereClauses = append(whereClauses, fmt.Sprintf(`EXISTS(
			SELECT 1 FROM "address_master" a2
			JOIN "store_master" s2 ON s2.id = a2.store_id
			JOIN "branch_store" bs2 ON bs2.store_id = s2.id AND bs2.branch_id = $%d
			WHERE a2.part_code = p.code AND a2.is_active = true)`, argIndex))
		args = append(args, *branchID)
		argIndex++
	}

	whereSQL := ""
	if len(whereClauses) > 0 {
		whereSQL = "WHERE " + strings.Join(whereClauses, " AND ")
	}
	q := `SELECT COUNT(DISTINCT p.code) FROM "part_master" p
		LEFT JOIN "category_master" c ON c.id = p.category_id ` + whereSQL

	var n int
	if err := r.db.QueryRowContext(ctx, q, args...).Scan(&n); err != nil {
		return 0, err
	}
	return n, nil
}

func (r *partRepositoryPG) SearchParts(ctx context.Context, query string, categoryID *string, isActive *bool, branchID, storeID *string, saleableOnly bool, limit, offset int) ([]PartDetail, error) {
	if limit <= 0 {
		limit = config.DefaultLimit
	}
	if offset < 0 {
		offset = config.DefaultOffset
	}
	if limit > config.MaxLimit {
		limit = config.MaxLimit
	}

	// Build WHERE clause dynamically
	whereClauses := []string{}
	args := []interface{}{}
	argIndex := 1

	// Universal search query - searches across all part-related fields:
	// part code, barcode, part name, name_th, category name, category name_th,
	// store address code, store address (shelf, remarks), store label, store label_th
	if query != "" {
		searchPattern := "%" + query + "%"
		// Search in part fields
		partSearch := fmt.Sprintf(`(p.code ILIKE $%d OR p.bar_code ILIKE $%d OR p.name ILIKE $%d OR p.name_th ILIKE $%d OR p.receipt_name ILIKE $%d)`,
			argIndex, argIndex, argIndex, argIndex, argIndex)

		// Search in category fields
		categorySearch := fmt.Sprintf(`(c.label ILIKE $%d OR c.label_th ILIKE $%d)`, argIndex, argIndex)

		// Search in store address fields (code, shelf, remarks, store label, store label_th)
		// Use EXISTS to check if any address/store matches
		addressSearch := fmt.Sprintf(`EXISTS(
			SELECT 1
			FROM "address_master" a_search
			JOIN "store_master" s_search ON s_search.id = a_search.store_id
			WHERE a_search.part_code = p.code
				AND a_search.is_active = true
				AND (a_search.code ILIKE $%d OR a_search.shelf ILIKE $%d OR a_search.remarks ILIKE $%d 
					OR s_search.label ILIKE $%d OR s_search.label_th ILIKE $%d)
		)`, argIndex, argIndex, argIndex, argIndex, argIndex)

		whereClauses = append(whereClauses, fmt.Sprintf(`(%s OR %s OR %s)`, partSearch, categorySearch, addressSearch))
		args = append(args, searchPattern)
		argIndex++
	}

	// Category filter
	if categoryID != nil && *categoryID != "" {
		whereClauses = append(whereClauses, fmt.Sprintf("p.category_id = $%d", argIndex))
		args = append(args, *categoryID)
		argIndex++
	}
	// Store (คลังสินค้า) filter — part must have an address in that store.
	if storeID != nil && *storeID != "" {
		stockClause := ""
		if saleableOnly {
			stockClause = " AND a_st.qty > 0"
		}
		whereClauses = append(whereClauses, fmt.Sprintf(`EXISTS(
			SELECT 1 FROM "address_master" a_st
			WHERE a_st.part_code = p.code AND a_st.is_active = true AND a_st.store_id = $%d%s)`, argIndex, stockClause))
		args = append(args, *storeID)
		argIndex++
	}

	// Active filter
	if isActive != nil {
		whereClauses = append(whereClauses, fmt.Sprintf("COALESCE(p.is_active, false) = $%d", argIndex))
		args = append(args, *isActive)
		argIndex++
	}

	whereSQL := ""
	if len(whereClauses) > 0 {
		whereSQL = "WHERE " + strings.Join(whereClauses, " AND ")
	}

	// Build query - different structure based on branch filtering
	var sqlQuery string
	if branchID != nil && *branchID != "" {
		// Branch filter - only show parts that exist in branch's stores and filter stock
		// Use same parameter for both EXISTS check and stock calculation
		branchArgIndex := argIndex
		args = append(args, *branchID)
		argIndex++

		branchFilter := fmt.Sprintf(`
			EXISTS(
				SELECT 1
				FROM "address_master" a2
				JOIN "store_master" s2 ON s2.id = a2.store_id
				JOIN "branch_store" bs2 ON bs2.store_id = s2.id AND bs2.branch_id = $%d
				WHERE a2.part_code = p.code AND a2.is_active = true
			)
		`, branchArgIndex)

		if whereSQL != "" {
			whereSQL += " AND " + branchFilter
		} else {
			whereSQL = "WHERE " + branchFilter
		}

		// Limit and offset
		limitArgIndex := argIndex
		offsetArgIndex := argIndex + 1
		args = append(args, limit, offset)

		sqlQuery = fmt.Sprintf(`
			SELECT
				p.code,
				p.bar_code,
				COALESCE(p.category_id, ''),
				COALESCE(c.label, ''),
				COALESCE(c.label_th, ''),
				COALESCE(p.unit_id, ''),
				COALESCE(u.label, ''),
				COALESCE(u.label_th, ''),
				p.name,
				COALESCE(p.name_th, ''),
				COALESCE(p.receipt_name, ''),
				COALESCE(p.details, ''),
				p.cost,
				p.price,
				p.min_price,
				COALESCE(p.image, ''),
				COALESCE(p.is_active, false),
				COALESCE(SUM(CASE WHEN bs.branch_id = $%d THEN a.qty ELSE 0 END), 0) AS total_stock
			FROM "part_master" p
			LEFT JOIN "category_master" c ON c.id = p.category_id
			LEFT JOIN "unit_master" u ON u.id = p.unit_id
			LEFT JOIN "address_master" a ON a.part_code = p.code AND a.is_active = true
			LEFT JOIN "store_master" s ON s.id = a.store_id
			LEFT JOIN "branch_store" bs ON bs.store_id = s.id AND bs.branch_id = $%d
			%s
			GROUP BY
				p.code, p.bar_code, p.category_id, c.label, c.label_th,
				p.unit_id, u.label, u.label_th,
				p.name, p.name_th, p.receipt_name, p.details, p.cost, p.price, p.min_price, p.image, p.is_active
			ORDER BY p.code
			LIMIT $%d OFFSET $%d
		`, branchArgIndex, branchArgIndex, whereSQL, limitArgIndex, offsetArgIndex)
	} else {
		// No branch filter - show all parts
		limitArgIndex := argIndex
		offsetArgIndex := argIndex + 1
		args = append(args, limit, offset)

		sqlQuery = fmt.Sprintf(`
			SELECT
				p.code,
				p.bar_code,
				COALESCE(p.category_id, ''),
				COALESCE(c.label, ''),
				COALESCE(c.label_th, ''),
				COALESCE(p.unit_id, ''),
				COALESCE(u.label, ''),
				COALESCE(u.label_th, ''),
				p.name,
				COALESCE(p.name_th, ''),
				COALESCE(p.receipt_name, ''),
				COALESCE(p.details, ''),
				p.cost,
				p.price,
				p.min_price,
				COALESCE(p.image, ''),
				COALESCE(p.is_active, false),
				COALESCE(SUM(a.qty), 0) AS total_stock
			FROM "part_master" p
			LEFT JOIN "category_master" c ON c.id = p.category_id
			LEFT JOIN "unit_master" u ON u.id = p.unit_id
			LEFT JOIN "address_master" a ON a.part_code = p.code AND a.is_active = true
			%s
			GROUP BY
				p.code, p.bar_code, p.category_id, c.label, c.label_th,
				p.unit_id, u.label, u.label_th,
				p.name, p.name_th, p.receipt_name, p.details, p.cost, p.price, p.min_price, p.image, p.is_active
			ORDER BY p.code
			LIMIT $%d OFFSET $%d
		`, whereSQL, limitArgIndex, offsetArgIndex)
	}

	rows, err := r.db.QueryContext(ctx, sqlQuery, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var parts []PartDetail
	for rows.Next() {
		var d PartDetail
		if err := rows.Scan(
			&d.Code,
			&d.BarCode,
			&d.CategoryID,
			&d.CategoryLabel,
			&d.CategoryLabelTH,
			&d.UnitID,
			&d.UnitLabel,
			&d.UnitLabelTH,
			&d.Name,
			&d.NameTH,
			&d.ReceiptName,
			&d.Details,
			&d.Cost,
			&d.Price,
			&d.MinPrice,
			&d.Image,
			&d.IsActive,
			&d.TotalStock,
		); err != nil {
			return nil, err
		}
		parts = append(parts, d)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	return parts, nil
}

// ImportParts writes a whole spreadsheet or none of it.
//
// A row is matched to an existing product by its code, or — when the code cell
// is blank — by an exact name. Name matching is unambiguous because the
// warehouse holds one product per name, so a name that is already in the
// catalog can only mean that product. A matched row is a restock: it adds to
// the warehouse quantity and refreshes the figures a restock can legitimately
// change. Identity — code, name, barcode, unit — is left alone, so a
// spreadsheet can never quietly rename a product; that has to go through the
// edit form.
//
// Rows that land on the same product are merged, quantities summed, because a
// list typed by hand repeats an item without meaning to order it twice.
//
// Every check happens inside the transaction, so two people importing
// overlapping files at the same time cannot both succeed.
func (r *partRepositoryPG) ImportParts(ctx context.Context, rows []PartImportRow, batch PartImportBatch) (PartImportResult, error) {
	result := PartImportResult{
		Codes:        make([]string, 0, len(rows)),
		UpdatedCodes: make([]string, 0),
	}
	if len(rows) == 0 {
		return result, nil
	}

	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return result, err
	}
	defer func() { _ = tx.Rollback() }()

	// Serialise imports against each other so the lookups below and the
	// running-code cursor cannot be invalidated by a concurrent import.
	if _, err := tx.ExecContext(ctx, `SELECT pg_advisory_xact_lock(hashtext('parts-import'))`); err != nil {
		return result, err
	}

	givenCodes := make([]string, 0, len(rows))
	lookupNames := make([]string, 0, len(rows))
	for _, row := range rows {
		if row.Code != "" {
			givenCodes = append(givenCodes, strings.ToUpper(row.Code))
			continue
		}
		lookupNames = append(lookupNames, importNameKey(row.Name))
	}

	// Map what the sheet supplied to the codes as the catalog spells them, so a
	// lowercase entry still updates the right product.
	byCode, err := r.lookupCodes(ctx, tx, `
		SELECT upper("code"), "code" FROM "part_master" WHERE upper("code") = ANY($1)
	`, givenCodes)
	if err != nil {
		return result, err
	}
	byName, err := r.lookupCodes(ctx, tx, `
		SELECT lower(btrim("name")), "code" FROM "part_master"
		WHERE lower(btrim("name")) = ANY($1)
	`, lookupNames)
	if err != nil {
		return result, err
	}

	// A row that names a code the catalog does not have creates a product, so
	// its name still has to be free.
	takenNames, err := r.lookupCodes(ctx, tx, `
		SELECT lower(btrim("name")), "code" FROM "part_master"
		WHERE lower(btrim("name")) = ANY($1)
	`, newCodeRowNames(rows, byCode))
	if err != nil {
		return result, err
	}

	updates := newImportBatch()
	creates := newImportBatch()
	for _, row := range rows {
		if row.Code != "" {
			if canonical, found := byCode[strings.ToUpper(row.Code)]; found {
				row.Code = canonical
				updates.add(canonical, row)
				continue
			}
			if owner, taken := takenNames[importNameKey(row.Name)]; taken {
				result.Conflicts = append(result.Conflicts, PartImportConflict{
					SheetRow: row.SheetRow,
					Column:   "ชื่อสินค้า",
					Message: fmt.Sprintf(
						"ชื่อนี้เป็นของสินค้า %s อยู่แล้ว ถ้าจะแก้ของเดิมให้ใส่รหัส %s หรือเว้นรหัสว่าง",
						owner, owner),
				})
				continue
			}
			creates.add(strings.ToUpper(row.Code), row)
			continue
		}
		if canonical, found := byName[importNameKey(row.Name)]; found {
			row.Code = canonical
			updates.add(canonical, row)
			continue
		}
		creates.add("name:"+importNameKey(row.Name), row)
	}
	if len(result.Conflicts) > 0 {
		return result, nil
	}

	// One running-code cursor for the batch; taking it inside the transaction
	// keeps the generated codes contiguous.
	var nextCode int
	if err := tx.QueryRowContext(ctx, `
		SELECT COALESCE(MAX(CAST(SUBSTRING("code" FROM 2) AS INTEGER)), 0) + 1
		FROM "part_master"
		WHERE "code" ~ '^P[0-9]+$'
	`).Scan(&nextCode); err != nil {
		return result, err
	}

	takenCodes := map[string]bool{}
	for _, canonical := range byCode {
		takenCodes[strings.ToUpper(canonical)] = true
	}
	for at := range creates.rows {
		if creates.rows[at].Code != "" {
			takenCodes[strings.ToUpper(creates.rows[at].Code)] = true
			continue
		}
		code := fmt.Sprintf("P%04d", nextCode)
		nextCode++
		// Skip over codes an earlier manual entry already claimed.
		for takenCodes[strings.ToUpper(code)] {
			code = fmt.Sprintf("P%04d", nextCode)
			nextCode++
		}
		takenCodes[strings.ToUpper(code)] = true
		creates.rows[at].Code = code
	}

	// Warehouse quantities as they stand before anything is written, so each
	// history line can show what it moved rather than just where it landed.
	touched := make([]string, 0, len(creates.rows)+len(updates.rows))
	for _, row := range creates.rows {
		touched = append(touched, row.Code)
	}
	for _, row := range updates.rows {
		touched = append(touched, row.Code)
	}
	qtyBefore, err := r.warehouseQuantities(ctx, tx, touched)
	if err != nil {
		return PartImportResult{}, err
	}

	// The writes below are set-based on purpose. A row-at-a-time loop costs
	// three round trips per product, which against a database in another region
	// puts a thousand-row import into the minutes — long enough that the client
	// gives up mid-flight and the user sees a network error rather than a
	// result. As batches the whole import is a handful of statements.
	if err := r.insertImportedParts(ctx, tx, creates.rows); err != nil {
		return PartImportResult{}, err
	}
	if err := r.updateImportedParts(ctx, tx, updates.rows); err != nil {
		return PartImportResult{}, err
	}
	// Existing warehouse rows are topped up first; whatever still has no row in
	// the warehouse is inserted after, so nothing is counted twice.
	if err := r.addImportedStock(ctx, tx, updates.rows); err != nil {
		return PartImportResult{}, err
	}
	if err := r.insertImportedStock(ctx, tx, append(append([]PartImportRow{}, creates.rows...), updates.rows...)); err != nil {
		return PartImportResult{}, err
	}

	for _, row := range creates.rows {
		result.Codes = append(result.Codes, row.Code)
	}
	for _, row := range updates.rows {
		result.UpdatedCodes = append(result.UpdatedCodes, row.Code)
	}

	batchID, err := r.recordImportBatch(ctx, tx, batch, creates.rows, updates.rows, qtyBefore)
	if err != nil {
		return PartImportResult{}, err
	}

	if err := tx.Commit(); err != nil {
		return PartImportResult{}, err
	}
	result.BatchID = batchID
	result.Created = len(result.Codes)
	result.Updated = len(result.UpdatedCodes)
	return result, nil
}

// warehouseQuantities reads the current warehouse quantity for the given
// products. Anything without a row yet is simply absent, which reads as zero.
func (r *partRepositoryPG) warehouseQuantities(ctx context.Context, tx *sql.Tx, codes []string) (map[string]int, error) {
	quantities := map[string]int{}
	if len(codes) == 0 {
		return quantities, nil
	}
	rows, err := tx.QueryContext(ctx, `
		SELECT "part_code", "qty" FROM "address_master"
		 WHERE "store_id" = $1 AND "part_code" = ANY($2)
	`, ImportWarehouseStoreID, pq.Array(codes))
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var code string
		var qty int
		if err := rows.Scan(&code, &qty); err != nil {
			return nil, err
		}
		quantities[code] = qty
	}
	return quantities, rows.Err()
}

// recordImportBatch writes the history entry for this upload. It runs inside
// the import transaction, so an import that fails leaves no trace and one that
// succeeds is always accounted for.
func (r *partRepositoryPG) recordImportBatch(
	ctx context.Context, tx *sql.Tx, batch PartImportBatch,
	creates, updates []PartImportRow, qtyBefore map[string]int,
) (string, error) {
	if len(creates) == 0 && len(updates) == 0 {
		return "", nil
	}
	// Document ids follow the house convention: prefix + Thailand date + a
	// counter taken atomically, never MAX()+1.
	// UTC+7, the same convention as bill and transfer ids.
	dateKey := time.Now().UTC().Add(7 * time.Hour).Format("20060102")
	var sequence int
	if err := tx.QueryRowContext(ctx, `
		INSERT INTO "counter"("key", "value") VALUES ($1, 1)
		ON CONFLICT ("key") DO UPDATE SET "value" = "counter"."value" + 1
		RETURNING "value"
	`, "imp_"+dateKey).Scan(&sequence); err != nil {
		return "", err
	}
	batchID := fmt.Sprintf("IMP%s%06d", dateKey, sequence)

	total := 0
	for _, row := range append(append([]PartImportRow{}, creates...), updates...) {
		total += row.Qty
	}
	if _, err := tx.ExecContext(ctx, `
		INSERT INTO "parts_import_batch"
			("id", "file_hash", "file_name", "file_size", "store_id", "created_by",
			 "created_count", "updated_count", "total_qty")
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
	`, batchID, batch.FileHash, batch.FileName, batch.FileSize, ImportWarehouseStoreID,
		batch.UserID, len(creates), len(updates), total); err != nil {
		return "", err
	}

	codes := make([]string, 0, len(creates)+len(updates))
	actions := make([]string, 0, cap(codes))
	sheetRows := make([]int64, 0, cap(codes))
	quantities := make([]int64, 0, cap(codes))
	befores := make([]int64, 0, cap(codes))
	afters := make([]int64, 0, cap(codes))
	costs := make([]float64, 0, cap(codes))
	prices := make([]float64, 0, cap(codes))
	add := func(row PartImportRow, action string) {
		before := qtyBefore[row.Code]
		if action == "created" {
			before = 0
		}
		codes = append(codes, row.Code)
		actions = append(actions, action)
		sheetRows = append(sheetRows, int64(row.SheetRow))
		quantities = append(quantities, int64(row.Qty))
		befores = append(befores, int64(before))
		afters = append(afters, int64(before+row.Qty))
		costs = append(costs, row.Cost)
		prices = append(prices, row.Price)
	}
	for _, row := range creates {
		add(row, "created")
	}
	for _, row := range updates {
		add(row, "updated")
	}
	_, err := tx.ExecContext(ctx, `
		INSERT INTO "parts_import_batch_item"
			("batch_id", "part_code", "action", "sheet_row", "qty",
			 "qty_before", "qty_after", "cost", "price")
		SELECT $1, v.code, v.action, v.sheet_row, v.qty, v.qty_before, v.qty_after, v.cost, v.price
		  FROM unnest($2::text[], $3::text[], $4::int[], $5::int[],
		              $6::int[], $7::int[], $8::numeric[], $9::numeric[])
		       AS v(code, action, sheet_row, qty, qty_before, qty_after, cost, price)
	`, batchID, pq.Array(codes), pq.Array(actions), pq.Array(sheetRows), pq.Array(quantities),
		pq.Array(befores), pq.Array(afters), pq.Array(costs), pq.Array(prices))
	return batchID, err
}

// importNameKey matches the collation the name lookups use — lower(btrim(...))
// in SQL, so nothing more clever here or the two would disagree.
func importNameKey(name string) string {
	return strings.ToLower(strings.TrimSpace(name))
}

// newCodeRowNames collects the names of rows that supplied a code the catalog
// does not have. Those rows create a product, so their names must be free.
func newCodeRowNames(rows []PartImportRow, byCode map[string]string) []string {
	names := make([]string, 0, len(rows))
	for _, row := range rows {
		if row.Code == "" {
			continue
		}
		if _, found := byCode[strings.ToUpper(row.Code)]; found {
			continue
		}
		names = append(names, importNameKey(row.Name))
	}
	return names
}

// importBatch keeps rows in sheet order while folding repeats of the same
// product together. The first row wins on every field except the quantity,
// which accumulates: a hand-typed list repeats an item without meaning to order
// it twice, and the later line is a second delivery of the same thing.
type importBatch struct {
	rows  []PartImportRow
	index map[string]int
}

func newImportBatch() *importBatch {
	return &importBatch{index: map[string]int{}}
}

func (b *importBatch) add(key string, row PartImportRow) {
	if at, seen := b.index[key]; seen {
		b.rows[at].Qty += row.Qty
		return
	}
	b.index[key] = len(b.rows)
	b.rows = append(b.rows, row)
}

// The four statements the import writes with. Each takes parallel arrays and
// works on the whole batch at once.

func (r *partRepositoryPG) insertImportedParts(ctx context.Context, tx *sql.Tx, rows []PartImportRow) error {
	if len(rows) == 0 {
		return nil
	}
	codes := make([]string, len(rows))
	barCodes := make([]string, len(rows))
	names := make([]string, len(rows))
	units := make([]string, len(rows))
	details := make([]string, len(rows))
	costs := make([]float64, len(rows))
	prices := make([]float64, len(rows))
	minPrices := make([]float64, len(rows))
	for at, row := range rows {
		codes[at] = row.Code
		barCodes[at] = row.BarCode
		if barCodes[at] == "" {
			barCodes[at] = row.Code
		}
		names[at] = strings.TrimSpace(row.Name)
		units[at] = row.UnitID
		details[at] = row.Details
		costs[at] = row.Cost
		prices[at] = row.Price
		minPrices[at] = row.MinPrice
	}
	// A unit the master table does not know becomes NULL, the same as the
	// one-at-a-time create path, so free-text input never trips the foreign key.
	_, err := tx.ExecContext(ctx, `
		INSERT INTO "part_master"
			("code", "bar_code", "name", "name_th", "unit_id", "category_id",
			 "cost", "price", "min_price", "details", "is_active", "receipt_name")
		SELECT c.code, c.bar_code, c.name, c.name,
		       (SELECT u."id" FROM "unit_master" u WHERE u."id" = c.unit_id),
		       NULL, c.cost, c.price, c.min_price, c.details, true, ''
		  FROM unnest($1::text[], $2::text[], $3::text[], $4::text[], $5::text[],
		              $6::numeric[], $7::numeric[], $8::numeric[])
		       AS c(code, bar_code, name, unit_id, details, cost, price, min_price)
	`, pq.Array(codes), pq.Array(barCodes), pq.Array(names), pq.Array(units),
		pq.Array(details), pq.Array(costs), pq.Array(prices), pq.Array(minPrices))
	return err
}

// updateImportedParts refreshes what a restock may change. A blank details cell
// means "no change", so an import carrying only quantities never wipes text
// somebody typed in the product form. Identity is not in the SET list at all.
func (r *partRepositoryPG) updateImportedParts(ctx context.Context, tx *sql.Tx, rows []PartImportRow) error {
	if len(rows) == 0 {
		return nil
	}
	codes := make([]string, len(rows))
	details := make([]string, len(rows))
	costs := make([]float64, len(rows))
	prices := make([]float64, len(rows))
	minPrices := make([]float64, len(rows))
	for at, row := range rows {
		codes[at] = row.Code
		details[at] = row.Details
		costs[at] = row.Cost
		prices[at] = row.Price
		minPrices[at] = row.MinPrice
	}
	_, err := tx.ExecContext(ctx, `
		UPDATE "part_master" p SET
			"cost" = u.cost, "price" = u.price, "min_price" = u.min_price,
			"details" = CASE WHEN u.details = '' THEN p."details" ELSE u.details END,
			"is_active" = true
		  FROM unnest($1::text[], $2::numeric[], $3::numeric[], $4::numeric[], $5::text[])
		       AS u(code, cost, price, min_price, details)
		 WHERE p."code" = u.code
	`, pq.Array(codes), pq.Array(costs), pq.Array(prices), pq.Array(minPrices), pq.Array(details))
	return err
}

// addImportedStock adds each row's quantity to what the warehouse already holds
// — the column is what was received, not a new stock level, so importing the
// same delivery note twice is visible as double stock rather than silently
// overwriting a count somebody took. Products with no warehouse row yet are
// left to insertImportedStock.
func (r *partRepositoryPG) addImportedStock(ctx context.Context, tx *sql.Tx, rows []PartImportRow) error {
	if len(rows) == 0 {
		return nil
	}
	codes, quantities, shelves := stockArrays(rows)
	// DISTINCT ON picks the same row the single-product path would: the active
	// one, then the lowest code.
	_, err := tx.ExecContext(ctx, `
		WITH incoming AS (
			SELECT * FROM unnest($1::text[], $2::int[], $3::text[])
			       AS t(part_code, qty, shelf)
		), target AS (
			SELECT DISTINCT ON (a."part_code") a."part_code", a."code"
			  FROM "address_master" a
			  JOIN incoming i ON i.part_code = a."part_code"
			 WHERE a."store_id" = $4
			 ORDER BY a."part_code", a."is_active" DESC, a."code"
		)
		UPDATE "address_master" a SET
			"qty" = a."qty" + i.qty,
			"shelf" = CASE WHEN i.shelf = '' THEN a."shelf" ELSE i.shelf END,
			"is_active" = true
		  FROM target t
		  JOIN incoming i ON i.part_code = t."part_code"
		 WHERE a."code" = t."code"
	`, pq.Array(codes), pq.Array(quantities), pq.Array(shelves), ImportWarehouseStoreID)
	return err
}

// insertImportedStock gives a warehouse row to every imported product that does
// not have one yet — new products, and the occasional existing product that
// only ever lived on a vehicle. Run it after addImportedStock so a product that
// already had a row is not counted twice.
func (r *partRepositoryPG) insertImportedStock(ctx context.Context, tx *sql.Tx, rows []PartImportRow) error {
	if len(rows) == 0 {
		return nil
	}
	codes, quantities, shelves := stockArrays(rows)
	_, err := tx.ExecContext(ctx, `
		INSERT INTO "address_master"
			("code", "part_code", "store_id", "shelf", "qty", "rop", "remarks", "is_active")
		SELECT 'ADDR-' || i.part_code || '-' || $4, i.part_code, $4, i.shelf, i.qty, 0, '', true
		  FROM unnest($1::text[], $2::int[], $3::text[]) AS i(part_code, qty, shelf)
		 WHERE NOT EXISTS (
			SELECT 1 FROM "address_master" a
			 WHERE a."part_code" = i.part_code AND a."store_id" = $4
		 )
	`, pq.Array(codes), pq.Array(quantities), pq.Array(shelves), ImportWarehouseStoreID)
	return err
}

func stockArrays(rows []PartImportRow) (codes []string, quantities []int64, shelves []string) {
	codes = make([]string, len(rows))
	quantities = make([]int64, len(rows))
	shelves = make([]string, len(rows))
	for at, row := range rows {
		codes[at] = row.Code
		quantities[at] = int64(row.Qty)
		shelves[at] = row.Shelf
	}
	return codes, quantities, shelves
}

// lookupCodes runs a "SELECT <key>, code FROM part_master WHERE <key> = ANY($1)"
// and returns the mapping, so callers can resolve a sheet's codes or names to
// the product they name.
func (r *partRepositoryPG) lookupCodes(ctx context.Context, tx *sql.Tx, query string, keys []string) (map[string]string, error) {
	found := map[string]string{}
	if len(keys) == 0 {
		return found, nil
	}
	rows, err := tx.QueryContext(ctx, query, pq.Array(keys))
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var key, code string
		if err := rows.Scan(&key, &code); err != nil {
			return nil, err
		}
		found[key] = code
	}
	return found, rows.Err()
}

// ImportWarehouseStoreID is the only store an imported product may enter — the
// catalog is modelled as a single warehouse that the vehicles draw from.
const ImportWarehouseStoreID = "main"

// The import history read side.

const importSummarySelect = `
	SELECT b."id", b."file_hash", b."file_name", b."file_size", b."store_id",
	       b."created_by", COALESCE(u."name", u."username", ''), b."created_at",
	       b."created_count", b."updated_count", b."total_qty"
	  FROM "parts_import_batch" b
	  LEFT JOIN "user" u ON u."id" = b."created_by"`

func scanImportSummaries(rows *sql.Rows) ([]PartImportSummary, error) {
	out := []PartImportSummary{}
	for rows.Next() {
		var s PartImportSummary
		if err := rows.Scan(&s.ID, &s.FileHash, &s.FileName, &s.FileSize, &s.StoreID,
			&s.CreatedBy, &s.CreatedByName, &s.CreatedAt,
			&s.Created, &s.Updated, &s.TotalQty); err != nil {
			return nil, err
		}
		out = append(out, s)
	}
	return out, rows.Err()
}

func (r *partRepositoryPG) FindImportsOfFile(ctx context.Context, fileHash string) ([]PartImportSummary, error) {
	if strings.TrimSpace(fileHash) == "" {
		return nil, nil
	}
	rows, err := r.db.QueryContext(ctx,
		importSummarySelect+` WHERE b."file_hash" = $1 ORDER BY b."created_at" DESC`, fileHash)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanImportSummaries(rows)
}

func (r *partRepositoryPG) ListImportBatches(ctx context.Context, limit, offset int) ([]PartImportSummary, int, error) {
	rows, err := r.db.QueryContext(ctx,
		importSummarySelect+` ORDER BY b."created_at" DESC LIMIT $1 OFFSET $2`, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	batches, err := scanImportSummaries(rows)
	if err != nil {
		return nil, 0, err
	}
	var total int
	if err := r.db.QueryRowContext(ctx, `SELECT count(*) FROM "parts_import_batch"`).Scan(&total); err != nil {
		return nil, 0, err
	}
	return batches, total, nil
}

func (r *partRepositoryPG) GetImportBatch(ctx context.Context, id string) (*PartImportSummary, []PartImportLine, error) {
	row := r.db.QueryRowContext(ctx, importSummarySelect+` WHERE b."id" = $1`, id)
	var s PartImportSummary
	if err := row.Scan(&s.ID, &s.FileHash, &s.FileName, &s.FileSize, &s.StoreID,
		&s.CreatedBy, &s.CreatedByName, &s.CreatedAt,
		&s.Created, &s.Updated, &s.TotalQty); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil, ErrNotFound
		}
		return nil, nil, err
	}

	rows, err := r.db.QueryContext(ctx, `
		SELECT i."part_code", COALESCE(p."name", ''), i."action", i."sheet_row",
		       i."qty", i."qty_before", i."qty_after", i."cost", i."price"
		  FROM "parts_import_batch_item" i
		  LEFT JOIN "part_master" p ON p."code" = i."part_code"
		 WHERE i."batch_id" = $1
		 ORDER BY i."sheet_row", i."part_code"
	`, id)
	if err != nil {
		return nil, nil, err
	}
	defer rows.Close()
	lines := []PartImportLine{}
	for rows.Next() {
		var l PartImportLine
		if err := rows.Scan(&l.PartCode, &l.PartName, &l.Action, &l.SheetRow,
			&l.Qty, &l.QtyBefore, &l.QtyAfter, &l.Cost, &l.Price); err != nil {
			return nil, nil, err
		}
		lines = append(lines, l)
	}
	return &s, lines, rows.Err()
}
