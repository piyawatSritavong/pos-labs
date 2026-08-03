package db

import (
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"fmt"
	"log"
	"os"
	"strings"

	"github.com/google/uuid"
	"golang.org/x/crypto/bcrypt"
)

// seedMockStockCounts inserts submitted stock count test data if none exist.
// This runs independently of the main mock data check so existing DBs get the data.
func seedMockStockCounts(db *sql.DB) error {
	var exists bool
	if err := db.QueryRow(`SELECT EXISTS(SELECT 1 FROM "stock_count" LIMIT 1)`).Scan(&exists); err != nil {
		return err
	}
	if exists {
		return nil
	}

	// Resolve a user ID to use as counted_by (prefer van staff, fall back to any user)
	var countedByID string
	err := db.QueryRow(`
		SELECT "id" FROM "user" WHERE "role_id" = 'role.van_staff' AND "is_active" = true LIMIT 1
	`).Scan(&countedByID)
	if err != nil {
		// Fall back to any active user
		if err2 := db.QueryRow(`SELECT "id" FROM "user" WHERE "is_active" = true LIMIT 1`).Scan(&countedByID); err2 != nil {
			log.Printf("Skipping mock stock count seed: no users found")
			return nil
		}
	}

	log.Printf("Seeding mock stock count data")
	tx, err := db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	counts := []struct {
		BranchID string
		StoreID  string
	}{
		{"00000", "main"},
		{"00002", "store_00001"},
	}

	for _, c := range counts {
		countID := strings.ReplaceAll(uuid.New().String(), "-", "")
		if _, err := tx.Exec(`
			INSERT INTO "stock_count"("id", "branch_id", "store_id", "counted_by", "status", "notes", "created_at", "submitted_at")
			VALUES ($1, $2, $3, $4, 'submitted', 'Mock stock count', NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 hour')
			ON CONFLICT ("id") DO NOTHING
		`, countID, c.BranchID, c.StoreID, countedByID); err != nil {
			return err
		}

		// Add a few count items per stock count (composite PK: count_id + part_code)
		for i := 1; i <= 3; i++ {
			partCode := fmt.Sprintf("P%04d", i)
			if _, err := tx.Exec(`
				INSERT INTO "stock_count_item"("count_id", "part_code", "system_qty", "counted_qty")
				VALUES ($1, $2, 100, $3)
				ON CONFLICT ("count_id", "part_code") DO NOTHING
			`, countID, partCode, 95+i); err != nil {
				return err
			}
		}
	}

	if err := tx.Commit(); err != nil {
		return err
	}
	log.Printf("Mock stock count data seeded")
	return nil
}

// SeedMockData inserts development-only mock data for categories, parts, and addresses.
// If any of these tables already have data, seeding is skipped entirely (all-or-nothing).
func SeedMockData(db *sql.DB) error {
	// The catalog seed can populate products before this development seed runs.
	// POS2's operational topology must therefore be ensured independently of
	// whether sample catalog rows already exist.
	if err := ensurePOS2MockTopology(db); err != nil {
		return err
	}

	// Check if any mock data already exists
	var exists bool
	err := db.QueryRow(`
		SELECT EXISTS(SELECT 1 FROM "category_master" LIMIT 1)
			OR EXISTS(SELECT 1 FROM "part_master" LIMIT 1)
			OR EXISTS(SELECT 1 FROM "address_master" LIMIT 1)
	`).Scan(&exists)
	if err != nil {
		return err
	}
	if exists {
		log.Printf("Mock data already exists, skipping main seeding")
		return seedMockStockCounts(db)
	}

	log.Printf("Seeding mock data for development (categories, parts, addresses)")

	tx, err := db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	// pos2's branch (00002) + its single store (คลังสาขา pos2). This is the
	// third branch in the 3-branch model (00000 สาขาหลัก and 00001 สาขา pos1
	// come from the core seed).
	if _, err := tx.Exec(`
		INSERT INTO "branch_setting"(
			"branch_id", "company_id", "branch_name", "branch_name_th",
			"branch_address", "branch_address_th", "phone", "email"
		)
		VALUES (
			'00002', '0000000000000', 'POS2 Branch', 'สาขา pos2',
			'456 Second Street', '456 ถนนที่สอง', '02-234-5678', 'branch2@example.com'
		)
		ON CONFLICT ("branch_id") DO NOTHING
	`); err != nil {
		return err
	}

	if _, err := tx.Exec(`
		INSERT INTO "store_master"("id", "branch_id", "label", "label_th", "is_default", "location_type")
		VALUES ('store_00001', '00002', 'POS2 Vehicle Stock', 'สต๊อกรถ POS2', true, 'vehicle')
		ON CONFLICT ("id") DO NOTHING
	`); err != nil {
		return err
	}

	if _, err := tx.Exec(`
		INSERT INTO "branch_store"("branch_id", "store_id", "is_default")
		VALUES ('00002', 'store_00001', true)
		ON CONFLICT ("branch_id", "store_id") DO NOTHING
	`); err != nil {
		return err
	}

	// Same POS_SECRET convention as the core seed (env override, random dev
	// fallback). Login also accepts the "default_if_needed" dev secret.
	posSecret := os.Getenv("POS_SECRET")
	if posSecret == "" {
		posSecretBytes := make([]byte, 32)
		if _, err := rand.Read(posSecretBytes); err != nil {
			return err
		}
		posSecret = hex.EncodeToString(posSecretBytes)
	}
	// POS002 (pos2) works on its branch's store (store_00001 = คลังสาขา pos2).
	if _, err := tx.Exec(`
		INSERT INTO "pos_setting"("pos_id", "branch_id", "pos_name", "pos_secret", "is_active", "vehicle_store_id")
		VALUES ('POS002', '00002', 'POS 2', $1, true, 'store_00001')
		ON CONFLICT ("pos_id") DO NOTHING
	`, posSecret); err != nil {
		return err
	}

	// Test users for development
	testUsers := []struct {
		Username string
		Password string
		RoleID   string
		Name     string
		BranchID string
	}{
		{"pos1", "pos123456", "role.cashier", "POS Cashier 1", "00000"},
		{"pos2", "pos123456", "role.cashier", "POS Cashier 2", "00002"},
	}
	for _, u := range testUsers {
		hash, err := bcrypt.GenerateFromPassword([]byte(u.Password), bcrypt.DefaultCost)
		if err != nil {
			return err
		}
		userID := strings.ReplaceAll(uuid.New().String(), "-", "")
		var insertedID string
		err = tx.QueryRow(`
			INSERT INTO "user"("id", "username", "role_id", "name", "password", "is_active", "is_superuser")
			VALUES ($1, $2, $3, $4, $5, true, false)
			ON CONFLICT ("username") DO NOTHING
			RETURNING "id"
		`, userID, u.Username, u.RoleID, u.Name, string(hash)).Scan(&insertedID)
		if err == sql.ErrNoRows {
			// User already exists, skip user_branch insert
			continue
		}
		if err != nil {
			return err
		}
		if _, err := tx.Exec(`
			INSERT INTO "user_branch"("user_id", "branch_id")
			VALUES ($1, $2)
			ON CONFLICT DO NOTHING
		`, insertedID, u.BranchID); err != nil {
			return err
		}
	}

	// Pin pos2 to its terminal (login auto-resolve reads default_pos_id).
	if _, err := tx.Exec(`
		UPDATE "user" SET "default_pos_id" = 'POS002' WHERE "username" = 'pos2'
	`); err != nil {
		return err
	}

	// Categories
	categories := []struct {
		ID     string
		Name   string
		NameTH string
	}{
		{"CAT001", "Beverages", "เครื่องดื่ม"},
		{"CAT002", "Snacks", "ขนมขบเคี้ยว"},
		{"CAT003", "Household", "ของใช้ในบ้าน"},
	}

	for _, c := range categories {
		if _, err := tx.Exec(`
			INSERT INTO "category_master"("id", "label", "label_th")
			VALUES ($1, $2, $3)
		`, c.ID, c.Name, c.NameTH); err != nil {
			return err
		}
	}

	// Parts
	for i := 1; i <= 10; i++ {
		code := fmt.Sprintf("P%04d", i)
		barCode := fmt.Sprintf("885000%04d", i)
		categoryID := categories[(i-1)%len(categories)].ID // #nosec G602
		unitID := "pcs"

		if _, err := tx.Exec(`
			INSERT INTO "part_master"(
				"code", "bar_code", "category_id", "unit_id",
				"name", "name_th", "receipt_name", "details", "cost", "price", "image", "is_active"
			)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 10.00, 15.00, '', true)
		`, code, barCode, categoryID, unitID,
			fmt.Sprintf("Sample Part %02d", i),
			fmt.Sprintf("สินค้า ตัวอย่าง %02d", i),
			fmt.Sprintf("SAMPLE PART %02d", i),
			"Development mock item"); err != nil {
			return err
		}
	}

	// Addresses: put each part into the main store at shelf A-01, qty 100
	for i := 1; i <= 10; i++ {
		addrCode := fmt.Sprintf("ADDR%04d", i)
		partCode := fmt.Sprintf("P%04d", i)
		if _, err := tx.Exec(`
			INSERT INTO "address_master"(
				"code", "part_code", "store_id", "shelf",
				"qty", "rop", "remarks"
			)
			VALUES ($1, $2, 'main', 'A-01', 100, 20, 'Mock location - main store')
		`, addrCode, partCode); err != nil {
			return err
		}
	}

	// Stock pos1's own store (คลังสาขา pos1 = vehicle_POS001, branch 00001).
	for i := 1; i <= 10; i++ {
		addrCode := fmt.Sprintf("P1S%04d", i)
		partCode := fmt.Sprintf("P%04d", i)
		if _, err := tx.Exec(`
			INSERT INTO "address_master"(
				"code", "part_code", "store_id", "shelf",
				"qty", "rop", "remarks"
			)
			VALUES ($1, $2, 'vehicle_POS001', 'B-01', 80, 15, 'Mock location - pos1 store')
		`, addrCode, partCode); err != nil {
			return err
		}
	}

	// Stock pos2's store (คลังสาขา pos2 = store_00001, branch 00002).
	for i := 1; i <= 10; i++ {
		addrCode := fmt.Sprintf("BR2%04d", i)
		partCode := fmt.Sprintf("P%04d", i)
		if _, err := tx.Exec(`
			INSERT INTO "address_master"(
				"code", "part_code", "store_id", "shelf",
				"qty", "rop", "remarks"
			)
			VALUES ($1, $2, 'store_00001', 'C-01', 75, 15, 'Mock location - pos2 store')
		`, addrCode, partCode); err != nil {
			return err
		}
	}

	// Create a test part that exists ONLY in branch 00001 (not in branch 00000)
	// This is for testing "Item NOT in branch stores" scenario for branch 00000
	// Part P0012 (barcode 8850000012) will be ONLY in store_00001 (branch 00001)
	branch2OnlyPartCode := "P0012"
	branch2OnlyBarcode := "8850000012"
	if _, err := tx.Exec(`
		INSERT INTO "part_master"(
			"code", "bar_code", "category_id", "unit_id",
			"name", "name_th", "receipt_name", "details", "cost", "price", "image", "is_active"
		)
		VALUES ($1, $2, 'CAT001', 'pcs', 'Branch 2 Only Part', 'สินค้าสาขา 2 เท่านั้น', 'BRANCH 2 ONLY PART', 'Test item that exists only in branch 00001', 10.00, 15.00, '', true)
	`, branch2OnlyPartCode, branch2OnlyBarcode); err != nil {
		return err
	}

	// Add this part ONLY to store_00001 (branch 00001)
	if _, err := tx.Exec(`
		INSERT INTO "address_master"(
			"code", "part_code", "store_id", "shelf",
			"qty", "rop", "remarks"
		)
		VALUES ('BR2ONLY', $1, 'store_00001', 'C-03', 40, 10, 'Test location - branch 2 only')
	`, branch2OnlyPartCode); err != nil {
		return err
	}

	if err := tx.Commit(); err != nil {
		return err
	}

	log.Printf("Mock data seeding completed")

	// Seed stock count test data separately (runs even when main mock data already exists)
	if err := seedMockStockCounts(db); err != nil {
		log.Printf("Warning: failed to seed mock stock counts: %v", err)
	}

	return nil
}

func ensurePOS2MockTopology(db *sql.DB) error {
	tx, err := db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	if _, err := tx.Exec(`
		INSERT INTO "branch_setting"(
			"branch_id", "company_id", "branch_name", "branch_name_th",
			"branch_address", "branch_address_th", "phone", "email"
		) VALUES (
			'00002', '0000000000000', 'POS2 Branch', 'สาขา pos2',
			'456 Second Street', '456 ถนนที่สอง', '02-234-5678', 'branch2@example.com'
		) ON CONFLICT ("branch_id") DO NOTHING
	`); err != nil {
		return err
	}
	if _, err := tx.Exec(`
		INSERT INTO "store_master"(
			"id", "branch_id", "label", "label_th", "is_default", "location_type"
		) VALUES (
			'store_00001', '00002', 'POS2 Vehicle Stock', 'สต๊อกรถ POS2', true, 'vehicle'
		) ON CONFLICT ("id") DO UPDATE SET "location_type" = 'vehicle'
	`); err != nil {
		return err
	}
	if _, err := tx.Exec(`
		INSERT INTO "branch_store"("branch_id", "store_id", "is_default")
		VALUES ('00002', 'store_00001', true)
		ON CONFLICT ("branch_id", "store_id") DO UPDATE SET "is_default" = true
	`); err != nil {
		return err
	}

	posSecret := os.Getenv("POS_SECRET")
	if posSecret == "" {
		secretBytes := make([]byte, 32)
		if _, err := rand.Read(secretBytes); err != nil {
			return err
		}
		posSecret = hex.EncodeToString(secretBytes)
	}
	if _, err := tx.Exec(`
		INSERT INTO "pos_setting"(
			"pos_id", "branch_id", "pos_name", "pos_secret", "is_active", "vehicle_store_id"
		) VALUES ('POS002', '00002', 'POS 2', $1, true, 'store_00001')
		ON CONFLICT ("pos_id") DO UPDATE SET
			"branch_id" = EXCLUDED."branch_id",
			"vehicle_store_id" = EXCLUDED."vehicle_store_id",
			"is_active" = true
	`, posSecret); err != nil {
		return err
	}

	var pos2ID string
	err = tx.QueryRow(`SELECT "id" FROM "user" WHERE "username" = 'pos2'`).Scan(&pos2ID)
	if err == sql.ErrNoRows {
		hash, hashErr := bcrypt.GenerateFromPassword([]byte("pos123456"), bcrypt.DefaultCost)
		if hashErr != nil {
			return hashErr
		}
		pos2ID = strings.ReplaceAll(uuid.New().String(), "-", "")
		if _, err := tx.Exec(`
			INSERT INTO "user"(
				"id", "username", "role_id", "name", "password",
				"is_active", "is_superuser", "default_pos_id"
			) VALUES ($1, 'pos2', 'role.cashier', 'POS Cashier 2', $2, true, false, 'POS002')
		`, pos2ID, string(hash)); err != nil {
			return err
		}
	} else if err != nil {
		return err
	}
	if _, err := tx.Exec(`
		UPDATE "user" SET "default_pos_id" = 'POS002' WHERE "id" = $1
	`, pos2ID); err != nil {
		return err
	}
	if _, err := tx.Exec(`
		INSERT INTO "user_branch"("user_id", "branch_id")
		VALUES ($1, '00002') ON CONFLICT DO NOTHING
	`, pos2ID); err != nil {
		return err
	}

	return tx.Commit()
}
