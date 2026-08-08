#!/usr/bin/env python3
"""Rebuild the whole product catalog from สินค้าและคลังสินค้า.xlsx.

The workbook is the source of truth. The rebuilt database satisfies three rules:

  1. 'main' is the only warehouse and holds every product exactly once — one
     part_master row per distinct product name in the workbook.
  2. POS1's vehicle store holds what the "รถคันที่ 1" block lists, issued (เบิก)
     out of the warehouse.
  3. POS2's vehicle store holds what the "รถคันที่ 2" block lists, likewise.

Because the previous catalog gave the same product a separate code per stock
location, aligning it in place is not possible without leaving retired codes
behind — so the seed drops the catalog and the transaction history that
references it, then rebuilds both from scratch. Take a pg_dump first.

Product codes are renumbered P0001.. in workbook order (first appearance wins).

Only the Python standard library is used.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import unicodedata
from collections import OrderedDict
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path
from xml.etree import ElementTree as ET
from zipfile import ZipFile

MAIN_NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
M = f"{{{MAIN_NS}}}"

FIRST_DATA_ROW = 16
EXPECTED_COLUMNS = 21
DEFAULT_UNIT_ID = "pcs"

WAREHOUSE = "main"
SECTIONS = {
    "ร้าน": WAREHOUSE,
    "main": WAREHOUSE,
    "รถ1": "vehicle_POS001",
    "รถ 1": "vehicle_POS001",
    "รถคันที่ 1": "vehicle_POS001",
    "pos1": "vehicle_POS001",
    "รถ2": "store_00001",
    "รถ 2": "store_00001",
    "รถคันที่ 2": "store_00001",
    "pos2": "store_00001",
}
# store_id -> (pos_id, branch_id) for the restock document that issues its stock
VEHICLES = OrderedDict(
    [
        ("vehicle_POS001", ("POS001", "00001")),
        ("store_00001", ("POS002", "00002")),
    ]
)

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

# Tables emptied before the rebuild, children first.
WIPE_ORDER = (
    "bill_discount_detail",
    "return_note_item_detail",
    "return_note_master",
    "bill_item_detail",
    "bill_master",
    "stock_count_item",
    "stock_count",
    "inventory_transfer_audit",
    "inventory_transfer_item",
    "inventory_transfer",
    "purchase_order_item",
    "purchase_order",
    "cash_reconciliation",
    "daily_close",
    "address_master",
    "part_master",
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
        shared: list[str] = []
        if "xl/sharedStrings.xml" in set(archive.namelist()):
            root = ET.fromstring(archive.read("xl/sharedStrings.xml"))
            for item in root.findall(f"{M}si"):
                shared.append("".join(n.text or "" for n in item.iter(f"{M}t")))
        sheet = ET.fromstring(archive.read("xl/worksheets/sheet1.xml"))
        sheet_data = sheet.find(f"{M}sheetData")
        if sheet_data is None:
            raise ValueError("workbook has no sheet data")
        rows: list[tuple[int, list[str | None]]] = []
        for row_node in sheet_data:
            values: list[str | None] = [None] * EXPECTED_COLUMNS
            for cell in row_node.findall(f"{M}c"):
                index = column_index(cell.attrib["r"])
                if index >= EXPECTED_COLUMNS:
                    continue
                cell_type = cell.attrib.get("t")
                value_node = cell.find(f"{M}v")
                inline_node = cell.find(f"{M}is")
                if cell_type == "s" and value_node is not None:
                    value = shared[int(value_node.text or "0")]
                elif cell_type == "inlineStr" and inline_node is not None:
                    value = "".join(n.text or "" for n in inline_node.iter(f"{M}t"))
                elif value_node is not None:
                    value = value_node.text
                else:
                    value = None
                values[index] = value
            rows.append((int(row_node.attrib["r"]), values))
        return rows


def clean_text(value: str | None) -> str:
    return str(value or "").strip()


def match_key(name: str) -> str:
    text = unicodedata.normalize("NFC", name or "").replace("​", "").replace("\xa0", " ")
    return re.sub(r"\s+", " ", text).strip().lower()


def number(value: str | None, *, row: int, field: str) -> tuple[Decimal, str | None]:
    text = clean_text(value)
    if not text:
        raise ValueError(f"row {row}: {field} is required")
    warning = None
    try:
        parsed = Decimal(text)
    except Exception:
        found = re.findall(r"-?\d+(?:\.\d+)?", text)
        if len(found) != 1:
            raise ValueError(f"row {row}: invalid {field} {text!r}")
        parsed = Decimal(found[0])
        warning = f"row {row}: {field} {text!r} read as {parsed}"
    if not parsed.is_finite():
        raise ValueError(f"row {row}: non-finite {field} {text!r}")
    return parsed, warning


def receipt_name(name: str, code: str) -> str:
    parts: list[str] = []
    for thai, english in RECEIPT_TERMS:
        if thai in name:
            parts.append(english)
            break
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


def vehicle_address_code(store_id: str, part_code: str) -> str:
    """Mirror of repository.vehicleAddressCode in the Go backend."""
    return "VEH" + hashlib.sha1(f"{store_id}:{part_code}".encode()).digest()[:10].hex().upper()


def sql(value) -> str:
    if value is None:
        return "NULL"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, Decimal)):
        return str(value)
    return "'" + str(value).replace("'", "''") + "'"


def parse_workbook(path: Path) -> tuple[list[dict], list[str]]:
    rows = read_first_sheet(path)
    headers = {number: values for number, values in rows}.get(2)
    if headers is None:
        raise ValueError("header row 2 is missing")
    for index, expected in {
        4: "ชื่อ",
        8: "ต้นทุน",
        9: "ราคาขาย",
        14: "ที่อยู่สต๊อก (ร้าน, รถ1, รถ2)",
        16: "จำนวนที่มี",
    }.items():
        if clean_text(headers[index]) != expected:
            raise ValueError(
                f"unexpected header in column {index + 1}: "
                f"{headers[index]!r} (expected {expected!r})"
            )

    products: "OrderedDict[str, dict]" = OrderedDict()
    warnings: list[str] = []
    for row_number, values in rows:
        if row_number < FIRST_DATA_ROW:
            continue
        if not any(clean_text(value) for value in values):
            continue

        name = clean_text(values[4])
        if not name:
            raise ValueError(f"row {row_number}: product name is required")
        label = clean_text(values[14])
        store_id = SECTIONS.get(label)
        if not store_id:
            raise ValueError(f"row {row_number}: unknown stock location {label!r}")

        cost, cost_warning = number(values[8], row=row_number, field="cost")
        price, price_warning = number(values[9], row=row_number, field="price")
        for warning in (cost_warning, price_warning):
            if warning:
                warnings.append(warning)
        cost = cost.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
        price = price.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
        raw_qty, _ = number(values[16], row=row_number, field="quantity")
        qty = int(raw_qty.quantize(Decimal("1"), rounding=ROUND_HALF_UP))
        if raw_qty != Decimal(qty):
            warnings.append(f"row {row_number}: qty {raw_qty} rounded to {qty}")

        key = match_key(name)
        product = products.get(key)
        if product is None:
            products[key] = {
                "key": key,
                "name": name,
                "cost": cost,
                "price": price,
                "qty": {WAREHOUSE: 0, **{store: 0 for store in VEHICLES}},
                "stores": {store_id},
                "rows": [(row_number, label)],
            }
            product = products[key]
        else:
            product["rows"].append((row_number, label))
            product["stores"].add(store_id)
            if (product["cost"], product["price"]) != (cost, price):
                warnings.append(
                    f"row {row_number}: {name!r} repeats with cost/price "
                    f"{cost}/{price}; keeping {product['cost']}/{product['price']} "
                    f"from row {product['rows'][0][0]}"
                )
        product["qty"][store_id] += qty

    if not products:
        raise ValueError("no employee-entered rows found from row 16 onward")
    return list(products.values()), warnings


def apply_overrides(products: list[dict], overrides: dict) -> list[str]:
    """overrides: {store_id: {match_key: qty}} — quantities kept from the live
    database instead of the workbook."""
    by_key = {product["key"]: product for product in products}
    notes: list[str] = []
    for store_id, per_name in overrides.items():
        for raw_name, qty in per_name.items():
            key = match_key(raw_name)
            product = by_key.get(key)
            if product is None:
                raise ValueError(f"override for unknown product {raw_name!r}")
            if product["qty"][store_id] == qty:
                continue
            notes.append(
                f"{store_id}: {product['name']!r} keeps database qty {qty} "
                f"(workbook says {product['qty'][store_id]})"
            )
            product["qty"][store_id] = qty
    return notes


def build_seed(products: list[dict], source_name: str, date_key: str, admin: str) -> str:
    out: list[str] = []
    w = out.append
    # A product belongs to a vehicle because its block lists it, not because it
    # happens to carry stock — a listed product at 0 still needs its stock row.
    per_store = {
        store: [p for p in products if store in p["stores"]]
        for store in (WAREHOUSE, *VEHICLES)
    }
    transfer_ids = {
        store: f"TR{date_key}{index:06d}" for index, store in enumerate(VEHICLES, start=1)
    }

    w("-- =============================================================================")
    w("-- Full catalog rebuild from the stock workbook")
    w(f"-- Generated from {source_name} by scripts/generate-catalog-rebuild-seed.py")
    w("--")
    w(f"-- Products (one per distinct name)      : {len(products)}  P0001..P{len(products):04d}")
    w(f"-- Warehouse '{WAREHOUSE}' stock rows          : {len(products)} "
      f"({sum(1 for p in products if p['qty'][WAREHOUSE])} with stock, "
      f"{sum(p['qty'][WAREHOUSE] for p in products)} units)")
    for store in VEHICLES:
        pos_id, _ = VEHICLES[store]
        w(f"-- {pos_id} vehicle stock ({store}){'':<{max(0, 14 - len(store))}}: "
          f"{len(per_store[store])} products, {sum(p['qty'][store] for p in products)} units")
    w("--")
    w("-- DESTRUCTIVE. Drops the catalog and every document that references it")
    w("-- (bills, returns, stock counts, transfers, purchase orders, daily closes)")
    w("-- so the rebuilt catalog carries no retired codes. Users, roles, branches,")
    w("-- stores, POS settings, units, categories and sessions are left untouched.")
    w("-- Take a pg_dump of schema 'public' before running this.")
    w("--")
    w("-- Each vehicle's stock is issued out of the warehouse by one completed")
    w("-- pos_restock transfer, mirroring what the app writes on completion.")
    w("-- =============================================================================")
    w("")
    w("BEGIN;")
    w("")
    w("-- Guard: everything this seed writes against must already exist.")
    w("DO $$")
    w("BEGIN")
    w(f"  IF NOT EXISTS (SELECT 1 FROM store_master"
      f" WHERE id = {sql(WAREHOUSE)} AND location_type = 'warehouse') THEN")
    w(f"    RAISE EXCEPTION 'warehouse {WAREHOUSE} is missing';")
    w("  END IF;")
    w("  IF (SELECT count(*) FROM store_master WHERE location_type = 'warehouse') <> 1 THEN")
    w("    RAISE EXCEPTION 'expected exactly one warehouse';")
    w("  END IF;")
    for store, (pos_id, branch_id) in VEHICLES.items():
        w(f"  IF NOT EXISTS (SELECT 1 FROM pos_setting WHERE pos_id = {sql(pos_id)}")
        w(f"                   AND vehicle_store_id = {sql(store)} AND branch_id = {sql(branch_id)}) THEN")
        w(f"    RAISE EXCEPTION '{pos_id} is not bound to {store}/{branch_id}';")
        w("  END IF;")
    w(f"  IF NOT EXISTS (SELECT 1 FROM \"user\" WHERE username = {sql(admin)}) THEN")
    w(f"    RAISE EXCEPTION 'user {admin} is missing';")
    w("  END IF;")
    w(f"  IF NOT EXISTS (SELECT 1 FROM unit_master WHERE id = {sql(DEFAULT_UNIT_ID)}) THEN")
    w(f"    RAISE EXCEPTION 'unit {DEFAULT_UNIT_ID} is missing';")
    w("  END IF;")
    w("END $$;")
    w("")
    w("-- 1. Clear the catalog and every document that references it, children first.")
    for table in WIPE_ORDER:
        w(f"DELETE FROM {table};")
    w("")
    w("-- Document counters restart with the clean history; branch/member counters stay.")
    w("DELETE FROM counter WHERE key ~ '^[a-z]*_?[0-9]{8}$';")
    w("")

    # ------------------------------------------------------------------ parts
    w("-- 2. One product per distinct workbook name, renumbered in workbook order.")
    w("INSERT INTO part_master")
    w("  (code, bar_code, category_id, unit_id, name, name_th, details,")
    w("   cost, price, min_price, image, is_active, receipt_name)")
    w("VALUES")
    values = []
    for product in products:
        values.append(
            "  ("
            + ", ".join(
                [
                    sql(product["code"]),
                    sql(product["code"]),
                    "NULL",
                    sql(DEFAULT_UNIT_ID),
                    sql(product["name"]),
                    sql(product["name"]),
                    "''",
                    sql(product["cost"]),
                    sql(product["price"]),
                    sql(product["min_price"]),
                    "''",
                    "true",
                    sql(product["receipt_name"]),
                ]
            )
            + ")"
        )
    w(",\n".join(values) + ";")
    w("")

    # -------------------------------------------------------------- warehouse
    w("-- 3. Warehouse stock. Every product gets exactly one row here, so 'main'")
    w("--    is the single place the catalog lives. The quantity is what the ร้าน")
    w("--    block lists; products the shop does not hold close at 0 because")
    w("--    everything they were stocked with went out to a vehicle.")
    w("INSERT INTO address_master (code, part_code, store_id, shelf, qty, rop, remarks, is_active)")
    w("VALUES")
    values = []
    for product in products:
        values.append(
            "  ("
            + ", ".join(
                [
                    sql(product["warehouse_address_code"]),
                    sql(product["code"]),
                    sql(WAREHOUSE),
                    "''",
                    sql(product["qty"][WAREHOUSE]),
                    "0",
                    "''",
                    "true",
                ]
            )
            + ")"
        )
    w(",\n".join(values) + ";")
    w("")

    # ----------------------------------------------------------- vehicle rows
    for index, (store, (pos_id, branch_id)) in enumerate(VEHICLES.items(), start=4):
        stocked = per_store[store]
        transfer_id = transfer_ids[store]
        w(f"-- {index}. {pos_id} vehicle stock. Address code, shelf and remarks match what")
        w("--    the backend writes itself when a restock request completes.")
        w("INSERT INTO address_master (code, part_code, store_id, shelf, qty, rop, remarks, is_active)")
        w("VALUES")
        values = []
        for product in stocked:
            values.append(
                "  ("
                + ", ".join(
                    [
                        sql(product["vehicle_address_code"][store]),
                        sql(product["code"]),
                        sql(store),
                        sql("รถ"),
                        sql(product["qty"][store]),
                        "0",
                        sql("สร้างจากใบเบิกสินค้าเข้ารถ"),
                        "true",
                    ]
                )
                + ")"
            )
        w(",\n".join(values) + ";")
        w("")
        total = sum(product["price"] * product["qty"][store] for product in stocked)
        moved = [product for product in stocked if product["qty"][store]]
        w(f"-- The issue document behind that stock.")
        w("INSERT INTO inventory_transfer")
        w("  (id, from_branch_id, to_branch_id, created_by, status, notes, created_at,")
        w("   submitted_at, submitted_by, approved_at, approved_by, dispatched_at, dispatched_by,")
        w("   received_at, received_by, completed_at, completed_by, transfer_mode,")
        w("   from_store_id, to_store_id, target_pos_id, total_sale_value)")
        w("SELECT " + ", ".join([
            sql(transfer_id), sql(branch_id), sql(branch_id), "u.id", sql("completed"),
            sql(f"seed: {source_name} — เบิกเข้า {pos_id}"), "now()",
            "now()", "u.id", "now()", "u.id", "now()", "u.id",
            "now()", "u.id", "now()", "u.id", sql("pos_restock"),
            sql(WAREHOUSE), sql(store), sql(pos_id), sql(total.quantize(Decimal("0.01"))),
        ]))
        w(f"  FROM \"user\" u WHERE u.username = {sql(admin)};")
        w("")
        w("-- Lines for what actually moved; a listed product at 0 has nothing to issue.")
        w("INSERT INTO inventory_transfer_item")
        w("  (transfer_id, part_code, requested_qty, dispatched_qty, received_qty, sale_price, line_total)")
        w("VALUES")
        values = []
        for product in stocked:
            qty = product["qty"][store]
            if qty == 0:
                continue
            values.append(
                "  ("
                + ", ".join(
                    [
                        sql(transfer_id),
                        sql(product["code"]),
                        sql(qty),
                        sql(qty),
                        sql(qty),
                        sql(product["price"]),
                        sql((product["price"] * qty).quantize(Decimal("0.01"))),
                    ]
                )
                + ")"
            )
        w(",\n".join(values) + ";")
        w("")

    w("INSERT INTO counter (key, value) VALUES "
      f"({sql('tr_' + date_key)}, {len(VEHICLES)})")
    w("ON CONFLICT (key) DO UPDATE SET value = GREATEST(counter.value, EXCLUDED.value);")
    w("")

    # ------------------------------------------------------------- assertions
    w("-- Post-conditions: the three rules this rebuild exists to satisfy.")
    w("DO $$")
    w("DECLARE n bigint;")
    w("BEGIN")
    w("  SELECT count(*) INTO n FROM part_master;")
    w(f"  IF n <> {len(products)} THEN")
    w(f"    RAISE EXCEPTION 'expected {len(products)} products, found %', n;")
    w("  END IF;")
    w("")
    w("  -- rule 1: one warehouse, every product in it exactly once, no repeated names")
    w("  SELECT count(*) INTO n FROM store_master WHERE location_type = 'warehouse';")
    w("  IF n <> 1 THEN RAISE EXCEPTION 'expected exactly one warehouse, found %', n; END IF;")
    w("  SELECT count(*) INTO n FROM address_master WHERE store_id = " + sql(WAREHOUSE) + ";")
    w(f"  IF n <> {len(products)} THEN")
    w(f"    RAISE EXCEPTION 'warehouse should hold all {len(products)} products, holds %', n;")
    w("  END IF;")
    w("  SELECT count(*) INTO n FROM (")
    w("    SELECT lower(btrim(name)) FROM part_master GROUP BY 1 HAVING count(*) > 1) d;")
    w("  IF n <> 0 THEN RAISE EXCEPTION '% product names occur more than once', n; END IF;")
    w("  SELECT count(*) INTO n FROM (")
    w("    SELECT part_code, store_id FROM address_master GROUP BY 1, 2 HAVING count(*) > 1) d;")
    w("  IF n <> 0 THEN RAISE EXCEPTION '% products have two rows in one store', n; END IF;")
    w("")
    w("  -- rules 2 and 3: each vehicle holds exactly what its block lists, and")
    w("  -- every unit it holds is covered by a completed issue out of the warehouse")
    for store in VEHICLES:
        stocked = per_store[store]
        units = sum(product["qty"][store] for product in stocked)
        w(f"  SELECT count(*) INTO n FROM address_master WHERE store_id = {sql(store)};")
        w(f"  IF n <> {len(stocked)} THEN")
        w(f"    RAISE EXCEPTION '{store} should hold {len(stocked)} products, holds %', n;")
        w("  END IF;")
        w(f"  SELECT COALESCE(sum(qty), 0) INTO n FROM address_master WHERE store_id = {sql(store)};")
        w(f"  IF n <> {units} THEN")
        w(f"    RAISE EXCEPTION '{store} should hold {units} units, holds %', n;")
        w("  END IF;")
        w("  SELECT COALESCE(sum(i.received_qty), 0) INTO n FROM inventory_transfer_item i")
        w(f"   WHERE i.transfer_id = {sql(transfer_ids[store])};")
        w(f"  IF n <> {units} THEN")
        w(f"    RAISE EXCEPTION 'issue document for {store} covers % units, expected {units}', n;")
        w("  END IF;")
        w("  IF EXISTS (SELECT 1 FROM address_master a")
        w(f"              WHERE a.store_id = {sql(store)}")
        w("                AND NOT EXISTS (SELECT 1 FROM address_master m")
        w(f"                                 WHERE m.part_code = a.part_code AND m.store_id = {sql(WAREHOUSE)})) THEN")
        w(f"    RAISE EXCEPTION '{store} holds a product that is not registered in the warehouse';")
        w("  END IF;")
    w("END $$;")
    w("")
    w("COMMIT;")
    w("")
    return "\n".join(out)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--xlsx", default=Path("สินค้าและคลังสินค้า.xlsx"), type=Path)
    parser.add_argument("--out", default=Path("deploy/supabase-catalog-rebuild-20260808.sql"), type=Path)
    parser.add_argument("--overrides", type=Path,
                        help="JSON {store_id: {product name: qty}} kept from the live database")
    parser.add_argument("--date-key", default="20260808")
    parser.add_argument("--admin", default="admin")
    args = parser.parse_args()

    products, warnings = parse_workbook(args.xlsx)
    notes: list[str] = []
    if args.overrides:
        notes = apply_overrides(products, json.loads(args.overrides.read_text()))

    for index, product in enumerate(products, start=1):
        code = f"P{index:04d}"
        product["code"] = code
        product["receipt_name"] = receipt_name(product["name"], code)
        product["min_price"] = (product["price"] * Decimal("0.90")).quantize(Decimal("0.01"))
        product["warehouse_address_code"] = f"ADDR{index:04d}"
        product["vehicle_address_code"] = {
            store: vehicle_address_code(store, code) for store in VEHICLES
        }

    args.out.write_text(build_seed(products, args.xlsx.name, args.date_key, args.admin))

    print(f"wrote {args.out}")
    print(f"  products            : {len(products)}  P0001..P{len(products):04d}")
    print(f"  warehouse units     : {sum(p['qty'][WAREHOUSE] for p in products)}")
    for store, (pos_id, _) in VEHICLES.items():
        listed = [p for p in products if store in p["stores"]]
        print(f"  {pos_id} ({store}): {len(listed)} products, "
              f"{sum(p['qty'][store] for p in listed)} units")
    for note in notes:
        print(f"  OVERRIDE: {note}")
    price_conflicts = sum(1 for line in warnings if "repeats with cost/price" in line)
    other = [line for line in warnings if "repeats with cost/price" not in line]
    print(f"  rows repeating a name with a different cost/price: {price_conflicts}")
    for line in other:
        print(f"  WARNING: {line}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
