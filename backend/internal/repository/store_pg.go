package repository

import (
	"context"
	"database/sql"
)

type storeRepositoryPG struct {
	db *sql.DB
}

func NewStoreRepository(db *sql.DB) StoreRepository {
	return &storeRepositoryPG{db: db}
}

func (r *storeRepositoryPG) ListStores(ctx context.Context) ([]StoreListItem, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT s.id, s.branch_id,
		       COALESCE(b.branch_name, ''), COALESCE(b.branch_name_th, ''),
		       COALESCE(s.label, ''), COALESCE(s.label_th, ''),
		       COALESCE(s.is_default, false)
		FROM "store_master" s
		LEFT JOIN "branch_setting" b ON b.branch_id = s.branch_id
		ORDER BY s.branch_id, s.is_default DESC, s.id
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []StoreListItem
	for rows.Next() {
		var s StoreListItem
		if err := rows.Scan(&s.ID, &s.BranchID, &s.BranchName, &s.BranchNameTH,
			&s.Label, &s.LabelTH, &s.IsDefault); err != nil {
			return nil, err
		}
		out = append(out, s)
	}
	return out, rows.Err()
}

func (r *storeRepositoryPG) CreateStore(ctx context.Context, s StoreInput) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()

	if _, err := tx.ExecContext(ctx, `
		INSERT INTO "store_master"("id", "branch_id", "label", "label_th", "is_default")
		VALUES ($1, $2, $3, $4, $5)
	`, s.ID, s.BranchID, s.Label, s.LabelTH, s.IsDefault); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `
		INSERT INTO "branch_store"("branch_id", "store_id", "is_default")
		VALUES ($1, $2, $3)
		ON CONFLICT ("branch_id", "store_id") DO NOTHING
	`, s.BranchID, s.ID, s.IsDefault); err != nil {
		return err
	}
	return tx.Commit()
}
