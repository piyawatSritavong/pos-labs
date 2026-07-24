package db

import (
	"context"
	"database/sql"
	_ "embed"
	"fmt"
	"time"
)

const catalogSeedID = "catalog-20260724-ppsale-v1"

//go:embed seed_catalog_20260724.sql
var catalogSeedSQL string

// ApplyProductionCatalog20260724 runs the requested production catalog
// replacement exactly once per database. The SQL itself is transactional and
// idempotent; the marker prevents doing the heavier staging work on every
// Render restart.
func ApplyProductionCatalog20260724(db *sql.DB) (bool, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()

	conn, err := db.Conn(ctx)
	if err != nil {
		return false, fmt.Errorf("catalog seed get connection: %w", err)
	}
	defer conn.Close()

	if _, err := conn.ExecContext(ctx, `
		CREATE TABLE IF NOT EXISTS "data_seed_history" (
			"id" text PRIMARY KEY,
			"applied_at" timestamptz NOT NULL DEFAULT now()
		)
	`); err != nil {
		return false, fmt.Errorf("catalog seed create history: %w", err)
	}

	if _, err := conn.ExecContext(
		ctx,
		`SELECT pg_advisory_lock(hashtextextended($1, 0))`,
		catalogSeedID,
	); err != nil {
		return false, fmt.Errorf("catalog seed lock: %w", err)
	}
	defer func() {
		unlockCtx, unlockCancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer unlockCancel()
		_, _ = conn.ExecContext(
			unlockCtx,
			`SELECT pg_advisory_unlock(hashtextextended($1, 0))`,
			catalogSeedID,
		)
	}()

	var alreadyApplied bool
	if err := conn.QueryRowContext(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM "data_seed_history" WHERE "id" = $1
		)
	`, catalogSeedID).Scan(&alreadyApplied); err != nil {
		return false, fmt.Errorf("catalog seed read history: %w", err)
	}
	if alreadyApplied {
		return false, nil
	}

	if _, err := conn.ExecContext(ctx, catalogSeedSQL); err != nil {
		return false, fmt.Errorf("catalog seed execute: %w", err)
	}
	if _, err := conn.ExecContext(ctx, `
		INSERT INTO "data_seed_history" ("id") VALUES ($1)
		ON CONFLICT ("id") DO NOTHING
	`, catalogSeedID); err != nil {
		return false, fmt.Errorf("catalog seed mark applied: %w", err)
	}
	return true, nil
}
