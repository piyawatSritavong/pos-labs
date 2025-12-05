package repository

import (
	"context"
	"database/sql"
	"errors"
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

func (r *branchRepositoryPG) Create(ctx context.Context, branch *Branch) error {
	_, err := r.db.ExecContext(ctx, `
		INSERT INTO "branch_setting"(
			"branch_id", "company_id", "branch_name", "branch_name_th",
			"branch_address", "branch_address_th", "phone", "email"
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
	`,
		branch.BranchID, branch.CompanyID, branch.BranchName, branch.BranchNameTH,
		branch.BranchAddress, branch.BranchAddressTH, branch.Phone, branch.Email,
	)
	return err
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
	_, err := r.db.ExecContext(ctx, `DELETE FROM "branch_setting" WHERE "branch_id" = $1`, id)
	return err
}

func (r *branchRepositoryPG) Count(ctx context.Context) (int, error) {
	var count int
	err := r.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM "branch_setting"`).Scan(&count)
	return count, err
}

