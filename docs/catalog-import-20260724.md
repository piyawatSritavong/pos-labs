# Catalog import report — 2026-07-24

Source: `สินค้าและคลังสินค้า.xlsx`

- Product rows: 800
- Inventory rows: 800
- Unique product names: 760
- Duplicate-name groups kept as separate products: 40
- `main` inventory rows: 369
- `vehicle_POS001` (pos1) inventory rows: 431
- `store_00001` (pos2) inventory rows: 0

## Field mapping

| Excel heading | Database field | Rule |
|---|---|---|
| ชื่อ | `part_master.name`, `name_th` | copied to both fields |
| ชื่อแสดงในใบเสร็จ | `part_master.receipt_name` | blank input gets a short ASCII name or `ITEM Pxxxx` |
| ต้นทุน | `part_master.cost` | copied exactly to 2 decimals |
| ราคาขาย | `part_master.price` | copied exactly to 2 decimals |
| ราคาลดได้ | `part_master.min_price` | defaults to 90% of selling price |
| ที่อยู่สต๊อก | `address_master.store_id` | ร้าน→`main`, รถ1→`vehicle_POS001`, รถ2→`store_00001` |
| จำนวนที่มี | `address_master.qty` | rounded half-up to the integer schema |

Rows 3-14 are workbook examples and row 15 is an instruction row, so they
are intentionally excluded. Each entered row remains a separate product,
including duplicate names, because the workbook provides no shared product
code with which to safely merge them.

## Warnings

- row 526: cost 'ุ16' interpreted as 16
- row 731: quantity 21.3 rounded to integer 21
