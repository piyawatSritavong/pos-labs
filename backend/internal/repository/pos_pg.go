package repository

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"errors"
	"strings"
)

type posRepositoryPG struct {
	db *sql.DB
}

func NewPOSRepository(db *sql.DB) POSRepository {
	return &posRepositoryPG{db: db}
}

func (r *posRepositoryPG) GetByID(ctx context.Context, id string) (*POS, error) {
	row := r.db.QueryRowContext(ctx, `
		SELECT "pos_id", "branch_id", "pos_name", "pos_secret", "is_active", COALESCE("vehicle_store_id", '')
		FROM "pos_setting"
		WHERE "pos_id" = $1
	`, id)

	var p POS
	err := row.Scan(&p.POSID, &p.BranchID, &p.POSName, &p.POSSecret, &p.IsActive, &p.VehicleStoreID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}

	return &p, nil
}

func (r *posRepositoryPG) GetFirstActiveByBranch(ctx context.Context, branchID string) (*POS, error) {
	row := r.db.QueryRowContext(ctx, `
		SELECT "pos_id", "branch_id", "pos_name", "pos_secret", "is_active", COALESCE("vehicle_store_id", '')
		FROM "pos_setting"
		WHERE "is_active" = true AND ($1 = '' OR "branch_id" = $1)
		ORDER BY "pos_id"
		LIMIT 1
	`, branchID)

	var p POS
	err := row.Scan(&p.POSID, &p.BranchID, &p.POSName, &p.POSSecret, &p.IsActive, &p.VehicleStoreID)
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
		SELECT "pos_id", "branch_id", "pos_name", "pos_secret", "is_active", COALESCE("vehicle_store_id", '')
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
		if err := rows.Scan(&p.POSID, &p.BranchID, &p.POSName, &p.POSSecret, &p.IsActive, &p.VehicleStoreID); err != nil {
			return nil, err
		}
		posList = append(posList, p)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	return posList, nil
}

// generatePOSSecret generates a random 32-byte secret and returns it as a hex string
func generatePOSSecret() (string, error) {
	secretBytes := make([]byte, 32)
	if _, err := rand.Read(secretBytes); err != nil {
		return "", err
	}
	return hex.EncodeToString(secretBytes), nil
}

func (r *posRepositoryPG) RefreshSecret(ctx context.Context, id string) (string, error) {
	// Generate new secret
	newSecret, err := generatePOSSecret()
	if err != nil {
		return "", err
	}

	// Update the secret in database and verify POS exists
	result, err := r.db.ExecContext(ctx, `
		UPDATE "pos_setting"
		SET "pos_secret" = $1
		WHERE "pos_id" = $2
	`, newSecret, id)
	if err != nil {
		return "", err
	}

	// Verify the POS exists (if no rows affected, POS doesn't exist)
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return "", err
	}
	if rowsAffected == 0 {
		return "", ErrNotFound
	}

	return newSecret, nil
}

func (r *posRepositoryPG) Create(ctx context.Context, pos *POS) error {
	// Generate pos_secret if not provided
	if pos.POSSecret == "" {
		secret, err := generatePOSSecret()
		if err != nil {
			return err
		}
		pos.POSSecret = secret
	}
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	if strings.TrimSpace(pos.VehicleStoreID) == "" {
		err = tx.QueryRowContext(ctx, `
			SELECT s."id"
			FROM "store_master" s
			JOIN "branch_store" bs
			  ON bs."branch_id" = s."branch_id"
			 AND bs."store_id" = s."id"
			WHERE s."branch_id" = $1
			ORDER BY bs."is_default" DESC, s."is_default" DESC, s."id"
			LIMIT 1
		`, pos.BranchID).Scan(&pos.VehicleStoreID)
		if errors.Is(err, sql.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
	}

	_, err = tx.ExecContext(ctx, `
		INSERT INTO "pos_setting"("pos_id", "branch_id", "pos_name", "pos_secret", "is_active", "vehicle_store_id")
		VALUES ($1, $2, $3, $4, $5, $6)
	`, pos.POSID, pos.BranchID, pos.POSName, pos.POSSecret, pos.IsActive, pos.VehicleStoreID)
	if err != nil {
		return err
	}

	return tx.Commit()
}

func (r *posRepositoryPG) Delete(ctx context.Context, id string) error {
	_, err := r.db.ExecContext(ctx, `DELETE FROM "pos_setting" WHERE "pos_id" = $1`, id)
	return err
}

func (r *posRepositoryPG) GetSecret(ctx context.Context, id string) (string, error) {
	row := r.db.QueryRowContext(ctx, `
		SELECT "pos_secret"
		FROM "pos_setting"
		WHERE "pos_id" = $1
	`, id)

	var secret string
	err := row.Scan(&secret)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return "", ErrNotFound
		}
		return "", err
	}

	return secret, nil
}

func (r *posRepositoryPG) ToggleActive(ctx context.Context, id string) error {
	_, err := r.db.ExecContext(ctx, `
		UPDATE "pos_setting"
		SET "is_active" = NOT "is_active"
		WHERE "pos_id" = $1
	`, id)
	return err
}
