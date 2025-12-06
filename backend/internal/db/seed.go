package db

import (
	"database/sql"
	"log"
	"strings"

	"github.com/google/uuid"
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
			OR EXISTS(SELECT 1 FROM "company_setting" LIMIT 1)
			OR EXISTS(SELECT 1 FROM "branch_setting" LIMIT 1)
			OR EXISTS(SELECT 1 FROM "pos_setting" LIMIT 1)
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
		{"perm.parts.delete", "Delete parts", "delete", "parts", "Delete part master data"},
		{"perm.bills.read", "Read bills", "read", "bills", "Read bill data"},
		{"perm.bills.write", "Write bills", "write", "bills", "Create/update bills"},
		{"perm.users.mgmt", "Manage users", "manage", "users", "Manage users and roles"},
		{"perm.users.read", "Read users", "read", "users", "Read users"},
		{"perm.users.write", "Write users", "write", "users", "Create/update users"},
		{"perm.users.delete", "Delete users", "delete", "users", "Delete users"},
		{"perm.roles.read", "Read roles", "read", "roles", "Read roles"},
		{"perm.roles.write", "Write roles", "write", "roles", "Create/update roles"},
		{"perm.roles.delete", "Delete roles", "delete", "roles", "Delete roles"},
		{"perm.permissions.read", "Read permissions", "read", "permissions", "Read permissions"},
		{"perm.permissions.write", "Write permissions", "write", "permissions", "Create/update permissions"},
		{"perm.permissions.delete", "Delete permissions", "delete", "permissions", "Delete permissions"},
		{"perm.company.read", "Read company", "read", "company", "Read company settings"},
		{"perm.company.write", "Write company", "write", "company", "Update company settings"},
		{"perm.branch.read", "Read branches", "read", "branch", "Read branch settings"},
		{"perm.branch.write", "Write branches", "write", "branch", "Create/update branch settings"},
		{"perm.branch.delete", "Delete branches", "delete", "branch", "Delete branch settings"},
		{"perm.pos.read", "Read POS", "read", "pos", "Read POS settings"},
		{"perm.pos.write", "Write POS", "write", "pos", "Create/update POS settings"},
		{"perm.pos.delete", "Delete POS", "delete", "pos", "Delete POS settings"},
		{"perm.user_branch.read", "Read user branches", "read", "user_branch", "Read user-branch associations"},
		{"perm.user_branch.write", "Write user branches", "write", "user_branch", "Create/update user-branch associations"},
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

	// Generate UUID without dashes for admin user ID
	adminID := strings.ReplaceAll(uuid.New().String(), "-", "")

	if _, err := tx.Exec(`
		INSERT INTO "user"("id", "username", "role_id", "name", "password", "is_active", "is_superuser")
		VALUES ($1, 'admin', 'role.admin', 'Administrator', $2, true, true)
	`, adminID, string(adminPasswordHash)); err != nil {
		return err
	}

	// Company setting (default company)
	if _, err := tx.Exec(`
		INSERT INTO "company_setting"(
			"tax_id", "company_name", "company_name_th", "company_address", "company_address_th",
			"phone", "email", "website", "logo_url", "tax_rate", "tax_type"
		)
		VALUES (
			'0000000000000', 'Default Company', 'บริษัทตัวอย่าง', 
			'123 Main Street', '123 ถนนหลัก', 
			'02-123-4567', 'info@example.com', 'https://example.com', '', 
			0.07, 'xvat'
		)
	`); err != nil {
		return err
	}

	// Branch setting (default branch)
	if _, err := tx.Exec(`
		INSERT INTO "branch_setting"(
			"branch_id", "company_id", "branch_name", "branch_name_th",
			"branch_address", "branch_address_th", "phone", "email"
		)
		VALUES (
			'00000', '0000000000000', 'Main Branch', 'สาขาหลัก',
			'123 Main Street', '123 ถนนหลัก', '02-123-4567', 'branch@example.com'
		)
	`); err != nil {
		return err
	}

	// POS setting (default POS)
	if _, err := tx.Exec(`
		INSERT INTO "pos_setting"("pos_id", "branch_id", "pos_name")
		VALUES ('POS001', '00000', 'POS 1')
	`); err != nil {
		return err
	}

	// store_master (updated to include branch_id)
	if _, err := tx.Exec(`
		INSERT INTO "store_master"("id", "branch_id", "label", "label_th", "is_default")
		VALUES ('main', '00000', 'Main Store', 'คลังหลัก', true)
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


