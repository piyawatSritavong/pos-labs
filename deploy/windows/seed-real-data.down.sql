-- seed-real-data.down.sql  (auto-generated)
-- Rolls back only the rows this script inserted.
-- WARNING: will fail if other tables (bills, returns, stock_count) reference these parts.

DELETE FROM "address_master" WHERE "code" ~ '^ADDR[0-9]+$';
DELETE FROM "part_master" WHERE "code" ~ '^P[0-9]+$';

DELETE FROM "category_master" WHERE "id" IN ('CAT001', 'CAT002', 'CAT003', 'CAT004', 'CAT005', 'CAT006', 'CAT007', 'CAT008', 'CAT009', 'CAT010', 'CAT011', 'CAT012', 'CAT013', 'CAT014', 'CAT015');

DELETE FROM "unit_master" WHERE "id" IN ('แผ่น', 'ชิ้น', 'ชุด', 'อัน', 'เส้น', 'กล่อง', 'ลัง', 'หลอด', 'กระป๋อง', 'ขวด', 'แกลลอน', 'ถัง', 'ปี๊บ', 'กิโล', 'ถุง', 'แผง', 'มัด', 'ดอก', 'ตัว', 'ใบ', 'คู่');

DELETE FROM "user_branch"
 WHERE "user_id" = (SELECT "id" FROM "user" WHERE "username" = 'pos1');
DELETE FROM "user" WHERE "username" = 'pos1';

