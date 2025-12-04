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
			VALUES ($1, $2, 'main', 'A-01', 100, 10, 200, 20, 'Mock location')
		`, addrCode, partCode); err != nil {
			return err
		}
	}

	if err := tx.Commit(); err != nil {
		return err
	}

	log.Printf("Mock data seeding completed")
	return nil
}


