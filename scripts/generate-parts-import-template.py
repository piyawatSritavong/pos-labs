#!/usr/bin/env python3
"""Build the Excel template users fill in for "เพิ่มสินค้าด้วยไฟล์".

The template's first sheet is the one the importer reads: row 1 holds the
column headers, and every row below it is one product. It ships empty so an
upload never creates the examples by accident — the examples live on a second
sheet the importer ignores.

Column order and meaning must stay in step with backend/internal/partsimport
(Columns) and the /parts create handler. Only the Python standard library is
used, so this runs on a fresh checkout.

Usage:
    python3 scripts/generate-parts-import-template.py
"""

from __future__ import annotations

import argparse
import shutil
import zipfile
from pathlib import Path
from xml.sax.saxutils import escape

DATA_SHEET = "สินค้า"
EXAMPLE_SHEET = "ตัวอย่าง"

# (header, column width, is_numeric) — header text is the contract with the
# importer, which matches on these strings.
COLUMNS = [
    ("ชื่อสินค้า *", 34, False),
    ("ราคาขาย *", 12, True),
    ("ต้นทุน", 12, True),
    ("จำนวนที่รับเข้าคลังหลัก", 22, True),
    ("รหัสสินค้า", 14, False),
    ("บาร์โค้ด", 16, False),
    ("หน่วย", 10, False),
    ("ราคาขายขั้นต่ำ", 15, True),
    ("ชั้นวาง", 12, False),
    ("รายละเอียด", 30, False),
]

EXAMPLES = [
    # New products — the code column is left blank.
    ["ตะปู 3*10", 650, 500, 20, "", "", "กล่อง", "", "A-01", "ตะปูสังกะสี"],
    ["เสื้อฝนลายจุด", 150, 120, 200, "", "", "ตัว", 140, "", ""],
    # An existing product: the code is what matches it, so this row adds 12 to
    # the warehouse and refreshes the cost/price. Name and barcode are ignored.
    ["ขั้วยางกันน้ำ", 15, 11, 12, "P0140", "", "", "", "", ""],
]

NOTES = [
    "วิธีใช้ — กรอกข้อมูลในชีต \"" + DATA_SHEET + "\" เท่านั้น ชีตนี้เป็นตัวอย่าง ระบบจะไม่อ่าน",
    "• คอลัมน์ที่มี * ต้องกรอก ที่เหลือเว้นว่างได้",
    "• รหัสสินค้า — เว้นว่างไว้ = สินค้าใหม่ ระบบจะออกรหัสให้อัตโนมัติ (P0001, P0002, ...)",
    "• กรอกรหัสสินค้าที่มีอยู่แล้ว = อัปเดตของเดิม จำนวนจะถูกบวกเพิ่มเข้าคลัง และแก้ต้นทุน/ราคาให้",
    "  ส่วนชื่อสินค้าและบาร์โค้ดจะไม่ถูกแก้ ต้องไปกดแก้ไขที่หน้าสินค้าเท่านั้น",
    "• บาร์โค้ด — เว้นว่างไว้ ระบบจะใช้รหัสสินค้าเป็นบาร์โค้ด",
    "• หน่วย — เว้นว่างไว้ ระบบจะใช้ \"pcs\" (ชิ้น) ถ้ากรอกหน่วยที่ไม่มีในระบบจะถูกเว้นว่าง",
    "• ราคาขายขั้นต่ำ — เว้นว่างไว้ ระบบจะคิดให้เป็น 90% ของราคาขาย และต้องไม่เกินราคาขาย",
    "• จำนวนที่รับเข้าคลังหลัก — สินค้าใหม่เข้าคลังหลักเท่านั้น เว้นว่าง = 0",
    "• ห้ามแก้ไข ลบ หรือสลับหัวคอลัมน์ในแถวที่ 1 ของชีต \"" + DATA_SHEET + "\"",
]


def column_name(index: int) -> str:
    name = ""
    index += 1
    while index:
        index, remainder = divmod(index - 1, 26)
        name = chr(ord("A") + remainder) + name
    return name


def cell(ref: str, value, *, style: int = 0) -> str:
    style_attr = f' s="{style}"' if style else ""
    if value is None or value == "":
        return f'<c r="{ref}"{style_attr}/>'
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return f'<c r="{ref}"{style_attr}><v>{value}</v></c>'
    return (
        f'<c r="{ref}"{style_attr} t="inlineStr">'
        f"<is><t xml:space=\"preserve\">{escape(str(value))}</t></is></c>"
    )


def sheet_xml(rows: list[list], *, widths: list[int] | None = None,
              header_style: int = 1) -> str:
    parts = [
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">',
    ]
    if widths:
        parts.append("<cols>")
        for index, width in enumerate(widths, start=1):
            parts.append(f'<col min="{index}" max="{index}" width="{width}" customWidth="1"/>')
        parts.append("</cols>")
    parts.append("<sheetData>")
    for row_index, row in enumerate(rows, start=1):
        cells = []
        for column_index, value in enumerate(row):
            style = header_style if row_index == 1 else 0
            cells.append(cell(f"{column_name(column_index)}{row_index}", value, style=style))
        parts.append(f'<row r="{row_index}">' + "".join(cells) + "</row>")
    parts.append("</sheetData></worksheet>")
    return "".join(parts)


CONTENT_TYPES = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
<Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>"""

ROOT_RELS = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>"""

WORKBOOK_RELS = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>
<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>"""

STYLES = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>
<font><b/><sz val="11"/><name val="Calibri"/></font></fonts>
<fills count="3"><fill><patternFill patternType="none"/></fill>
<fill><patternFill patternType="gray125"/></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FFE8EEF7"/><bgColor indexed="64"/></patternFill></fill></fills>
<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/></cellXfs>
</styleSheet>"""


def workbook_xml() -> str:
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
        ' xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        "<sheets>"
        f'<sheet name="{escape(DATA_SHEET)}" sheetId="1" r:id="rId1"/>'
        f'<sheet name="{escape(EXAMPLE_SHEET)}" sheetId="2" r:id="rId2"/>'
        "</sheets></workbook>"
    )


def build(path: Path) -> None:
    headers = [header for header, _, _ in COLUMNS]
    widths = [width for _, width, _ in COLUMNS]

    data_sheet = sheet_xml([headers], widths=widths)
    example_rows = [headers, *EXAMPLES, [], *[[note] for note in NOTES]]
    example_sheet = sheet_xml(example_rows, widths=widths)

    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("[Content_Types].xml", CONTENT_TYPES)
        archive.writestr("_rels/.rels", ROOT_RELS)
        archive.writestr("xl/workbook.xml", workbook_xml())
        archive.writestr("xl/_rels/workbook.xml.rels", WORKBOOK_RELS)
        archive.writestr("xl/styles.xml", STYLES)
        archive.writestr("xl/worksheets/sheet1.xml", data_sheet)
        archive.writestr("xl/worksheets/sheet2.xml", example_sheet)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--out",
        type=Path,
        default=Path("backend/internal/partsimport/parts_import_template.xlsx"),
        help="canonical template embedded by the backend and served for download",
    )
    parser.add_argument(
        "--copy-to",
        type=Path,
        default=Path("docs/templates/เทมเพลตเพิ่มสินค้า.xlsx"),
        help="human-facing copy kept next to the docs",
    )
    args = parser.parse_args()

    build(args.out)
    if args.copy_to:
        args.copy_to.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(args.out, args.copy_to)

    size = args.out.stat().st_size
    print(f"wrote {args.out} ({size:,} bytes)")
    if args.copy_to:
        print(f"copied to {args.copy_to}")
    print(f"  data sheet    : {DATA_SHEET} (row 1 = headers, empty below)")
    print(f"  example sheet : {EXAMPLE_SHEET} ({len(EXAMPLES)} rows, ignored by the importer)")
    print(f"  columns       : {', '.join(header for header, _, _ in COLUMNS)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
