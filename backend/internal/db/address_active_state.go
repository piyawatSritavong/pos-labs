package db

import (
	"context"
	"database/sql"
	"fmt"
	"time"
)

// EnsureAddressActiveState keeps the legacy Render service safe while its
// AUTO_MIGRATE setting remains disabled. Migration 0022 is still the canonical
// schema change; this idempotent guard only ensures the additive column/index
// exist before repositories or the catalog compatibility seed use them.
func EnsureAddressActiveState(db *sql.DB) error {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if _, err := db.ExecContext(ctx, `
		ALTER TABLE "address_master"
		  ADD COLUMN IF NOT EXISTS "is_active" boolean NOT NULL DEFAULT true;

		UPDATE "address_master"
		SET "is_active" = false
		WHERE "remarks" LIKE 'archived by catalog replacement %';

		CREATE INDEX IF NOT EXISTS "idx_address_master_active_part_store"
		  ON "address_master" ("part_code", "store_id")
		  WHERE "is_active" = true;
	`); err != nil {
		return fmt.Errorf("ensure address active state: %w", err)
	}
	return nil
}
