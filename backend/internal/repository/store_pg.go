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
		       COALESCE(s.is_default, false), s.location_type
		FROM "store_master" s
		LEFT JOIN "branch_setting" b ON b.branch_id = s.branch_id
		WHERE s.location_type = 'warehouse'
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
			&s.Label, &s.LabelTH, &s.IsDefault, &s.LocationType); err != nil {
			return nil, err
		}
		out = append(out, s)
	}
	return out, rows.Err()
}
