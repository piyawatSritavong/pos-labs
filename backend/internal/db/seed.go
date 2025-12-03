package db

import (
	"database/sql"
	"log"

	"golang.org/x/crypto/bcrypt"
)

// SeedCoreData inserts initial permissions, roles, role-permissions, and an admin user.
// If any of these tables already have data, seeding is skipped entirely (all-or-nothing).
func SeedCoreData(db *sql.DB) error {
	// Check if any core data already exists
	var exists bool
	err := db.QueryRow(`
		SELECT EXISTS(SELECT 1 FROM "permission" LIMIT 1)
			OR EXISTS(SELECT 1 FROM "role" LIMIT 1)
			OR EXISTS(SELECT 1 FROM "user" LIMIT 1)
			OR EXISTS(SELECT 1 FROM "store_master" LIMIT 1)
			OR EXISTS(SELECT 1 FROM "unit_master" LIMIT 1)
	`).Scan(&exists)
	if err != nil {
		return err
	}
	if exists {
		log.Printf("Core data already exists, skipping seeding")
		return nil
	}

	log.Printf("Seeding core data (permissions, roles, users)")

	tx, err := db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	// Permissions
	permissions := []struct {
		ID       string
		Name     string
		Action   string
		Resource string
		Detail   string
	}{
		{"perm.parts.read", "Read parts", "read", "parts", "Read part master data"},
		{"perm.parts.write", "Write parts", "write", "parts", "Create/update part master data"},
		{"perm.bills.read", "Read bills", "read", "bills", "Read bill data"},
		{"perm.bills.write", "Write bills", "write", "bills", "Create/update bills"},
		{"perm.users.mgmt", "Manage users", "manage", "users", "Manage users and roles"},
	}

	for _, p := range permissions {
		if _, err := tx.Exec(`
			INSERT INTO "permission"("id", "name", "action", "resource", "detail")
			VALUES ($1, $2, $3, $4, $5)
		`, p.ID, p.Name, p.Action, p.Resource, p.Detail); err != nil {
			return err
		}
	}

	// Roles
	if _, err := tx.Exec(`
		INSERT INTO "role"("id", "name", "detail")
		VALUES ('role.admin', 'Admin', 'System administrator'),
		       ('role.cashier', 'Cashier', 'Point of sale cashier')
	`); err != nil {
		return err
	}

	// Role-permissions (admin gets all, cashier gets billing and read parts)
	if _, err := tx.Exec(`
		INSERT INTO "role_permission"("role_id", "permission_id")
		SELECT 'role.admin', p.id FROM "permission" p
	`); err != nil {
		return err
	}

	cashierPerms := []string{
		"perm.parts.read",
		"perm.bills.read",
		"perm.bills.write",
	}
	for _, pid := range cashierPerms {
		if _, err := tx.Exec(`
			INSERT INTO "role_permission"("role_id", "permission_id")
			VALUES ('role.cashier', $1)
		`, pid); err != nil {
			return err
		}
	}

	// Admin user
	adminPasswordHash, err := bcrypt.GenerateFromPassword([]byte("admin123"), bcrypt.DefaultCost)
	if err != nil {
		return err
	}

	if _, err := tx.Exec(`
		INSERT INTO "user"("id", "username", "role_id", "name", "password", "is_active")
		VALUES ('admin', 'admin', 'role.admin', 'Administrator', $1, true)
	`, string(adminPasswordHash)); err != nil {
		return err
	}

	// store_master
	if _, err := tx.Exec(`
		INSERT INTO "store_master"("id", "label", "label_th", "is_default")
		VALUES ('main', 'Main Store', 'คลังหลัก', true)
	`); err != nil {
		return err
	}

	// unit_master
	if _, err := tx.Exec(`
		INSERT INTO "unit_master"("id", "label", "label_th")
		VALUES ('pcs', 'PCS', 'หน่วย'),
		       ('box', 'BOX', 'กล่อง'),
		       ('case', 'CASE', 'กล่อง'),
		       ('set', 'SET', 'ชุด'),
		       ('pair', 'PAIR', 'คู่'),
		       ('roll', 'ROLL', 'ม้วน'),
		       ('sheet', 'SHEET', 'แผ่น')
	`); err != nil {
		return err
	}

	if err := tx.Commit(); err != nil {
		return err
	}

	log.Printf("Core data seeding completed")
	return nil
}


