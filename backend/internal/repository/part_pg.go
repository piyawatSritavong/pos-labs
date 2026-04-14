package repository

import (
	"context"
	"database/sql"
	"fmt"
	"strings"

	"backend/internal/config"
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
				p.category_id,
				COALESCE(c.label, ''),
				COALESCE(c.label_th, ''),
				p.unit_id,
				COALESCE(u.label, ''),
				COALESCE(u.label_th, ''),
				p.name,
				COALESCE(p.name_th, ''),
				p.price,
				COALESCE(p.is_active, false),
				COALESCE((
					SELECT SUM(a2.qty)
					FROM "address_master" a2
					JOIN "branch_store" bs2 ON bs2.store_id = a2.store_id
					WHERE a2.part_code = p.code AND bs2.branch_id = $3
				), 0) AS total_stock
			FROM "part_master" p
			LEFT JOIN "category_master" c ON c.id = p.category_id
			LEFT JOIN "unit_master" u ON u.id = p.unit_id
			WHERE EXISTS (
				SELECT 1 FROM "address_master" a
				JOIN "branch_store" bs ON bs.store_id = a.store_id
				WHERE a.part_code = p.code AND bs.branch_id = $3
			)
			ORDER BY p.code
			LIMIT $1 OFFSET $2
		`, limit, offset, *branchID)
	} else {
		rows, err = r.db.QueryContext(ctx, `
			SELECT
				p.code,
				p.bar_code,
				p.category_id,
				COALESCE(c.label, ''),
				COALESCE(c.label_th, ''),
				p.unit_id,
				COALESCE(u.label, ''),
				COALESCE(u.label_th, ''),
				p.name,
				COALESCE(p.name_th, ''),
				p.price,
				COALESCE(p.is_active, false),
				COALESCE(SUM(a.qty), 0) AS total_stock
			FROM "part_master" p
			LEFT JOIN "category_master" c ON c.id = p.category_id
			LEFT JOIN "unit_master" u ON u.id = p.unit_id
			LEFT JOIN "address_master" a ON a.part_code = p.code
			GROUP BY
				p.code, p.bar_code, p.category_id, c.label, c.label_th,
				p.unit_id, u.label, u.label_th,
				p.name, p.name_th, p.price, p.is_active
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
			&s.Price,
			&s.IsActive,
			&s.TotalStock,
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
				p.category_id,
				COALESCE(c.label, ''),
				COALESCE(c.label_th, ''),
				p.unit_id,
				COALESCE(u.label, ''),
				COALESCE(u.label_th, ''),
				p.name,
				COALESCE(p.name_th, ''),
				COALESCE(p.details, ''),
				p.cost,
				p.price,
				COALESCE(p.image, ''),
				COALESCE(p.is_active, false),
				COALESCE(SUM(CASE WHEN bs.branch_id = $2 THEN a.qty ELSE 0 END), 0) AS total_stock
			FROM "part_master" p
			LEFT JOIN "category_master" c ON c.id = p.category_id
			LEFT JOIN "unit_master" u ON u.id = p.unit_id
			LEFT JOIN "address_master" a ON a.part_code = p.code
			LEFT JOIN "store_master" s ON s.id = a.store_id
			LEFT JOIN "branch_store" bs ON bs.store_id = s.id AND bs.branch_id = $2
			WHERE p.code = $1
			GROUP BY
				p.code, p.bar_code, p.category_id, c.label, c.label_th,
				p.unit_id, u.label, u.label_th,
				p.name, p.name_th, p.details, p.cost, p.price, p.image, p.is_active
		`
		args = []interface{}{code, *branchID}
	} else {
		query = `
			SELECT
				p.code,
				p.bar_code,
				p.category_id,
				COALESCE(c.label, ''),
				COALESCE(c.label_th, ''),
				p.unit_id,
				COALESCE(u.label, ''),
				COALESCE(u.label_th, ''),
				p.name,
				COALESCE(p.name_th, ''),
				COALESCE(p.details, ''),
				p.cost,
				p.price,
				COALESCE(p.image, ''),
				COALESCE(p.is_active, false),
				COALESCE(SUM(a.qty), 0) AS total_stock
			FROM "part_master" p
			LEFT JOIN "category_master" c ON c.id = p.category_id
			LEFT JOIN "unit_master" u ON u.id = p.unit_id
			LEFT JOIN "address_master" a ON a.part_code = p.code
			WHERE p.code = $1
			GROUP BY
				p.code, p.bar_code, p.category_id, c.label, c.label_th,
				p.unit_id, u.label, u.label_th,
				p.name, p.name_th, p.details, p.cost, p.price, p.image, p.is_active
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
		&d.Details,
		&d.Cost,
		&d.Price,
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
				a.min,
				a.max,
				a.rop,
				COALESCE(a.remarks, ''),
				COALESCE(bs.is_default, false) as is_default
			FROM "address_master" a
			JOIN "store_master" s ON s.id = a.store_id
			JOIN "branch_store" bs ON bs.store_id = s.id AND bs.branch_id = $2
			WHERE a.part_code = $1
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
				a.min,
				a.max,
				a.rop,
				COALESCE(a.remarks, ''),
				false as is_default
			FROM "address_master" a
			JOIN "store_master" s ON s.id = a.store_id
			WHERE a.part_code = $1
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
			&a.Min,
			&a.Max,
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

func (r *partRepositoryPG) GetPartByBarcode(ctx context.Context, barcode string, branchID string) (*PartDetail, []PartAddress, error) {
	// First get the part code from barcode
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

	// Then get the full part detail using the part code, filtered by branch
	return r.GetPartDetail(ctx, partCode, &branchID)
}

func (r *partRepositoryPG) CheckPartExistsInBranch(ctx context.Context, partCode, branchID string) (bool, error) {
	var exists bool
	err := r.db.QueryRowContext(ctx, `
		SELECT EXISTS(
			SELECT 1
			FROM "address_master" a
			JOIN "store_master" s ON s.id = a.store_id
			JOIN "branch_store" bs ON bs.store_id = s.id AND bs.branch_id = $2
			WHERE a.part_code = $1
		)
	`, partCode, branchID).Scan(&exists)
	if err != nil {
		return false, err
	}
	return exists, nil
}

func (r *partRepositoryPG) SearchParts(ctx context.Context, query string, categoryID *string, isActive *bool, branchID *string, limit, offset int) ([]PartDetail, error) {
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
		partSearch := fmt.Sprintf(`(p.code ILIKE $%d OR p.bar_code ILIKE $%d OR p.name ILIKE $%d OR p.name_th ILIKE $%d)`, 
			argIndex, argIndex, argIndex, argIndex)
		
		// Search in category fields
		categorySearch := fmt.Sprintf(`(c.label ILIKE $%d OR c.label_th ILIKE $%d)`, argIndex, argIndex)
		
		// Search in store address fields (code, shelf, remarks, store label, store label_th)
		// Use EXISTS to check if any address/store matches
		addressSearch := fmt.Sprintf(`EXISTS(
			SELECT 1
			FROM "address_master" a_search
			JOIN "store_master" s_search ON s_search.id = a_search.store_id
			WHERE a_search.part_code = p.code
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
				WHERE a2.part_code = p.code
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
				p.category_id,
				COALESCE(c.label, ''),
				COALESCE(c.label_th, ''),
				p.unit_id,
				COALESCE(u.label, ''),
				COALESCE(u.label_th, ''),
				p.name,
				COALESCE(p.name_th, ''),
				COALESCE(p.details, ''),
				p.cost,
				p.price,
				COALESCE(p.image, ''),
				COALESCE(p.is_active, false),
				COALESCE(SUM(CASE WHEN bs.branch_id = $%d THEN a.qty ELSE 0 END), 0) AS total_stock
			FROM "part_master" p
			LEFT JOIN "category_master" c ON c.id = p.category_id
			LEFT JOIN "unit_master" u ON u.id = p.unit_id
			LEFT JOIN "address_master" a ON a.part_code = p.code
			LEFT JOIN "store_master" s ON s.id = a.store_id
			LEFT JOIN "branch_store" bs ON bs.store_id = s.id AND bs.branch_id = $%d
			%s
			GROUP BY
				p.code, p.bar_code, p.category_id, c.label, c.label_th,
				p.unit_id, u.label, u.label_th,
				p.name, p.name_th, p.details, p.cost, p.price, p.image, p.is_active
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
				p.category_id,
				COALESCE(c.label, ''),
				COALESCE(c.label_th, ''),
				p.unit_id,
				COALESCE(u.label, ''),
				COALESCE(u.label_th, ''),
				p.name,
				COALESCE(p.name_th, ''),
				COALESCE(p.details, ''),
				p.cost,
				p.price,
				COALESCE(p.image, ''),
				COALESCE(p.is_active, false),
				COALESCE(SUM(a.qty), 0) AS total_stock
			FROM "part_master" p
			LEFT JOIN "category_master" c ON c.id = p.category_id
			LEFT JOIN "unit_master" u ON u.id = p.unit_id
			LEFT JOIN "address_master" a ON a.part_code = p.code
			%s
			GROUP BY
				p.code, p.bar_code, p.category_id, c.label, c.label_th,
				p.unit_id, u.label, u.label_th,
				p.name, p.name_th, p.details, p.cost, p.price, p.image, p.is_active
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
			&d.Details,
			&d.Cost,
			&d.Price,
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


