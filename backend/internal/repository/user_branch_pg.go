package repository

import (
	"context"
	"database/sql"
	"errors"
)

type userBranchRepositoryPG struct {
	db *sql.DB
}

func NewUserBranchRepository(db *sql.DB) UserBranchRepository {
	return &userBranchRepositoryPG{db: db}
}

func (r *userBranchRepositoryPG) GetByUserID(ctx context.Context, userID string) ([]UserBranch, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT "user_id", "branch_id"
		FROM "user_branch"
		WHERE "user_id" = $1
		ORDER BY "branch_id"
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var userBranches []UserBranch
	for rows.Next() {
		var ub UserBranch
		if err := rows.Scan(&ub.UserID, &ub.BranchID); err != nil {
			return nil, err
		}
		userBranches = append(userBranches, ub)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	return userBranches, nil
}

func (r *userBranchRepositoryPG) GetByBranchID(ctx context.Context, branchID string) ([]UserBranch, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT "user_id", "branch_id"
		FROM "user_branch"
		WHERE "branch_id" = $1
		ORDER BY "user_id"
	`, branchID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var userBranches []UserBranch
	for rows.Next() {
		var ub UserBranch
		if err := rows.Scan(&ub.UserID, &ub.BranchID); err != nil {
			return nil, err
		}
		userBranches = append(userBranches, ub)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	return userBranches, nil
}

func (r *userBranchRepositoryPG) GetByUserAndBranch(ctx context.Context, userID, branchID string) (*UserBranch, error) {
	row := r.db.QueryRowContext(ctx, `
		SELECT "user_id", "branch_id"
		FROM "user_branch"
		WHERE "user_id" = $1 AND "branch_id" = $2
	`, userID, branchID)

	var ub UserBranch
	err := row.Scan(&ub.UserID, &ub.BranchID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}

	return &ub, nil
}

func (r *userBranchRepositoryPG) Create(ctx context.Context, userBranch *UserBranch) error {
	_, err := r.db.ExecContext(ctx, `
		INSERT INTO "user_branch"("user_id", "branch_id")
		VALUES ($1, $2)
		ON CONFLICT ("user_id", "branch_id") DO NOTHING
	`, userBranch.UserID, userBranch.BranchID)
	return err
}

func (r *userBranchRepositoryPG) Delete(ctx context.Context, userID, branchID string) error {
	_, err := r.db.ExecContext(ctx, `
		DELETE FROM "user_branch"
		WHERE "user_id" = $1 AND "branch_id" = $2
	`, userID, branchID)
	return err
}

