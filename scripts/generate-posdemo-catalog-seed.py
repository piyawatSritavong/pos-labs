#!/usr/bin/env python3
"""Generate the Supabase product/inventory replacement seed from the Thai XLSX.

The workbook is an XLSX file with the product export in columns A-L and the
inventory export in columns M-U. Rows 3-14 are examples and row 15 is an
instruction row; employee-entered data starts at row 16.

Only Python's standard library is used so the generator works in CI and on a
fresh developer machine without openpyxl.
"""

from __future__ import annotations

import argparse
import re
import sys
from collections import Counter
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path
from xml.etree import ElementTree as ET
from zipfile import ZipFile


MAIN_NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
M = f"{{{MAIN_NS}}}"

FIRST_DATA_ROW = 16
EXPECTED_COLUMNS = 21
DEFAULT_UNIT_ID = "pcs"

# The workbook uses employee-facing names. These are the existing store IDs in
# this branch's production schema.
STORE_ALIASES = {
    "ร้าน": "main",
    "main": "main",
    "รถ1": "vehicle_POS001",
    "รถ 1": "vehicle_POS001",
    "รถคันที่ 1": "vehicle_POS001",
    "pos1": "vehicle_POS001",
    "รถ2": "store_00001",
    "รถ 2": "store_00001",
    "รถคันที่ 2": "store_00001",
    "pos2": "store_00001",
}

# Short, conservative mappings for receipt names. Any name that cannot be
# represented meaningfully in ASCII falls back to "ITEM Pxxxx".
RECEIPT_TERMS = (
    ("ตะปูสังกะสี", "GALV NAIL"),
    ("ตะปู", "NAIL"),
    ("สายไฟ", "WIRE"),
    ("ปลั๊ก", "PLUG"),
    ("สวิตช์", "SWITCH"),
    ("หลอดไฟ", "LAMP"),
    ("หลอดนีออน", "FLUORESCENT"),
    ("กาว", "GLUE"),
    ("เทป", "TAPE"),
    ("เชือก", "ROPE"),
    ("ถุงมือ", "GLOVES"),
    ("รองเท้า", "SHOES"),
    ("ใบเลื่อย", "SAW BLADE"),
    ("ใบเลือย", "SAW BLADE"),
    ("วาว", "VALVE"),
    ("วาล์ว", "VALVE"),
    ("สกรู", "SCREW"),
    ("น็อต", "NUT"),
    ("น๊อต", "NUT"),
    ("ค้อน", "HAMMER"),
    ("แปรง", "BRUSH"),
    ("สี", "PAINT"),
)


def column_index(cell_ref: str) -> int:
    match = re.match(r"[A-Z]+", cell_ref)
    if not match:
        raise ValueError(f"invalid XLSX cell reference: {cell_ref!r}")
    value = 0
    for char in match.group(0):
        value = value * 26 + ord(char) - ord("A") + 1
    return value - 1


def read_first_sheet(path: Path) -> list[tuple[int, list[str | None]]]:
    with ZipFile(path) as archive:
        names = set(archive.namelist())
        shared: list[str] = []
        if "xl/sharedStrings.xml" in names:
            root = ET.fromstring(archive.read("xl/sharedStrings.xml"))
            for item in root.findall(f"{M}si"):
                shared.append("".join(node.text or "" for node in item.iter(f"{M}t")))

        sheet_path = "xl/worksheets/sheet1.xml"
        if sheet_path not in names:
            raise ValueError("workbook does not contain xl/worksheets/sheet1.xml")
        sheet = ET.fromstring(archive.read(sheet_path))
        sheet_data = sheet.find(f"{M}sheetData")
        if sheet_data is None:
            raise ValueError("workbook has no sheet data")

        rows: list[tuple[int, list[str | None]]] = []
        for row_node in sheet_data:
            row_number = int(row_node.attrib["r"])
            values: list[str | None] = [None] * EXPECTED_COLUMNS
            for cell in row_node.findall(f"{M}c"):
                index = column_index(cell.attrib["r"])
                if index >= EXPECTED_COLUMNS:
                    continue
                cell_type = cell.attrib.get("t")
                value_node = cell.find(f"{M}v")
                inline_node = cell.find(f"{M}is")
                value: str | None
                if cell_type == "s" and value_node is not None:
                    value = shared[int(value_node.text or "0")]
                elif cell_type == "inlineStr" and inline_node is not None:
                    value = "".join(
                        node.text or "" for node in inline_node.iter(f"{M}t")
                    )
                elif value_node is not None:
                    value = value_node.text
                else:
                    value = None
                values[index] = value
            rows.append((row_number, values))
        return rows


def clean_text(value: str | None) -> str:
    return str(value or "").strip()


def money(
    value: str | None, *, row: int, field: str
) -> tuple[Decimal, str | None]:
    text = clean_text(value)
    if not text:
        raise ValueError(f"row {row}: {field} is required")
    warning = None
    try:
        parsed = Decimal(text)
    except Exception:
        numeric_parts = re.findall(r"-?\d+(?:\.\d+)?", text)
        if len(numeric_parts) != 1:
            raise ValueError(f"row {row}: invalid {field} {text!r}")
        parsed = Decimal(numeric_parts[0])
        warning = f"row {row}: {field} {text!r} interpreted as {parsed}"
    if not parsed.is_finite():
        raise ValueError(f"row {row}: non-finite {field} {text!r}")
    return (
        parsed.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP),
        warning,
    )


def quantity(value: str | None, *, row: int) -> tuple[int, str | None]:
    text = clean_text(value)
    if not text:
        raise ValueError(f"row {row}: quantity is required")
    try:
        parsed = Decimal(text)
    except Exception as exc:
        raise ValueError(f"row {row}: invalid quantity {text!r}") from exc
    if not parsed.is_finite():
        raise ValueError(f"row {row}: non-finite quantity {text!r}")
    rounded = int(parsed.quantize(Decimal("1"), rounding=ROUND_HALF_UP))
    warning = None
    if parsed != Decimal(rounded):
        warning = f"row {row}: quantity {parsed} rounded to integer {rounded}"
    return rounded, warning


def receipt_name(name: str, code: str) -> str:
    parts: list[str] = []
    for thai, english in RECEIPT_TERMS:
        if thai in name:
            parts.append(english)
            break

    # Preserve useful Latin model names, dimensions, and numbers.
    tokens = re.findall(
        r"[A-Za-z][A-Za-z0-9._/+\"'-]*|"
        r"\d+(?:\.\d+)?(?:\s*[*xX/-]\s*\d+(?:\.\d+)?)*[\"']?",
        name,
    )
    parts.extend(token.upper().replace(" ", "") for token in tokens)

    candidate = " ".join(dict.fromkeys(parts))
    candidate = re.sub(r"[^A-Z0-9 ./+_()*\"'-]+", " ", candidate)
    candidate = re.sub(r"\s+", " ", candidate).strip()
    if len(candidate) > 32:
        candidate = candidate[:32].rstrip()
    if sum(char.isalpha() for char in candidate) >= 2:
        return candidate
    return f"ITEM {code}"


def sql(value: str | int | Decimal | bool | None) -> str:
    if value is None:
        return "NULL"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, Decimal)):
        return str(value)
    return "'" + value.replace("'", "''") + "'"


def parse_catalog(path: Path) -> tuple[list[dict[str, object]], list[str]]:
    rows = read_first_sheet(path)
    by_number = {number: values for number, values in rows}

    expected_headers = {
        4: "ชื่อ",
        8: "ต้นทุน",
        9: "ราคาขาย",
        14: "ที่อยู่สต๊อก (ร้าน, รถ1, รถ2)",
        16: "จำนวนที่มี",
    }
    headers = by_number.get(2)
    if headers is None:
        raise ValueError("header row 2 is missing")
    for index, expected in expected_headers.items():
        if clean_text(headers[index]) != expected:
            raise ValueError(
                f"unexpected header in column {index + 1}: "
                f"{headers[index]!r} (expected {expected!r})"
            )

    products: list[dict[str, object]] = []
    warnings: list[str] = []
    for row_number, values in rows:
        if row_number < FIRST_DATA_ROW:
            continue
        if not any(clean_text(value) for value in values):
            continue

        name = clean_text(values[4])
        if not name:
            raise ValueError(f"row {row_number}: product name is required")
        cost, cost_warning = money(values[8], row=row_number, field="cost")
        price, price_warning = money(values[9], row=row_number, field="price")
        if cost_warning:
            warnings.append(cost_warning)
        if price_warning:
            warnings.append(price_warning)
        store_label = clean_text(values[14])
        store_id = STORE_ALIASES.get(store_label)
        if not store_id:
            raise ValueError(
                f"row {row_number}: unknown stock location {store_label!r}"
            )
        qty, warning = quantity(values[16], row=row_number)
        if warning:
            warnings.append(warning)

        number = len(products) + 1
        code = f"P{number:04d}"
        address_code = f"ADDR{number:04d}"
        products.append(
            {
                "source_row": row_number,
                "code": code,
                "address_code": address_code,
                "name": name,
                "receipt_name": receipt_name(name, code),
                "cost": cost,
                "price": price,
                "store_id": store_id,
                "qty": qty,
            }
        )

    if not products:
        raise ValueError("no employee-entered products found from row 16 onward")
    return products, warnings


def build_seed(products: list[dict[str, object]], source_name: str) -> str:
    lines = [
        "-- =============================================================================",
        "-- Supabase product/inventory replacement seed",
        f"-- Generated from {source_name}; employee data starts at row {FIRST_DATA_ROW}.",
        f"-- Incoming products: {len(products)}; incoming inventory rows: {len(products)}.",
        "--",
        "-- Safe replacement behavior:",
        "--   * P0001... are fully replaced with the incoming product values.",
        "--   * ADDR0001... are fully replaced with the incoming inventory values.",
        "--   * stale, unreferenced product/inventory rows are deleted.",
        "--   * stale rows referenced by sales/transfer/count history are retained as",
        "--     inactive/zero-stock archive rows so historical foreign keys stay valid.",
        "-- =============================================================================",
        "",
        "BEGIN;",
        "",
        "CREATE TEMP TABLE incoming_part (",
        "  code text PRIMARY KEY,",
        "  bar_code text NOT NULL UNIQUE,",
        "  unit_id text NOT NULL,",
        "  name text NOT NULL,",
        "  name_th text NOT NULL,",
        "  receipt_name text NOT NULL,",
        "  details text NOT NULL,",
        "  cost decimal(10,2) NOT NULL,",
        "  price decimal(10,2) NOT NULL,",
        "  image text NOT NULL,",
        "  is_active boolean NOT NULL",
        ") ON COMMIT DROP;",
        "",
        "INSERT INTO incoming_part",
        "  (code, bar_code, unit_id, name, name_th, receipt_name, details, cost, price, image, is_active)",
        "VALUES",
    ]
    part_values = []
    for item in products:
        part_values.append(
            "  ("
            + ", ".join(
                [
                    sql(item["code"]),
                    sql(item["code"]),
                    sql(DEFAULT_UNIT_ID),
                    sql(item["name"]),
                    sql(item["name"]),
                    sql(item["receipt_name"]),
                    "''",
                    sql(item["cost"]),
                    sql(item["price"]),
                    "''",
                    "true",
                ]
            )
            + ")"
        )
    lines.append(",\n".join(part_values) + ";")

    lines.extend(
        [
            "",
            "CREATE TEMP TABLE incoming_address (",
            "  code text PRIMARY KEY,",
            "  part_code text NOT NULL UNIQUE,",
            "  store_id text NOT NULL,",
            "  shelf text NOT NULL,",
            "  qty integer NOT NULL,",
            '  "min" integer NOT NULL,',
            '  "max" integer NOT NULL,',
            "  rop integer NOT NULL,",
            "  remarks text NOT NULL",
            ") ON COMMIT DROP;",
            "",
            "INSERT INTO incoming_address",
            '  (code, part_code, store_id, shelf, qty, "min", "max", rop, remarks)',
            "VALUES",
        ]
    )
    address_values = []
    for item in products:
        address_values.append(
            "  ("
            + ", ".join(
                [
                    sql(item["address_code"]),
                    sql(item["code"]),
                    sql(item["store_id"]),
                    "''",
                    sql(item["qty"]),
                    "0",
                    "0",
                    "0",
                    "''",
                ]
            )
            + ")"
        )
    lines.append(",\n".join(address_values) + ";")

    lines.extend(
        [
            "",
            "-- Fail before touching production rows if the generated payload is incomplete",
            "-- or its store mapping does not exist in this database.",
            "DO $$",
            "DECLARE",
            "  part_count integer;",
            "  address_count integer;",
            "  missing_stores text;",
            "BEGIN",
            "  SELECT count(*) INTO part_count FROM incoming_part;",
            "  SELECT count(*) INTO address_count FROM incoming_address;",
            f"  IF part_count <> {len(products)} OR address_count <> {len(products)} THEN",
            "    RAISE EXCEPTION 'catalog staging count mismatch: parts %, addresses %', part_count, address_count;",
            "  END IF;",
            "",
            "  SELECT string_agg(s.store_id, ', ' ORDER BY s.store_id)",
            "    INTO missing_stores",
            "    FROM (SELECT DISTINCT store_id FROM incoming_address) s",
            "   WHERE NOT EXISTS (SELECT 1 FROM store_master sm WHERE sm.id = s.store_id);",
            "  IF missing_stores IS NOT NULL THEN",
            "    RAISE EXCEPTION 'catalog references missing stores: %', missing_stores;",
            "  END IF;",
            "",
            "  IF EXISTS (",
            "    SELECT 1",
            "      FROM address_master a",
            "      JOIN incoming_address i ON i.code = a.code",
            "      JOIN bill_item_detail b ON b.address_code = a.code",
            "     WHERE a.part_code <> i.part_code",
            "  ) THEN",
            "    RAISE EXCEPTION 'incoming address code conflicts with historical product mapping';",
            "  END IF;",
            "END $$;",
            "",
            "INSERT INTO unit_master(id, label, label_th)",
            "VALUES ('pcs', 'PCS', 'ชิ้น')",
            "ON CONFLICT (id) DO NOTHING;",
            "",
            "-- Replace the incoming product codes.",
            "INSERT INTO part_master",
            "  (code, bar_code, category_id, unit_id, name, name_th, receipt_name,",
            "   details, cost, price, image, is_active)",
            "SELECT code, bar_code, NULL, unit_id, name, name_th, receipt_name,",
            "       details, cost, price, image, is_active",
            "  FROM incoming_part",
            "ON CONFLICT (code) DO UPDATE SET",
            "  bar_code = EXCLUDED.bar_code,",
            "  category_id = EXCLUDED.category_id,",
            "  unit_id = EXCLUDED.unit_id,",
            "  name = EXCLUDED.name,",
            "  name_th = EXCLUDED.name_th,",
            "  receipt_name = EXCLUDED.receipt_name,",
            "  details = EXCLUDED.details,",
            "  cost = EXCLUDED.cost,",
            "  price = EXCLUDED.price,",
            "  image = EXCLUDED.image,",
            "  is_active = EXCLUDED.is_active;",
            "",
            "-- Replace the incoming inventory codes.",
            "INSERT INTO address_master",
            '  (code, part_code, store_id, shelf, qty, "min", "max", rop, remarks)',
            'SELECT code, part_code, store_id, shelf, qty, "min", "max", rop, remarks',
            "  FROM incoming_address",
            "ON CONFLICT (code) DO UPDATE SET",
            "  part_code = EXCLUDED.part_code,",
            "  store_id = EXCLUDED.store_id,",
            "  shelf = EXCLUDED.shelf,",
            "  qty = EXCLUDED.qty,",
            '  "min" = EXCLUDED."min",',
            '  "max" = EXCLUDED."max",',
            "  rop = EXCLUDED.rop,",
            "  remarks = EXCLUDED.remarks;",
            "",
            "-- Remove old inventory unless a historical bill still references it.",
            "DELETE FROM address_master a",
            " WHERE NOT EXISTS (SELECT 1 FROM incoming_address i WHERE i.code = a.code)",
            "   AND NOT EXISTS (SELECT 1 FROM bill_item_detail b WHERE b.address_code = a.code);",
            "",
            "-- Historical addresses cannot be deleted; zero them so they no longer",
            "-- contribute saleable stock.",
            "UPDATE address_master a",
            "   SET qty = 0,",
            '       "min" = 0,',
            '       "max" = 0,',
            "       rop = 0,",
            "       remarks = 'archived by catalog replacement 2026-07-24'",
            " WHERE NOT EXISTS (SELECT 1 FROM incoming_address i WHERE i.code = a.code);",
            "",
            "-- Delete stale products only when no operational history references them.",
            "DELETE FROM part_master p",
            " WHERE NOT EXISTS (SELECT 1 FROM incoming_part i WHERE i.code = p.code)",
            "   AND NOT EXISTS (SELECT 1 FROM address_master a WHERE a.part_code = p.code)",
            "   AND NOT EXISTS (SELECT 1 FROM bill_item_detail b WHERE b.part_code = p.code)",
            "   AND NOT EXISTS (SELECT 1 FROM inventory_transfer_item t WHERE t.part_code = p.code)",
            "   AND NOT EXISTS (SELECT 1 FROM stock_count_item s WHERE s.part_code = p.code);",
            "",
            "-- Products kept only for history must not appear as active catalog items.",
            "UPDATE part_master p",
            "   SET is_active = false",
            " WHERE NOT EXISTS (SELECT 1 FROM incoming_part i WHERE i.code = p.code);",
            "",
            "-- Final transaction guards.",
            "DO $$",
            "DECLARE",
            "  active_incoming integer;",
            "  exact_addresses integer;",
            "BEGIN",
            "  SELECT count(*) INTO active_incoming",
            "    FROM part_master p JOIN incoming_part i USING (code)",
            "   WHERE p.is_active;",
            "  SELECT count(*) INTO exact_addresses",
            "    FROM address_master a",
            "    JOIN incoming_address i",
            "      ON i.code = a.code",
            "     AND i.part_code = a.part_code",
            "     AND i.store_id = a.store_id",
            "     AND i.qty = a.qty;",
            f"  IF active_incoming <> {len(products)} OR exact_addresses <> {len(products)} THEN",
            "    RAISE EXCEPTION 'catalog verification failed: active %, addresses %', active_incoming, exact_addresses;",
            "  END IF;",
            "END $$;",
            "",
            "COMMIT;",
            "",
            "ANALYZE part_master;",
            "ANALYZE address_master;",
            "",
        ]
    )
    return "\n".join(lines)


def build_report(
    products: list[dict[str, object]], warnings: list[str], source_name: str
) -> str:
    stores = Counter(str(item["store_id"]) for item in products)
    duplicate_names = Counter(str(item["name"]) for item in products)
    duplicates = sorted(
        ((name, count) for name, count in duplicate_names.items() if count > 1),
        key=lambda item: (-item[1], item[0]),
    )
    lines = [
        "# Catalog import report — 2026-07-24",
        "",
        f"Source: `{source_name}`",
        "",
        f"- Product rows: {len(products)}",
        f"- Inventory rows: {len(products)}",
        f"- Unique product names: {len(duplicate_names)}",
        f"- Duplicate-name groups kept as separate products: {len(duplicates)}",
        f"- `main` inventory rows: {stores.get('main', 0)}",
        f"- `vehicle_POS001` (pos1) inventory rows: {stores.get('vehicle_POS001', 0)}",
        f"- `store_00001` (pos2) inventory rows: {stores.get('store_00001', 0)}",
        "",
        "## Field mapping",
        "",
        "| Excel heading | Database field | Rule |",
        "|---|---|---|",
        "| ชื่อ | `part_master.name`, `name_th` | copied to both fields |",
        "| ชื่อแสดงในใบเสร็จ | `part_master.receipt_name` | blank input gets a short ASCII name or `ITEM Pxxxx` |",
        "| ต้นทุน | `part_master.cost` | copied exactly to 2 decimals |",
        "| ราคาขาย | `part_master.price` | copied exactly to 2 decimals |",
        "| ที่อยู่สต๊อก | `address_master.store_id` | ร้าน→`main`, รถ1→`vehicle_POS001`, รถ2→`store_00001` |",
        "| จำนวนที่มี | `address_master.qty` | rounded half-up to the integer schema |",
        "",
        "Rows 3-14 are workbook examples and row 15 is an instruction row, so they",
        "are intentionally excluded. Each entered row remains a separate product,",
        "including duplicate names, because the workbook provides no shared product",
        "code with which to safely merge them.",
        "",
        "## Warnings",
        "",
    ]
    if warnings:
        lines.extend(f"- {warning}" for warning in warnings)
    else:
        lines.append("- None")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--xlsx",
        default="สินค้าและคลังสินค้า.xlsx",
        help="path to the Thai product/inventory workbook",
    )
    parser.add_argument(
        "--sql",
        default="deploy/supabase-replace-catalog-20260724.sql",
        help="generated SQL seed path",
    )
    parser.add_argument(
        "--report",
        default="docs/catalog-import-20260724.md",
        help="generated analysis report path",
    )
    args = parser.parse_args()

    xlsx_path = Path(args.xlsx)
    if not xlsx_path.exists():
        print(f"ERROR: workbook not found: {xlsx_path}", file=sys.stderr)
        return 1

    try:
        products, warnings = parse_catalog(xlsx_path)
    except (ValueError, OSError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    sql_path = Path(args.sql)
    report_path = Path(args.report)
    sql_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    sql_path.write_text(build_seed(products, xlsx_path.name), encoding="utf-8")
    report_path.write_text(
        build_report(products, warnings, xlsx_path.name), encoding="utf-8"
    )

    stores = Counter(str(item["store_id"]) for item in products)
    print(f"Parsed {len(products)} product/inventory rows from {xlsx_path}")
    print("Store rows:", ", ".join(f"{key}={value}" for key, value in sorted(stores.items())))
    for warning in warnings:
        print(f"WARNING: {warning}")
    print(f"Wrote {sql_path} ({sql_path.stat().st_size:,} bytes)")
    print(f"Wrote {report_path} ({report_path.stat().st_size:,} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
