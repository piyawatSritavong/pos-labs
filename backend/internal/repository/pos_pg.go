package repository

import (
	"context"
	"database/sql"
	"errors"
)

type posRepositoryPG struct {
	db *sql.DB
}

func NewPOSRepository(db *sql.DB) POSRepository {
	return &posRepositoryPG{db: db}
}

func (r *posRepositoryPG) GetByID(ctx context.Context, id string) (*POS, error) {
	row := r.db.QueryRowContext(ctx, `
		SELECT "pos_id", "branch_id", "pos_name"
		FROM "pos_setting"
		WHERE "pos_id" = $1
	`, id)

	var p POS
	err := row.Scan(&p.POSID, &p.BranchID, &p.POSName)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}

	return &p, nil
}

func (r *posRepositoryPG) List(ctx context.Context, limit, offset int) ([]POS, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT "pos_id", "branch_id", "pos_name"
		FROM "pos_setting"
		ORDER BY "pos_id"
		LIMIT $1 OFFSET $2
	`, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var posList []POS
	for rows.Next() {
		var p POS
		if err := rows.Scan(&p.POSID, &p.BranchID, &p.POSName); err != nil {
			return nil, err
		}
		posList = append(posList, p)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	return posList, nil
}

func (r *posRepositoryPG) Create(ctx context.Context, pos *POS) error {
	_, err := r.db.ExecContext(ctx, `
		INSERT INTO "pos_setting"("pos_id", "branch_id", "pos_name")
		VALUES ($1, $2, $3)
	`, pos.POSID, pos.BranchID, pos.POSName)
	return err
}

func (r *posRepositoryPG) Update(ctx context.Context, pos *POS) error {
	_, err := r.db.ExecContext(ctx, `
		UPDATE "pos_setting"
		SET "branch_id" = $1, "pos_name" = $2
		WHERE "pos_id" = $3
	`, pos.BranchID, pos.POSName, pos.POSID)
	return err
}

func (r *posRepositoryPG) Delete(ctx context.Context, id string) error {
	_, err := r.db.ExecContext(ctx, `DELETE FROM "pos_setting" WHERE "pos_id" = $1`, id)
	return err
}

