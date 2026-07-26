package repository

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
)

type branchRepositoryPG struct {
	db *sql.DB
}

func NewBranchRepository(db *sql.DB) BranchRepository {
	return &branchRepositoryPG{db: db}
}

func (r *branchRepositoryPG) GetByID(ctx context.Context, id string) (*Branch, error) {
	row := r.db.QueryRowContext(ctx, `
		SELECT "branch_id", "company_id", "branch_name", "branch_name_th",
		       "branch_address", "branch_address_th", "phone", "email"
		FROM "branch_setting"
		WHERE "branch_id" = $1
	`, id)

	var b Branch
	var email sql.NullString
	err := row.Scan(
		&b.BranchID, &b.CompanyID, &b.BranchName, &b.BranchNameTH,
		&b.BranchAddress, &b.BranchAddressTH, &b.Phone, &email,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}

	if email.Valid {
		b.Email = &email.String
	}

	return &b, nil
}

func (r *branchRepositoryPG) List(ctx context.Context, limit, offset int) ([]Branch, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT "branch_id", "company_id", "branch_name", "branch_name_th",
		       "branch_address", "branch_address_th", "phone", "email"
		FROM "branch_setting"
		ORDER BY "branch_id"
		LIMIT $1 OFFSET $2
	`, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var branches []Branch
	for rows.Next() {
		var b Branch
		var email sql.NullString
		if err := rows.Scan(
			&b.BranchID, &b.CompanyID, &b.BranchName, &b.BranchNameTH,
			&b.BranchAddress, &b.BranchAddressTH, &b.Phone, &email,
		); err != nil {
			return nil, err
		}
		if email.Valid {
			b.Email = &email.String
		}
		branches = append(branches, b)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	return branches, nil
}

func (r *branchRepositoryPG) NextID(ctx context.Context) (string, error) {
	var next int
	err := r.db.QueryRowContext(ctx, `
		WITH branch_max AS (
			SELECT COALESCE(MAX(
				CASE WHEN "branch_id" ~ '^[0-9]{5}$' THEN "branch_id"::integer END
			), -1) AS value
			FROM "branch_setting"
		)
		SELECT GREATEST(
			(SELECT value + 1 FROM branch_max),
			COALESCE((SELECT "value" + 1 FROM "counter" WHERE "key" = 'branch_id'), 0)
		)
	`).Scan(&next)
	if err != nil {
		return "", err
	}
	if next > 99999 {
		return "", fmt.Errorf("branch id sequence exhausted")
	}
	return fmt.Sprintf("%05d", next), nil
}

func (r *branchRepositoryPG) Create(ctx context.Context, branch *Branch) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	// Serialize allocation so concurrent branch creations cannot receive the
	// same human-readable five-digit ID.
	if _, err := tx.ExecContext(ctx, `
		SELECT pg_advisory_xact_lock(hashtext('branch-id-sequence'))
	`); err != nil {
		return err
	}

	var next int
	if err := tx.QueryRowContext(ctx, `
		WITH branch_max AS (
			SELECT COALESCE(MAX(
				CASE WHEN "branch_id" ~ '^[0-9]{5}$' THEN "branch_id"::integer END
			), -1) AS value
			FROM "branch_setting"
		)
		INSERT INTO "counter"("key", "value")
		SELECT 'branch_id', value + 1 FROM branch_max
		ON CONFLICT ("key") DO UPDATE
		SET "value" = GREATEST(
			"counter"."value" + 1,
			EXCLUDED."value"
		)
		RETURNING "value"
	`).Scan(&next); err != nil {
		return err
	}
	if next > 99999 {
		return fmt.Errorf("branch id sequence exhausted")
	}
	branch.BranchID = fmt.Sprintf("%05d", next)

	if _, err := tx.ExecContext(ctx, `
		INSERT INTO "branch_setting"(
			"branch_id", "company_id", "branch_name", "branch_name_th",
			"branch_address", "branch_address_th", "phone", "email"
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
	`,
		branch.BranchID, branch.CompanyID, branch.BranchName, branch.BranchNameTH,
		branch.BranchAddress, branch.BranchAddressTH, branch.Phone, branch.Email,
	); err != nil {
		return err
	}

	storeID := "store_" + branch.BranchID
	label := strings.TrimSpace(branch.BranchName)
	if label == "" {
		label = branch.BranchID
	}
	label += " Warehouse"
	labelTH := strings.TrimSpace(branch.BranchNameTH)
	if labelTH == "" {
		labelTH = branch.BranchID
	}
	labelTH = "คลัง" + labelTH

	if _, err := tx.ExecContext(ctx, `
		INSERT INTO "store_master"("id", "branch_id", "label", "label_th", "is_default")
		VALUES ($1, $2, $3, $4, true)
	`, storeID, branch.BranchID, label, labelTH); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `
		INSERT INTO "branch_store"("branch_id", "store_id", "is_default")
		VALUES ($1, $2, true)
	`, branch.BranchID, storeID); err != nil {
		return err
	}

	return tx.Commit()
}

func (r *branchRepositoryPG) Update(ctx context.Context, branch *Branch) error {
	_, err := r.db.ExecContext(ctx, `
		UPDATE "branch_setting"
		SET "company_id" = $1, "branch_name" = $2, "branch_name_th" = $3,
		    "branch_address" = $4, "branch_address_th" = $5, "phone" = $6, "email" = $7
		WHERE "branch_id" = $8
	`,
		branch.CompanyID, branch.BranchName, branch.BranchNameTH,
		branch.BranchAddress, branch.BranchAddressTH, branch.Phone, branch.Email,
		branch.BranchID,
	)
	return err
}

func (r *branchRepositoryPG) Delete(ctx context.Context, id string) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	var exists bool
	if err := tx.QueryRowContext(ctx, `
		SELECT EXISTS(SELECT 1 FROM "branch_setting" WHERE "branch_id" = $1)
	`, id).Scan(&exists); err != nil {
		return err
	}
	if !exists {
		return ErrNotFound
	}

	if _, err := tx.ExecContext(ctx, `
		DELETE FROM "branch_store" WHERE "branch_id" = $1
	`, id); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `
		DELETE FROM "store_master" WHERE "branch_id" = $1
	`, id); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `
		DELETE FROM "branch_setting" WHERE "branch_id" = $1
	`, id); err != nil {
		return err
	}
	return tx.Commit()
}

func (r *branchRepositoryPG) Count(ctx context.Context) (int, error) {
	var count int
	err := r.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM "branch_setting"`).Scan(&count)
	return count, err
}

func (r *branchRepositoryPG) GetStoresByBranchID(ctx context.Context, branchID string) ([]Store, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT s.id, s.branch_id, s.label, s.label_th, COALESCE(bs.is_default, false) as is_default
		FROM "store_master" s
		JOIN "branch_store" bs ON bs.store_id = s.id
		WHERE bs.branch_id = $1
		ORDER BY bs.is_default DESC, s.id
	`, branchID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var stores []Store
	for rows.Next() {
		var s Store
		if err := rows.Scan(
			&s.ID,
			&s.BranchID,
			&s.Label,
			&s.LabelTH,
			&s.IsDefault,
		); err != nil {
			return nil, err
		}
		stores = append(stores, s)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	return stores, nil
}
