package db

import (
	"database/sql"
	"log"
)

// EnsureBarcodes backfills part_master.bar_code for every part whose barcode
// is empty/null, using the part's own code as the value (Code128 friendly).
//
// This complements migration 0012_generate_missing_barcodes — that migration
// runs once at first deploy, but EnsureBarcodes also runs on every backend
// start so any parts created later (e.g. via a future POST /parts handler or
// out-of-band SQL INSERTs) automatically receive a barcode the next time the
// server starts.
//
// Idempotent: returns silently when there is nothing to do.
func EnsureBarcodes(sqlDB *sql.DB) error {
	res, err := sqlDB.Exec(`
		UPDATE "part_master"
		   SET "bar_code" = "code"
		 WHERE COALESCE("bar_code", '') = ''
		   AND "code" ~ '^P[0-9]+$'
	`)
	if err != nil {
		return err
	}
	if n, err := res.RowsAffected(); err == nil && n > 0 {
		log.Printf("EnsureBarcodes: backfilled %d empty barcodes with part code", n)
	}
	return nil
}
