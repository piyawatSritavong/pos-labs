package repository

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
)

type addressRepositoryPG struct {
	db *sql.DB
}

func NewAddressRepository(db *sql.DB) AddressRepository {
	return &addressRepositoryPG{db: db}
}

func (r *addressRepositoryPG) GetByCode(ctx context.Context, code string) (*Address, error) {
	row := r.db.QueryRowContext(ctx, `
		SELECT a."code", a."part_code", a."store_id", a."shelf", a."qty",
		       a."min", a."max", a."rop", a."remarks",
		       COALESCE(NULLIF(p."name_th", ''), p."name", ''),
		       COALESCE(NULLIF(s."label_th", ''), s."label", a."store_id"),
		       COALESCE(s."branch_id", ''),
		       COALESCE(p."cost", 0), COALESCE(p."price", 0), COALESCE(p."min_price", 0)
		FROM "address_master" a
		LEFT JOIN "part_master" p ON p."code" = a."part_code"
		LEFT JOIN "store_master" s ON s."id" = a."store_id"
		WHERE a."code" = $1 AND a."is_active" = true
	`, code)

	var a Address
	err := row.Scan(
		&a.Code, &a.PartCode, &a.StoreID, &a.Shelf, &a.Qty,
		&a.Min, &a.Max, &a.Rop, &a.Remarks, &a.PartName, &a.StoreName, &a.BranchID,
		&a.Cost, &a.Price, &a.MinPrice,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}

	return &a, nil
}

// Search lists addresses with optional server-side filtering by free-text query
// (part code / part name / store name) and/or storeID, plus LIMIT/OFFSET paging.
// This lets the Addresses page filter+page on the server instead of loading the
// whole catalog and filtering in Dart. Empty q/storeID behaves like List.
func (r *addressRepositoryPG) Search(ctx context.Context, q, storeID string, branchID *string, limit, offset int) ([]Address, error) {
	var conds []string
	var args []interface{}
	argn := 1

	if s := strings.TrimSpace(q); s != "" {
		like := "%" + s + "%"
		conds = append(conds, fmt.Sprintf(
			`(a."part_code" ILIKE $%d OR p."name" ILIKE $%d OR p."name_th" ILIKE $%d OR s."label" ILIKE $%d OR s."label_th" ILIKE $%d)`,
			argn, argn, argn, argn, argn,
		))
		args = append(args, like)
		argn++
	}
	if sid := strings.TrimSpace(storeID); sid != "" {
		conds = append(conds, fmt.Sprintf(`a."store_id" = $%d`, argn))
		args = append(args, sid)
		argn++
	}
	if branchID != nil && strings.TrimSpace(*branchID) != "" {
		conds = append(conds, fmt.Sprintf(`s."branch_id" = $%d`, argn))
		args = append(args, strings.TrimSpace(*branchID))
		argn++
	}
	conds = append(conds, `a."is_active" = true`)

	where := ""
	if len(conds) > 0 {
		where = " WHERE " + strings.Join(conds, " AND ")
	}

	query := `
		SELECT
			a."code", a."part_code", a."store_id", a."shelf", a."qty",
			a."min", a."max", a."rop", a."remarks",
			COALESCE(NULLIF(p."name_th", ''), p."name", '') AS part_name,
			COALESCE(NULLIF(s."label_th", ''), s."label", a."store_id") AS store_name,
			COALESCE(s."branch_id", '') AS branch_id,
			COALESCE(p."cost", 0), COALESCE(p."price", 0), COALESCE(p."min_price", 0)
		FROM "address_master" a
		LEFT JOIN "part_master"  p ON p."code" = a."part_code"
		LEFT JOIN "store_master" s ON s."id"   = a."store_id"` +
		where +
		fmt.Sprintf(` ORDER BY a."code" LIMIT $%d OFFSET $%d`, argn, argn+1)
	args = append(args, limit, offset)

	rows, err := r.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var addresses []Address
	for rows.Next() {
		var a Address
		if err := rows.Scan(
			&a.Code, &a.PartCode, &a.StoreID, &a.Shelf, &a.Qty,
			&a.Min, &a.Max, &a.Rop, &a.Remarks,
			&a.PartName, &a.StoreName, &a.BranchID, &a.Cost, &a.Price, &a.MinPrice,
		); err != nil {
			return nil, err
		}
		addresses = append(addresses, a)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	return addresses, nil
}

// Count mirrors the Search WHERE clause (q + storeID) but returns COUNT(*) so
// the Addresses page can render a page-jump dropdown.
func (r *addressRepositoryPG) Count(ctx context.Context, q, storeID string, branchID *string) (int, error) {
	var conds []string
	var args []interface{}
	argn := 1

	if s := strings.TrimSpace(q); s != "" {
		like := "%" + s + "%"
		conds = append(conds, fmt.Sprintf(
			`(a."part_code" ILIKE $%d OR p."name" ILIKE $%d OR p."name_th" ILIKE $%d OR s."label" ILIKE $%d OR s."label_th" ILIKE $%d)`,
			argn, argn, argn, argn, argn,
		))
		args = append(args, like)
		argn++
	}
	if sid := strings.TrimSpace(storeID); sid != "" {
		conds = append(conds, fmt.Sprintf(`a."store_id" = $%d`, argn))
		args = append(args, sid)
		argn++
	}
	if branchID != nil && strings.TrimSpace(*branchID) != "" {
		conds = append(conds, fmt.Sprintf(`s."branch_id" = $%d`, argn))
		args = append(args, strings.TrimSpace(*branchID))
		argn++
	}
	conds = append(conds, `a."is_active" = true`)

	where := ""
	if len(conds) > 0 {
		where = " WHERE " + strings.Join(conds, " AND ")
	}

	query := `
		SELECT COUNT(*)
		FROM "address_master" a
		LEFT JOIN "part_master"  p ON p."code" = a."part_code"
		LEFT JOIN "store_master" s ON s."id"   = a."store_id"` + where

	var total int
	if err := r.db.QueryRowContext(ctx, query, args...).Scan(&total); err != nil {
		return 0, err
	}
	return total, nil
}

func (r *addressRepositoryPG) List(ctx context.Context, limit, offset int) ([]Address, error) {
	// LEFT JOIN part_master + store_master so the Addresses page can display
	// product name and store label without a second round-trip. COALESCE protects
	// against NULL rows older seed data may have left.
	rows, err := r.db.QueryContext(ctx, `
		SELECT
			a."code", a."part_code", a."store_id", a."shelf", a."qty",
			a."min", a."max", a."rop", a."remarks",
			COALESCE(NULLIF(p."name_th", ''), p."name", '') AS part_name,
			COALESCE(NULLIF(s."label_th", ''), s."label", a."store_id") AS store_name,
			COALESCE(s."branch_id", '') AS branch_id,
			COALESCE(p."cost", 0), COALESCE(p."price", 0), COALESCE(p."min_price", 0)
		FROM "address_master" a
		LEFT JOIN "part_master"  p ON p."code" = a."part_code"
		LEFT JOIN "store_master" s ON s."id"   = a."store_id"
		WHERE a."is_active" = true
		ORDER BY a."code"
		LIMIT $1 OFFSET $2
	`, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var addresses []Address
	for rows.Next() {
		var a Address
		if err := rows.Scan(
			&a.Code, &a.PartCode, &a.StoreID, &a.Shelf, &a.Qty,
			&a.Min, &a.Max, &a.Rop, &a.Remarks,
			&a.PartName, &a.StoreName, &a.BranchID, &a.Cost, &a.Price, &a.MinPrice,
		); err != nil {
			return nil, err
		}
		addresses = append(addresses, a)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	return addresses, nil
}

func (r *addressRepositoryPG) Create(ctx context.Context, address *Address) error {
	_, err := r.db.ExecContext(ctx, `
		INSERT INTO "address_master"("code", "part_code", "store_id", "shelf", "qty", "min", "max", "rop", "remarks")
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
	`, address.Code, address.PartCode, address.StoreID, address.Shelf, address.Qty, address.Min, address.Max, address.Rop, address.Remarks)
	return err
}

func (r *addressRepositoryPG) Update(ctx context.Context, address *Address) error {
	result, err := r.db.ExecContext(ctx, `
		UPDATE "address_master"
		SET "part_code" = $1, "store_id" = $2, "shelf" = $3, "qty" = $4, "min" = $5, "max" = $6, "rop" = $7, "remarks" = $8
		WHERE "code" = $9 AND "is_active" = true
	`, address.PartCode, address.StoreID, address.Shelf, address.Qty, address.Min, address.Max, address.Rop, address.Remarks, address.Code)
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

func (r *addressRepositoryPG) Delete(ctx context.Context, code string) error {
	result, err := r.db.ExecContext(ctx, `
		DELETE FROM "address_master"
		WHERE "code" = $1 AND "is_active" = true
	`, code)
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

func (r *addressRepositoryPG) DecreaseInventory(ctx context.Context, addressCode string, qty int) (bool, error) {
	result, err := r.db.ExecContext(ctx, `
		UPDATE "address_master"
		SET "qty" = "qty" - $1
		WHERE "code" = $2 AND "is_active" = true AND "qty" >= $1
	`, qty, addressCode)
	if err != nil {
		return false, err
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return false, err
	}

	return rowsAffected > 0, nil
}

func (r *addressRepositoryPG) IncreaseInventory(ctx context.Context, addressCode string, qty int) error {
	result, err := r.db.ExecContext(ctx, `
		UPDATE "address_master"
		SET "qty" = "qty" + $1
		WHERE "code" = $2
	`, qty, addressCode)
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
