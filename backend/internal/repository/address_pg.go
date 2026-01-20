package repository

import (
	"context"
	"database/sql"
	"errors"
)

type addressRepositoryPG struct {
	db *sql.DB
}

func NewAddressRepository(db *sql.DB) AddressRepository {
	return &addressRepositoryPG{db: db}
}

func (r *addressRepositoryPG) GetByCode(ctx context.Context, code string) (*Address, error) {
	row := r.db.QueryRowContext(ctx, `
		SELECT "code", "part_code", "store_id", "shelf", "qty", "min", "max", "rop", "remarks"
		FROM "address_master"
		WHERE "code" = $1
	`, code)

	var a Address
	err := row.Scan(&a.Code, &a.PartCode, &a.StoreID, &a.Shelf, &a.Qty, &a.Min, &a.Max, &a.Rop, &a.Remarks)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}

	return &a, nil
}

func (r *addressRepositoryPG) List(ctx context.Context, limit, offset int) ([]Address, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT "code", "part_code", "store_id", "shelf", "qty", "min", "max", "rop", "remarks"
		FROM "address_master"
		ORDER BY "code"
		LIMIT $1 OFFSET $2
	`, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var addresses []Address
	for rows.Next() {
		var a Address
		if err := rows.Scan(&a.Code, &a.PartCode, &a.StoreID, &a.Shelf, &a.Qty, &a.Min, &a.Max, &a.Rop, &a.Remarks); err != nil {
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
		WHERE "code" = $9
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
		WHERE "code" = $1
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
		WHERE "code" = $2 AND "qty" >= $1
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
