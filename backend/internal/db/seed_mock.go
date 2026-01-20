package db

import (
	"database/sql"
	"fmt"
	"log"
)

// SeedMockData inserts development-only mock data for categories, parts, and addresses.
// If any of these tables already have data, seeding is skipped entirely (all-or-nothing).
func SeedMockData(db *sql.DB) error {
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
		log.Printf("Mock data already exists, skipping seeding")
		return nil
	}

	log.Printf("Seeding mock data for development (categories, parts, addresses)")

	tx, err := db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	// Add another branch (00001)
	if _, err := tx.Exec(`
		INSERT INTO "branch_setting"(
			"branch_id", "company_id", "branch_name", "branch_name_th",
			"branch_address", "branch_address_th", "phone", "email"
		)
		VALUES (
			'00001', '0000000000000', 'Second Branch', 'สาขาที่สอง',
			'456 Second Street', '456 ถนนที่สอง', '02-234-5678', 'branch2@example.com'
		)
		ON CONFLICT ("branch_id") DO NOTHING
	`); err != nil {
		return err
	}

	// Create tmp_store for branch 00000
	if _, err := tx.Exec(`
		INSERT INTO "store_master"("id", "branch_id", "label", "label_th", "is_default")
		VALUES ('tmp_store', '00000', 'Temporary Store', 'คลังชั่วคราว', false)
		ON CONFLICT ("id") DO NOTHING
	`); err != nil {
		return err
	}

	// Create another non-default store for testing "no default store" scenario
	if _, err := tx.Exec(`
		INSERT INTO "store_master"("id", "branch_id", "label", "label_th", "is_default")
		VALUES ('no_default_store', '00000', 'No Default Store', 'คลังไม่มีค่าเริ่มต้น', false)
		ON CONFLICT ("id") DO NOTHING
	`); err != nil {
		return err
	}

	// Link branch 00000 to tmp_store via branch_store
	if _, err := tx.Exec(`
		INSERT INTO "branch_store"("branch_id", "store_id", "is_default")
		VALUES ('00000', 'tmp_store', false)
		ON CONFLICT ("branch_id", "store_id") DO NOTHING
	`); err != nil {
		return err
	}

	// Link branch 00000 to no_default_store (non-default)
	if _, err := tx.Exec(`
		INSERT INTO "branch_store"("branch_id", "store_id", "is_default")
		VALUES ('00000', 'no_default_store', false)
		ON CONFLICT ("branch_id", "store_id") DO NOTHING
	`); err != nil {
		return err
	}

	// Create a store for branch 00001
	if _, err := tx.Exec(`
		INSERT INTO "store_master"("id", "branch_id", "label", "label_th", "is_default")
		VALUES ('store_00001', '00001', 'Second Branch Store', 'คลังสาขาที่สอง', true)
		ON CONFLICT ("id") DO NOTHING
	`); err != nil {
		return err
	}

	// Link branch 00001 to its store
	if _, err := tx.Exec(`
		INSERT INTO "branch_store"("branch_id", "store_id", "is_default")
		VALUES ('00001', 'store_00001', true)
		ON CONFLICT ("branch_id", "store_id") DO NOTHING
	`); err != nil {
		return err
	}

	// Categories
	categories := []struct {
    ID   string
    Name string
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

	if len(categories) == 0 {
			return fmt.Errorf("no categories")
	}

  // Parts
  for i := 1; i <= 10; i++ {
    code := fmt.Sprintf("P%04d", i)
    barCode := fmt.Sprintf("885000%04d", i)
    categoryID := categories[(i-1)%len(categories)].ID
    unitID := "pcs"

    if _, err := tx.Exec(`
      INSERT INTO "part_master"(
        "code", "bar_code", "category_id", "unit_id",
        "name", "name_th", "details", "cost", "price", "image", "is_active"
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, 10.00, 15.00, '', true)
    `, code, barCode, categoryID, unitID,
      fmt.Sprintf("Sample Part %02d", i),
      fmt.Sprintf("สินค้า ตัวอย่าง %02d", i),
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
				"qty", "min", "max", "rop", "remarks"
			)
			VALUES ($1, $2, 'main', 'A-01', 100, 10, 200, 20, 'Mock location - main store')
		`, addrCode, partCode); err != nil {
			return err
		}
	}

	// Add same parts (same barcode) to tmp_store for testing
	// Parts 1-5 will be in both main and tmp_store
	for i := 1; i <= 5; i++ {
		addrCode := fmt.Sprintf("TMP%04d", i)
		partCode := fmt.Sprintf("P%04d", i)
		if _, err := tx.Exec(`
			INSERT INTO "address_master"(
				"code", "part_code", "store_id", "shelf",
				"qty", "min", "max", "rop", "remarks"
			)
			VALUES ($1, $2, 'tmp_store', 'B-01', 50, 5, 100, 10, 'Mock location - tmp store')
		`, addrCode, partCode); err != nil {
			return err
		}
	}

	// Add some parts to branch 00001's store
	for i := 6; i <= 10; i++ {
		addrCode := fmt.Sprintf("BR2%04d", i)
		partCode := fmt.Sprintf("P%04d", i)
		if _, err := tx.Exec(`
			INSERT INTO "address_master"(
				"code", "part_code", "store_id", "shelf",
				"qty", "min", "max", "rop", "remarks"
			)
			VALUES ($1, $2, 'store_00001', 'C-01', 75, 10, 150, 15, 'Mock location - branch 2')
		`, addrCode, partCode); err != nil {
			return err
		}
	}

	// Create a test part that exists in multiple stores but NONE are default
	// This is for testing "no default store" error scenario
	// Part P0011 (barcode 8850000011) will be in both tmp_store and no_default_store (both non-default)
	testPartCode := "P0011"
	testBarcode := "8850000011"
	if _, err := tx.Exec(`
		INSERT INTO "part_master"(
			"code", "bar_code", "category_id", "unit_id",
			"name", "name_th", "details", "cost", "price", "image", "is_active"
		)
		VALUES ($1, $2, 'CAT001', 'pcs', 'Test Part No Default', 'สินค้าทดสอบไม่มีค่าเริ่มต้น', 'Test item for no default store scenario', 10.00, 15.00, '', true)
	`, testPartCode, testBarcode); err != nil {
		return err
	}

	// Add this part to tmp_store (non-default)
	if _, err := tx.Exec(`
		INSERT INTO "address_master"(
			"code", "part_code", "store_id", "shelf",
			"qty", "min", "max", "rop", "remarks"
		)
		VALUES ('TMP0011', $1, 'tmp_store', 'B-02', 30, 5, 100, 10, 'Test location - tmp store (no default)')
	`, testPartCode); err != nil {
		return err
	}

	// Add same part to no_default_store (also non-default)
	if _, err := tx.Exec(`
		INSERT INTO "address_master"(
			"code", "part_code", "store_id", "shelf",
			"qty", "min", "max", "rop", "remarks"
		)
		VALUES ('NDS0011', $1, 'no_default_store', 'C-02', 25, 5, 100, 10, 'Test location - no default store')
	`, testPartCode); err != nil {
		return err
	}

	// Create a test part that exists ONLY in branch 00001 (not in branch 00000)
	// This is for testing "Item NOT in branch stores" scenario for branch 00000
	// Part P0012 (barcode 8850000012) will be ONLY in store_00001 (branch 00001)
	branch2OnlyPartCode := "P0012"
	branch2OnlyBarcode := "8850000012"
	if _, err := tx.Exec(`
		INSERT INTO "part_master"(
			"code", "bar_code", "category_id", "unit_id",
			"name", "name_th", "details", "cost", "price", "image", "is_active"
		)
		VALUES ($1, $2, 'CAT001', 'pcs', 'Branch 2 Only Part', 'สินค้าสาขา 2 เท่านั้น', 'Test item that exists only in branch 00001', 10.00, 15.00, '', true)
	`, branch2OnlyPartCode, branch2OnlyBarcode); err != nil {
		return err
	}

	// Add this part ONLY to store_00001 (branch 00001)
	if _, err := tx.Exec(`
		INSERT INTO "address_master"(
			"code", "part_code", "store_id", "shelf",
			"qty", "min", "max", "rop", "remarks"
		)
		VALUES ('BR2ONLY', $1, 'store_00001', 'C-03', 40, 5, 100, 10, 'Test location - branch 2 only')
	`, branch2OnlyPartCode); err != nil {
		return err
	}

	if err := tx.Commit(); err != nil {
		return err
	}

	log.Printf("Mock data seeding completed")
	return nil
}


