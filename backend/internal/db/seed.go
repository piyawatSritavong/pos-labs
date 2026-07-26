package db

import (
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"log"
	"os"
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
		SELECT EXISTS(SELECT 1 FROM "role" LIMIT 1)
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
		{"perm.bills.delete", "Delete bills", "delete", "bills", "Delete bills permanently"},
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
		{"perm.pos.write", "Write POS", "write", "pos", "Create/update POS settings, toggle activate"},
		{"perm.pos.delete", "Delete POS", "delete", "pos", "Delete POS settings"},
		{"perm.pos.secret", "Read POS secret", "secret", "pos", "Retrieve and refresh POS secret"},
		{"perm.user_branch.read", "Read user branches", "read", "user_branch", "Read user-branch associations"},
		{"perm.user_branch.write", "Write user branches", "write", "user_branch", "Create/update user-branch associations"},
		{"perm.promotions.read", "Read promotions", "read", "promotions", "Read promotion master data"},
		{"perm.promotions.write", "Write promotions", "write", "promotions", "Create/update promotion master data"},
		{"perm.promotions.delete", "Delete promotions", "delete", "promotions", "Delete promotion master data"},
		{"perm.addresses.read", "Read addresses", "read", "addresses", "Read address master data"},
		{"perm.addresses.write", "Write addresses", "write", "addresses", "Create/update address master data"},
		{"perm.addresses.delete", "Delete addresses", "delete", "addresses", "Delete address master data"},
		{"perm.qr_image.read", "Read QR image", "read", "qr_image", "Read QR code image"},
		{"perm.qr_image.write", "Write QR image", "write", "qr_image", "Upload/replace QR code image"},
		{"perm.reports_bill.read", "Read bill reports", "read", "reports_bill", "Export bill reports as CSV"},
		{"perm.reports_parts.read", "Read parts reports", "read", "reports_parts", "Export parts reports as CSV"},
		{"perm.reports_inventory.read", "Read inventory reports", "read", "reports_inventory", "Export inventory reports as CSV"},
		{"perm.members.read", "Read members", "read", "members", "Read member master data"},
		{"perm.members.write", "Write members", "write", "members", "Create/update member master data"},
		{"perm.members.delete", "Delete members", "delete", "members", "Delete member master data"},
		{"perm.transfers.read", "Read transfers", "read", "transfers", "Read inventory transfers"},
		{"perm.transfers.write", "Write transfers", "write", "transfers", "Create/update inventory transfers"},
		{"perm.transfers.approve", "Approve transfers", "approve", "transfers", "Approve/dispatch/cancel inventory transfers"},
		{"perm.stock_count.read", "Read stock counts", "read", "stock_count", "Read stock count records"},
		{"perm.stock_count.write", "Write stock counts", "write", "stock_count", "Create/submit stock count records"},
		{"perm.daily_close.read", "Read daily closes", "read", "daily_close", "Read daily close records"},
		{"perm.daily_close.write", "Write daily closes", "write", "daily_close", "Create daily close records"},
		{"perm.cash_reconciliation.read", "Read cash reconciliations", "read", "cash_reconciliation", "Read cash reconciliation records"},
		{"perm.cash_reconciliation.write", "Write cash reconciliations", "write", "cash_reconciliation", "Create cash reconciliation records"},
		{"perm.reports_variance.read", "Read variance reports", "read", "reports_variance", "View stock variance reports"},
	}

	for _, p := range permissions {
		if _, err := tx.Exec(`
			INSERT INTO "permission"("id", "name", "action", "resource", "detail")
			VALUES ($1, $2, $3, $4, $5)
			ON CONFLICT ("id") DO UPDATE SET
				"name" = EXCLUDED."name",
				"action" = EXCLUDED."action",
				"resource" = EXCLUDED."resource",
				"detail" = EXCLUDED."detail"
		`, p.ID, p.Name, p.Action, p.Resource, p.Detail); err != nil {
			return err
		}
	}

	// Roles
	if _, err := tx.Exec(`
		INSERT INTO "role"("id", "name", "detail")
		VALUES ('role.admin', 'Admin', 'System administrator'),
		       ('role.cashier', 'Cashier', 'Point of sale cashier'),
		       ('role.hq_manager', 'HQ Manager', 'Headquarter manager'),
		       ('role.van_staff', 'Van Staff', 'Van sales staff')
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
		"perm.branch.read",
		"perm.parts.read",
		"perm.addresses.read", // needed for POS add-item flow (stock lookup) and Addresses page
		"perm.bills.read",
		"perm.bills.write",
		"perm.promotions.read",
		"perm.qr_image.read",
		"perm.members.read",
		"perm.transfers.read",
		"perm.transfers.write",
		"perm.daily_close.read",
		"perm.daily_close.write",
		"perm.stock_count.read",
		"perm.stock_count.write",
	}
	for _, pid := range cashierPerms {
		if _, err := tx.Exec(`
			INSERT INTO "role_permission"("role_id", "permission_id")
			VALUES ('role.cashier', $1)
		`, pid); err != nil {
			return err
		}
	}

	hqManagerPerms := []string{
		"perm.branch.read",
		"perm.users.read",
		"perm.users.write",
		"perm.users.delete",
		"perm.user_branch.read",
		"perm.user_branch.write",
		"perm.parts.read",
		"perm.parts.write",
		"perm.parts.delete",
		"perm.addresses.read",
		"perm.addresses.write",
		"perm.addresses.delete",
		"perm.promotions.read",
		"perm.promotions.write",
		"perm.promotions.delete",
		"perm.members.read",
		"perm.members.write",
		"perm.members.delete",
		"perm.bills.read",
		"perm.bills.write",
		"perm.qr_image.read",
		"perm.qr_image.write",
		"perm.reports_bill.read",
		"perm.reports_parts.read",
		"perm.reports_inventory.read",
		"perm.transfers.read",
		"perm.transfers.write",
		"perm.transfers.approve",
		"perm.stock_count.read",
		"perm.daily_close.read",
		"perm.cash_reconciliation.read",
		"perm.cash_reconciliation.write",
		"perm.reports_variance.read",
	}
	for _, pid := range hqManagerPerms {
		if _, err := tx.Exec(`
			INSERT INTO "role_permission"("role_id", "permission_id")
			VALUES ('role.hq_manager', $1)
		`, pid); err != nil {
			return err
		}
	}

	vanStaffPerms := []string{
		"perm.branch.read",
		"perm.parts.read",
		"perm.bills.read",
		"perm.bills.write",
		"perm.promotions.read",
		"perm.qr_image.read",
		"perm.members.read",
		"perm.members.write",
		"perm.transfers.read",
		"perm.transfers.write",
		"perm.stock_count.read",
		"perm.stock_count.write",
		"perm.daily_close.read",
		"perm.daily_close.write",
		"perm.reports_variance.read",
	}
	for _, pid := range vanStaffPerms {
		if _, err := tx.Exec(`
			INSERT INTO "role_permission"("role_id", "permission_id")
			VALUES ('role.van_staff', $1)
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

	// POS cashier user "pos1" — created out-of-box so the Windows POS can login
	// immediately after first start, even before the real product data is loaded.
	pos1PasswordHash, err := bcrypt.GenerateFromPassword([]byte("pos123456"), bcrypt.DefaultCost)
	if err != nil {
		return err
	}
	pos1ID := strings.ReplaceAll(uuid.New().String(), "-", "")
	if _, err := tx.Exec(`
		INSERT INTO "user"("id", "username", "role_id", "name", "password", "is_active", "is_superuser")
		VALUES ($1, 'pos1', 'role.cashier', 'POS Cashier 1', $2, true, false)
	`, pos1ID, string(pos1PasswordHash)); err != nil {
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

	// Branches. The branch id matches the POS number. Each POS is its own
	// branch with its own single store:
	//   00000 สาขาหลัก  -> คลังหลัก (main)          admin / POS003
	//   00001 สาขา pos1 -> คลังสาขา pos1 (van)      pos1  / POS001
	// (00002 สาขา pos2 / คลังสาขา pos2 is added by the mock seed.)
	if _, err := tx.Exec(`
		INSERT INTO "branch_setting"(
			"branch_id", "company_id", "branch_name", "branch_name_th",
			"branch_address", "branch_address_th", "phone", "email"
		)
		VALUES
			('00000', '0000000000000', 'Main Branch', 'สาขาหลัก',
			 '123 Main Street', '123 ถนนหลัก', '02-123-4567', 'branch@example.com'),
			('00001', '0000000000000', 'POS1 Branch', 'สาขา pos1',
			 '', '', '', NULL)
	`); err != nil {
		return err
	}

	// admin is listed under the main branch; pos1 under its own branch (00001).
	if _, err := tx.Exec(`
		INSERT INTO "user_branch"("user_id", "branch_id") VALUES ($1, '00000')
	`, adminID); err != nil {
		return err
	}
	if _, err := tx.Exec(`
		INSERT INTO "user_branch"("user_id", "branch_id") VALUES ($1, '00001')
	`, pos1ID); err != nil {
		return err
	}

	// store_master: main warehouse (admin) + pos1's own store. Each is the
	// default store of its branch and the stock source for sales at that POS.
	if _, err := tx.Exec(`
		INSERT INTO "store_master"("id", "branch_id", "label", "label_th", "is_default")
		VALUES
			('main', '00000', 'Main Warehouse', 'คลังหลัก', true),
			('vehicle_POS001', '00001', 'POS1 Store', 'คลังสาขา pos1', true)
	`); err != nil {
		return err
	}

	// branch_store (link branch to its default store)
	if _, err := tx.Exec(`
		INSERT INTO "branch_store"("branch_id", "store_id", "is_default")
		VALUES
			('00000', 'main', true),
			('00001', 'vehicle_POS001', true)
	`); err != nil {
		return err
	}

	// POS setting (default POS). The pos_secret comes from the POS_SECRET env var
	// if set (so .env on the Windows POS controls it and Flutter --dart-define can
	// match), otherwise we fall back to a fresh random 32-byte hex for dev.
	posSecret := os.Getenv("POS_SECRET")
	if posSecret == "" {
		posSecretBytes := make([]byte, 32)
		if _, err := rand.Read(posSecretBytes); err != nil {
			return err
		}
		posSecret = hex.EncodeToString(posSecretBytes)
	}

	// Stock wiring: each POS sells from / counts its branch's own store —
	//   POS001 (pos1)  -> คลังสาขา pos1 (vehicle_POS001, branch 00001)
	//   POS003 (admin) -> คลังหลัก (main, branch 00000)
	//   POS002 (pos2, mock seed) -> คลังสาขา pos2 (store_00001, branch 00002)
	if _, err := tx.Exec(`
		INSERT INTO "pos_setting"("pos_id", "branch_id", "pos_name", "pos_secret", "is_active", "vehicle_store_id")
		VALUES ($1, $2, $3, $4, $5, $6)
	`, "POS001", "00001", "POS 1", posSecret, true, "vehicle_POS001"); err != nil {
		return err
	}

	// Admin's own terminal: the backoffice "ขายสินค้า (POS)" page sells as
	// POS003 so its bills/mirror/customer display never collide with pos1.
	if _, err := tx.Exec(`
		INSERT INTO "pos_setting"("pos_id", "branch_id", "pos_name", "pos_secret", "is_active", "vehicle_store_id")
		VALUES ($1, $2, $3, $4, $5, $6)
	`, "POS003", "00000", "POS สำนักงาน", posSecret, true, "main"); err != nil {
		return err
	}

	// Pin each account to its terminal (used by login auto-resolve).
	if _, err := tx.Exec(`
		UPDATE "user" SET "default_pos_id" = 'POS003' WHERE "username" = 'admin'
	`); err != nil {
		return err
	}
	if _, err := tx.Exec(`
		UPDATE "user" SET "default_pos_id" = 'POS001' WHERE "username" = 'pos1'
	`); err != nil {
		return err
	}

	// unit_master
	if _, err := tx.Exec(`
		INSERT INTO "unit_master"("id", "label", "label_th")
		VALUES ('pcs', 'PCS', 'ชิ้น'),
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
