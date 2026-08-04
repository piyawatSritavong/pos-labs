package repository

import (
	"context"
	"database/sql"
	"os"
	"testing"
)

func TestFormatPartCode(t *testing.T) {
	tests := []struct {
		name     string
		sequence int64
		want     string
	}{
		{name: "first", sequence: 1, want: "P0001"},
		{name: "four digits", sequence: 9999, want: "P9999"},
		{name: "grows past four digits", sequence: 10000, want: "P10000"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := formatPartCode(tt.sequence); got != tt.want {
				t.Fatalf("formatPartCode(%d) = %q, want %q", tt.sequence, got, tt.want)
			}
		})
	}
}

func TestCreatePartCreatesInitialAddresses(t *testing.T) {
	databaseURL := os.Getenv("TEST_DATABASE_URL")
	if databaseURL == "" {
		t.Skip("TEST_DATABASE_URL is not set")
	}

	db, err := sql.Open("postgres", databaseURL)
	if err != nil {
		t.Fatalf("open test database: %v", err)
	}
	defer db.Close()

	created, err := NewPartRepository(db).CreatePart(context.Background(), PartInput{
		Name:     "Address integration test",
		NameTH:   "ทดสอบตำแหน่งสต๊อก",
		Price:    100,
		IsActive: true,
	})
	if err != nil {
		t.Fatalf("CreatePart: %v", err)
	}
	t.Cleanup(func() {
		_, _ = db.Exec(`DELETE FROM "part_master" WHERE "code"=$1`, created.Code)
	})

	var addressCount int
	var stores string
	var allZero bool
	err = db.QueryRow(`
		SELECT
			COUNT(*),
			COALESCE(string_agg("store_id", ',' ORDER BY "store_id"), ''),
			COALESCE(bool_and(COALESCE("qty", 0) = 0 AND COALESCE("rop", 0) = 0), false)
		FROM "address_master"
		WHERE "part_code"=$1
	`, created.Code).Scan(&addressCount, &stores, &allZero)
	if err != nil {
		t.Fatalf("query initial addresses: %v", err)
	}
	if addressCount != 2 {
		t.Fatalf("initial address count = %d, want 2 (stores: %s)", addressCount, stores)
	}
	if stores != "branch1-default,branch2-default" {
		t.Fatalf("initial address stores = %q, want branch defaults", stores)
	}
	if !allZero {
		t.Fatal("initial addresses must start with Qty=0 and ROP=0")
	}
}
