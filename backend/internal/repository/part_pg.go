package repository

import (
	"context"
	"database/sql"
)

type partRepositoryPG struct {
	db *sql.DB
}

func NewPartRepository(db *sql.DB) PartRepository {
	return &partRepositoryPG{db: db}
}

func (r *partRepositoryPG) ListParts(ctx context.Context, limit, offset int) ([]PartSummary, error) {
	if limit <= 0 {
		limit = 50
	}
	if offset < 0 {
		offset = 0
	}

	rows, err := r.db.QueryContext(ctx, `
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

func (r *partRepositoryPG) GetPartDetail(ctx context.Context, code string) (*PartDetail, []PartAddress, error) {
	// Header with aggregated stock, category, and unit
	row := r.db.QueryRowContext(ctx, `
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
	`, code)

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

	// Addresses
	rows, err := r.db.QueryContext(ctx, `
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
			COALESCE(a.remarks, '')
		FROM "address_master" a
		JOIN "store_master" s ON s.id = a.store_id
		WHERE a.part_code = $1
		ORDER BY a.code
	`, code)
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
		); err != nil {
			return &d, nil, err
		}
		// is_default doesn't exist in address_master schema
		a.IsDefault = false
		addrs = append(addrs, a)
	}
	if err := rows.Err(); err != nil {
		return &d, nil, err
	}

	return &d, addrs, nil
}


