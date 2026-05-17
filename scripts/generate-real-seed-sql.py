#!/usr/bin/env python3
"""
Generate deploy/windows/seed-real-data.sql from the spreadsheet at
~/Downloads/real-data-stock.xlsx (override with --xlsx).

The generated SQL is a STANDALONE script the user copies to the Windows POS
machine and runs with psql AFTER backend's first start (which creates the
schema and seeds permissions/admin/pos1/company/branch/POS via SeedCoreData).

The SQL adds:
  - role.cashier (if missing — SeedCoreData also creates it; ON CONFLICT safe)
  - pos1 user (also seeded by SeedCoreData; ON CONFLICT safe so re-running is OK)
  - user_branch link for pos1 → '00000'
  - 15 categories (CAT001-CAT015) from sheet "ประเภท"
  - 21 Thai units (id = Thai unit name) — added on top of the 7 default units
  - UPDATE pos_setting.pos_secret to 'windows-pos-default-secret' (match Flutter build)
  - ~1,566 part_master rows (codes P0001+)
  - ~1,566 address_master rows (ADDR0001+, store_id='main', qty=100)

All INSERTs use ON CONFLICT DO NOTHING so the script is safe to re-run.
Re-run this generator whenever the spreadsheet changes.

Usage:
    python3 scripts/generate-real-seed-sql.py
    python3 scripts/generate-real-seed-sql.py --xlsx /path/to/real-data-stock.xlsx
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

try:
    from openpyxl import load_workbook
except ImportError:
    print("ERROR: openpyxl not installed. Run: pip3 install openpyxl", file=sys.stderr)
    sys.exit(1)


# bcrypt hash of "pos123456" — pre-computed (Go bcrypt accepts $2a$/$2b$).
POS1_PASSWORD_HASH = "$2b$12$XvFVPxGNgNfUiAWKMISm9upd1dXyKE7FY5CeWhawbWnGVnkCSMFPu"
POS1_USER_ID = "pos1-user-fixed-id-00000000000001"
POS_SECRET_FIXED = "windows-pos-default-secret"
DEFAULT_STORE_ID = "main"
DEFAULT_BRANCH_ID = "00000"
DEFAULT_STARTING_QTY = 100

CATEGORY_ENGLISH = {
    "CAT001": "Plywood",
    "CAT002": "Trim Wood",
    "CAT003": "Frame Wood",
    "CAT004": "Laminate",
    "CAT005": "Paint",
    "CAT006": "Chemicals",
    "CAT007": "Sandpaper",
    "CAT008": "Fitting",
    "CAT009": "Hardware",
    "CAT010": "Fasteners",
    "CAT011": "Tools",
    "CAT012": "Handles",
    "CAT013": "Bulk Sale",
    "CAT014": "Misc",
    "CAT015": "Small Parts",
}

THAI_UNIT_TO_ENGLISH = {
    "แผ่น": "sheet",
    "ชิ้น": "piece",
    "ชุด": "set",
    "อัน": "unit",
    "เส้น": "strip",
    "กล่อง": "box",
    "ลัง": "case",
    "หลอด": "tube",
    "กระป๋อง": "can",
    "ขวด": "bottle",
    "แกลลอน": "gallon",
    "ถัง": "bucket",
    "ปี๊บ": "tin",
    "กิโล": "kg",
    "ถุง": "bag",
    "แผง": "panel",
    "มัด": "bundle",
    "ดอก": "bit",
    "ตัว": "unit",
    "ใบ": "leaf",
    "คู่": "pair",
}


def sql_quote(value):
    """Render a Python value as a SQL literal."""
    if value is None:
        return "NULL"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return f"{value}"
    s = str(value).replace("'", "''")
    return f"'{s}'"


def normalize_barcode(raw):
    if raw is None:
        return None
    if isinstance(raw, float):
        if raw != raw:
            return None
        return str(int(raw))
    s = str(raw).strip()
    return s or None


def read_products(xlsx_path: Path):
    wb = load_workbook(xlsx_path, data_only=True, read_only=True)
    sheet_name = "สินค้า"
    if sheet_name not in wb.sheetnames:
        print(f"ERROR: sheet '{sheet_name}' not found in {xlsx_path}", file=sys.stderr)
        sys.exit(1)
    ws = wb[sheet_name]

    rows = list(ws.iter_rows(values_only=True))
    if not rows:
        print(f"ERROR: sheet '{sheet_name}' is empty", file=sys.stderr)
        sys.exit(1)

    products = []
    last_category = None
    skipped = 0
    warnings = []
    for idx, row in enumerate(rows[1:], start=2):
        if not row:
            continue
        padded = list(row) + [None] * (7 - len(row)) if len(row) < 7 else row
        cat_id = padded[0]
        unit_th = padded[1]
        name_th = padded[2]
        details = padded[3]
        price = padded[4]
        min_qty = padded[5]
        bar_code = padded[6]

        if not name_th or str(name_th).strip() == "":
            continue

        if not cat_id or str(cat_id).strip() == "":
            if last_category:
                cat_id = last_category
                warnings.append(f"row {idx}: blank category, inheriting {last_category}")
            else:
                warnings.append(f"row {idx}: blank category and no previous — skipping")
                skipped += 1
                continue
        else:
            cat_id = str(cat_id).strip()
            last_category = cat_id

        if not unit_th or str(unit_th).strip() == "":
            warnings.append(f"row {idx}: blank unit, defaulting to 'ชิ้น'")
            unit_th = "ชิ้น"
        else:
            unit_th = str(unit_th).strip()

        if unit_th not in THAI_UNIT_TO_ENGLISH:
            warnings.append(f"row {idx}: unknown unit '{unit_th}', adding to unit_master")
            THAI_UNIT_TO_ENGLISH[unit_th] = unit_th

        if cat_id not in CATEGORY_ENGLISH:
            warnings.append(f"row {idx}: unknown category '{cat_id}', skipping")
            skipped += 1
            continue

        products.append(
            {
                "name_th": str(name_th).strip(),
                "details": str(details).strip() if details else None,
                "category_id": cat_id,
                "unit_id": unit_th,
                "price": float(price) if price is not None else 0.0,
                "min_qty": int(min_qty) if min_qty is not None else 0,
                "bar_code": normalize_barcode(bar_code),
            }
        )
    return products, skipped, warnings


def build_up_sql(products):
    out = []
    out.append("-- =============================================================================")
    out.append("-- seed-real-data.sql  (auto-generated by scripts/generate-real-seed-sql.py)")
    out.append("--")
    out.append("-- Standalone seed for the production Windows 10 POS — run AFTER backend's")
    out.append("-- first start (which created the schema and core data via SeedCoreData).")
    out.append("--")
    out.append("-- How to run (on Windows, after start-pos.bat has run at least once):")
    out.append("--     psql -h 127.0.0.1 -U posuser -d poslabs -f seed-real-data.sql")
    out.append("--   …or just double-click load-real-data.bat in the same folder.")
    out.append("--")
    out.append("-- This script adds:")
    out.append("--   0. UTF-8 client_encoding + UPDATE-NULL repair for any pre-existing data")
    out.append("--   1. role.cashier + pos1 user + user_branch link + addresses:read perm")
    out.append("--   2. 15 Thai categories (CAT001-CAT015)")
    out.append("--   3. 21 Thai units (id = Thai name, e.g. 'แผ่น') — atop the 7 SeedCoreData units")
    out.append("--   4. Fixed pos_secret for POS001 (must match Flutter --dart-define=POS_SECRET)")
    out.append(f"--   5. {len(products)} part_master rows from xlsx Sheet สินค้า")
    out.append(f"--   6. {len(products)} address_master rows (store_id='main', qty={DEFAULT_STARTING_QTY})")
    out.append("--")
    out.append("-- All inserts use ON CONFLICT DO NOTHING so this script is safe to re-run.")
    out.append("-- =============================================================================")
    out.append("")

    # Ensure psql talks UTF-8 to the server regardless of OS code page.
    # Without this, Windows psql in Thai locale defaults to WIN874 and Thai text
    # bytes get rejected with "invalid byte sequence for encoding".
    out.append("SET client_encoding TO 'UTF8';")
    out.append("")

    # Repair pass: replace any NULL values left by an older version of this
    # script with empty/zero defaults. The Go repository code (Address.Shelf,
    # PartSummary.BarCode, etc.) Scans into plain string/int — NULL columns
    # would cause `sql.Scan` to fail and the handler to return 500.
    out.append("-- 0) Repair NULL → default for any rows seeded by older scripts")
    out.append("UPDATE \"part_master\"    SET \"bar_code\" = '' WHERE \"bar_code\" IS NULL;")
    out.append("UPDATE \"part_master\"    SET \"details\"  = '' WHERE \"details\"  IS NULL;")
    out.append("UPDATE \"part_master\"    SET \"cost\"     = 0  WHERE \"cost\"     IS NULL;")
    out.append("UPDATE \"address_master\" SET \"shelf\"    = '' WHERE \"shelf\"    IS NULL;")
    out.append(f"UPDATE \"address_master\" SET \"qty\"      = {DEFAULT_STARTING_QTY} WHERE \"qty\" IS NULL;")
    out.append("UPDATE \"address_master\" SET \"max\"      = 0  WHERE \"max\"      IS NULL;")
    out.append("UPDATE \"address_master\" SET \"remarks\"  = '' WHERE \"remarks\"  IS NULL;")
    out.append("")

    out.append("-- 1) role.cashier + pos1 user")
    out.append("INSERT INTO \"role\" (\"id\", \"name\", \"detail\") VALUES")
    out.append("    ('role.cashier', 'Cashier', 'Point of sale cashier')")
    out.append("ON CONFLICT (\"id\") DO NOTHING;")
    out.append("")
    out.append("INSERT INTO \"user\" (\"id\", \"username\", \"role_id\", \"name\", \"password\", \"is_active\", \"is_superuser\")")
    out.append("VALUES (")
    out.append(f"    {sql_quote(POS1_USER_ID)},")
    out.append("    'pos1',")
    out.append("    'role.cashier',")
    out.append("    'POS Cashier 1',")
    out.append(f"    {sql_quote(POS1_PASSWORD_HASH)},  -- bcrypt('pos123456')")
    out.append("    true,")
    out.append("    false")
    out.append(")")
    out.append("ON CONFLICT (\"username\") DO NOTHING;")
    out.append("")
    out.append("INSERT INTO \"user_branch\" (\"user_id\", \"branch_id\")")
    out.append("SELECT u.\"id\", '00000'")
    out.append("FROM \"user\" u")
    out.append("WHERE u.\"username\" = 'pos1'")
    out.append("ON CONFLICT DO NOTHING;")
    out.append("")
    # role.cashier in seed.go does not include addresses:read — but the POS
    # add-item flow + Addresses page in backoffice both need it. Grant via
    # ON CONFLICT-safe INSERT so existing DBs get the missing permission.
    out.append("-- Grant addresses:read to cashier (missing in older seed.go)")
    out.append("INSERT INTO \"role_permission\" (\"role_id\", \"permission_id\") VALUES")
    out.append("    ('role.cashier', 'perm.addresses.read')")
    out.append("ON CONFLICT DO NOTHING;")
    out.append("")

    out.append("-- 2) Categories (xlsx Sheet ประเภท)")
    out.append("INSERT INTO \"category_master\" (\"id\", \"label\", \"label_th\") VALUES")
    cat_lines = []
    sheet_cat_th = {
        "CAT001": "ไม้อัด",
        "CAT002": "ไม้คิ้ว",
        "CAT003": "ไม้โครง",
        "CAT004": "ลามิเนต",
        "CAT005": "สี",
        "CAT006": "เคมีภัณฑ์",
        "CAT007": "กระดาษทราย",
        "CAT008": "อุปกรณ์ฟิตติ้ง",
        "CAT009": "อุปกรณ์ฮาร์ดแวร์",
        "CAT010": "ลูกแม็กซ์ สกรู เราเตอร์ ตะปู",
        "CAT011": "เครื่องมือช่าง",
        "CAT012": "มือจับ",
        "CAT013": "แบ่งขาย",
        "CAT014": "จิปาถะ",
        "CAT015": "ของชิ้นเล็ก",
    }
    for cat_id, en in CATEGORY_ENGLISH.items():
        th = sheet_cat_th.get(cat_id, en)
        cat_lines.append(f"    ({sql_quote(cat_id)}, {sql_quote(en)}, {sql_quote(th)})")
    out.append(",\n".join(cat_lines))
    out.append("ON CONFLICT (\"id\") DO NOTHING;")
    out.append("")

    out.append("-- 3) Thai units (id = Thai name)")
    out.append("INSERT INTO \"unit_master\" (\"id\", \"label\", \"label_th\") VALUES")
    unit_lines = []
    for thai, en in THAI_UNIT_TO_ENGLISH.items():
        unit_lines.append(f"    ({sql_quote(thai)}, {sql_quote(en)}, {sql_quote(thai)})")
    out.append(",\n".join(unit_lines))
    out.append("ON CONFLICT (\"id\") DO NOTHING;")
    out.append("")

    out.append("-- 4) Fix pos_secret for POS001 to a known value")
    out.append("--    (must match Flutter --dart-define=POS_SECRET=windows-pos-default-secret)")
    out.append("UPDATE \"pos_setting\"")
    out.append(f"   SET \"pos_secret\" = {sql_quote(POS_SECRET_FIXED)}")
    out.append("   WHERE \"pos_id\" = 'POS001';")
    out.append("")

    # NOTE: empty strings ('') and zeros (0) used instead of NULL because the Go
    # repository code (PartSummary.BarCode / Address.Shelf / Max / Remarks) Scans
    # into plain string/int — NULL columns would cause sql.Scan to fail.
    out.append(f"-- 5) {len(products)} parts from xlsx Sheet สินค้า")
    out.append("INSERT INTO \"part_master\" (\"code\", \"bar_code\", \"category_id\", \"unit_id\", \"name\", \"name_th\", \"details\", \"cost\", \"price\", \"image\", \"is_active\") VALUES")
    part_lines = []
    for i, p in enumerate(products, start=1):
        code = f"P{i:04d}"
        bc = sql_quote(p["bar_code"] or "")     # '' instead of NULL
        cat = sql_quote(p["category_id"])
        unit = sql_quote(p["unit_id"])
        name = sql_quote(p["name_th"])
        details = sql_quote(p["details"] or "") # '' instead of NULL
        price = f"{p['price']:.2f}"
        part_lines.append(
            f"    ({sql_quote(code)}, {bc}, {cat}, {unit}, {name}, {name}, {details}, 0, {price}, '', true)"
        )
    out.append(",\n".join(part_lines))
    out.append("ON CONFLICT (\"code\") DO NOTHING;")
    out.append("")

    out.append(f"-- 6) {len(products)} addresses (one per part, store_id='main')")
    out.append("INSERT INTO \"address_master\" (\"code\", \"part_code\", \"store_id\", \"shelf\", \"qty\", \"min\", \"max\", \"rop\", \"remarks\") VALUES")
    addr_lines = []
    for i, p in enumerate(products, start=1):
        code = f"ADDR{i:04d}"
        part_code = f"P{i:04d}"
        min_v = p["min_qty"]
        # shelf='', max=0, remarks='' instead of NULL — see note above
        addr_lines.append(
            f"    ({sql_quote(code)}, {sql_quote(part_code)}, {sql_quote(DEFAULT_STORE_ID)}, '', {DEFAULT_STARTING_QTY}, {min_v}, 0, {min_v}, '')"
        )
    out.append(",\n".join(addr_lines))
    out.append("ON CONFLICT (\"code\") DO NOTHING;")
    out.append("")
    out.append("-- Repair older real-data loads where generated addresses were inserted with qty=0.")
    out.append("-- Do not reset addresses that already appear in bill details.")
    out.append("UPDATE \"address_master\" a")
    out.append(f"   SET \"qty\" = {DEFAULT_STARTING_QTY}")
    out.append(" WHERE a.\"code\" ~ '^ADDR[0-9]+$'")
    out.append(f"   AND a.\"store_id\" = {sql_quote(DEFAULT_STORE_ID)}")
    out.append("   AND COALESCE(a.\"qty\", 0) = 0")
    out.append("   AND NOT EXISTS (")
    out.append("       SELECT 1")
    out.append("         FROM \"bill_item_detail\" bid")
    out.append("        WHERE bid.\"address_code\" = a.\"code\"")
    out.append("   );")
    out.append("")

    return "\n".join(out) + "\n"


def build_down_sql(products):
    out = []
    out.append("-- seed-real-data.down.sql  (auto-generated)")
    out.append("-- Rolls back only the rows this script inserted.")
    out.append("-- WARNING: will fail if other tables (bills, returns, stock_count) reference these parts.")
    out.append("")
    out.append("DELETE FROM \"address_master\" WHERE \"code\" ~ '^ADDR[0-9]+$';")
    out.append("DELETE FROM \"part_master\" WHERE \"code\" ~ '^P[0-9]+$';")
    out.append("")
    cats = ", ".join(sql_quote(c) for c in CATEGORY_ENGLISH)
    out.append(f"DELETE FROM \"category_master\" WHERE \"id\" IN ({cats});")
    out.append("")
    units = ", ".join(sql_quote(u) for u in THAI_UNIT_TO_ENGLISH)
    out.append(f"DELETE FROM \"unit_master\" WHERE \"id\" IN ({units});")
    out.append("")
    out.append("DELETE FROM \"user_branch\"")
    out.append(" WHERE \"user_id\" = (SELECT \"id\" FROM \"user\" WHERE \"username\" = 'pos1');")
    out.append("DELETE FROM \"user\" WHERE \"username\" = 'pos1';")
    out.append("")
    return "\n".join(out) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--xlsx",
        default=str(Path.home() / "Downloads" / "real-data-stock.xlsx"),
        help="Path to real-data-stock.xlsx",
    )
    parser.add_argument(
        "--out-dir",
        default=str(Path(__file__).parent.parent / "deploy" / "windows"),
        help="Output directory for the .sql files",
    )
    args = parser.parse_args()

    xlsx = Path(args.xlsx)
    if not xlsx.exists():
        print(f"ERROR: xlsx not found at {xlsx}", file=sys.stderr)
        sys.exit(1)

    products, skipped, warnings = read_products(xlsx)
    print(f"Parsed {len(products)} products from {xlsx} (skipped {skipped})")
    if warnings:
        print("First 10 warnings:")
        for w in warnings[:10]:
            print(" ", w)
        if len(warnings) > 10:
            print(f"  ... and {len(warnings) - 10} more")

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    up_path = out_dir / "seed-real-data.sql"
    down_path = out_dir / "seed-real-data.down.sql"

    up_sql = build_up_sql(products)
    down_sql = build_down_sql(products)

    up_path.write_text(up_sql, encoding="utf-8")
    down_path.write_text(down_sql, encoding="utf-8")

    up_size = up_path.stat().st_size
    down_size = down_path.stat().st_size
    print(f"Wrote {up_path} ({up_size:,} bytes)")
    print(f"Wrote {down_path} ({down_size:,} bytes)")


if __name__ == "__main__":
    main()
