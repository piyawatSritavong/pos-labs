package partsimport

import (
	"archive/zip"
	"bytes"
	"fmt"
	"strings"
	"testing"
)

// buildXLSX writes a workbook that uses sharedStrings, the way Excel saves a
// file the user edited — the reader has to cope with that as well as with the
// inline strings our own template uses.
func buildXLSX(t *testing.T, sheetName string, rows [][]string) []byte {
	t.Helper()

	strIndex := map[string]int{}
	var order []string
	for _, row := range rows {
		for _, cell := range row {
			if cell == "" {
				continue
			}
			if _, ok := strIndex[cell]; !ok {
				strIndex[cell] = len(order)
				order = append(order, cell)
			}
		}
	}

	var sheet strings.Builder
	sheet.WriteString(`<?xml version="1.0"?><worksheet xmlns="` + sheetMainNS + `"><sheetData>`)
	for rowIndex, row := range rows {
		fmt.Fprintf(&sheet, `<row r="%d">`, rowIndex+1)
		for columnIndex, cell := range row {
			if cell == "" {
				continue
			}
			ref := fmt.Sprintf("%c%d", 'A'+columnIndex, rowIndex+1)
			fmt.Fprintf(&sheet, `<c r="%s" t="s"><v>%d</v></c>`, ref, strIndex[cell])
		}
		sheet.WriteString(`</row>`)
	}
	sheet.WriteString(`</sheetData></worksheet>`)

	var shared strings.Builder
	fmt.Fprintf(&shared, `<?xml version="1.0"?><sst xmlns="%s" count="%d" uniqueCount="%d">`,
		sheetMainNS, len(order), len(order))
	for _, value := range order {
		fmt.Fprintf(&shared, `<si><t>%s</t></si>`, value)
	}
	shared.WriteString(`</sst>`)

	buffer := &bytes.Buffer{}
	archive := zip.NewWriter(buffer)
	write := func(name, body string) {
		writer, err := archive.Create(name)
		if err != nil {
			t.Fatalf("create %s: %v", name, err)
		}
		if _, err := writer.Write([]byte(body)); err != nil {
			t.Fatalf("write %s: %v", name, err)
		}
	}
	write("[Content_Types].xml", `<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>`)
	write("_rels/.rels", `<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>`)
	write("xl/workbook.xml", fmt.Sprintf(
		`<?xml version="1.0"?><workbook xmlns="%s" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">`+
			`<sheets><sheet name="%s" sheetId="1" r:id="rId7"/></sheets></workbook>`, sheetMainNS, sheetName))
	write("xl/_rels/workbook.xml.rels",
		`<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">`+
			`<Relationship Id="rId7" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/data.xml"/>`+
			`</Relationships>`)
	write("xl/sharedStrings.xml", shared.String())
	write("xl/worksheets/data.xml", sheet.String())
	if err := archive.Close(); err != nil {
		t.Fatalf("close archive: %v", err)
	}
	return buffer.Bytes()
}

func headerRow() []string {
	header := make([]string, 0, len(Columns))
	for _, column := range Columns {
		if column.Required {
			header = append(header, column.Header+" *")
			continue
		}
		header = append(header, column.Header)
	}
	return header
}

func TestTemplateIsReadableAndEmpty(t *testing.T) {
	sheet, err := ReadFirstSheet(TemplateXLSX)
	if err != nil {
		t.Fatalf("read template: %v", err)
	}
	if len(sheet.Rows) != 1 {
		t.Fatalf("template's data sheet should hold only the header row, got %d rows", len(sheet.Rows))
	}
	if _, err := mapHeaders(sheet.Rows[0]); err != nil {
		t.Fatalf("template headers do not satisfy the importer: %v", err)
	}
	// The examples must live somewhere the importer never reads, or an
	// untouched template upload would create them.
	rows, problems, err := Parse(sheet)
	if err == nil && (len(rows) > 0 || len(problems) > 0) {
		t.Fatalf("blank template produced rows=%d problems=%d", len(rows), len(problems))
	}
}

func TestParseFillsDefaults(t *testing.T) {
	data := buildXLSX(t, "สินค้า", [][]string{
		headerRow(),
		{"ตะปู 3*10", "650", "500", "20", "", "", "กล่อง", "", "A-01", "ตะปูสังกะสี"},
		{"เสื้อฝนลายจุด", "150", "", "", "", "", "", "", "", ""},
	})
	sheet, err := ReadFirstSheet(data)
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	rows, problems, err := Parse(sheet)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if len(problems) != 0 {
		t.Fatalf("unexpected problems: %v", problems)
	}
	if len(rows) != 2 {
		t.Fatalf("expected 2 rows, got %d", len(rows))
	}

	first := rows[0]
	if first.SheetRow != 2 || first.Name != "ตะปู 3*10" || first.Price != 650 || first.Cost != 500 || first.Qty != 20 {
		t.Fatalf("first row parsed wrong: %+v", first)
	}
	if first.MinPrice != 585 {
		t.Fatalf("blank min price should default to 90%% of price, got %v", first.MinPrice)
	}
	if first.UnitID != "กล่อง" || first.Shelf != "A-01" {
		t.Fatalf("optional columns lost: %+v", first)
	}

	second := rows[1]
	if second.UnitID != DefaultUnitID {
		t.Fatalf("blank unit should default to %q, got %q", DefaultUnitID, second.UnitID)
	}
	if second.Cost != 0 || second.Qty != 0 {
		t.Fatalf("blank cost/qty should default to 0: %+v", second)
	}
	if second.Code != "" || second.BarCode != "" {
		t.Fatalf("blank code/barcode must stay empty so the repository assigns them: %+v", second)
	}
}

func TestParseReportsEveryBadRow(t *testing.T) {
	data := buildXLSX(t, "สินค้า", [][]string{
		headerRow(),
		{"", "10", "", "", "", "", "", "", "", ""},                // missing name
		{"ของดี", "ไม่ใช่ตัวเลข", "", "", "", "", "", "", "", ""}, // price not a number
		{"ของถูก", "10", "", "", "", "", "", "20", "", ""},        // min price above price
		{"ของใหม่", "10", "", "", "P0001", "", "", "", "", ""},    // fine
		{"ของอื่น", "10", "", "", "P0001", "", "", "", "", ""},    // code repeats row 5
		{"ของท้าย", "10", "", "", "P 001", "", "", "", "", ""},    // code with a space
	})
	sheet, err := ReadFirstSheet(data)
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	rows, problems, err := Parse(sheet)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if len(rows) != 1 || rows[0].SheetRow != 5 {
		t.Fatalf("only the good row should survive, got %+v", rows)
	}
	wantRows := []int{2, 3, 4, 6, 7}
	if len(problems) != len(wantRows) {
		t.Fatalf("expected one problem per bad row, got %d: %v", len(problems), problems)
	}
	for index, wantRow := range wantRows {
		if problems[index].SheetRow != wantRow {
			t.Fatalf("problem %d points at row %d, want %d: %v",
				index, problems[index].SheetRow, wantRow, problems[index])
		}
	}
}

func TestParseLeavesDuplicateNamesToTheRepository(t *testing.T) {
	// Rows that repeat a name are folded together against the product they
	// resolve to, and only the repository knows what the catalog holds — so the
	// parser must not pre-judge them.
	data := buildXLSX(t, "สินค้า", [][]string{
		headerRow(),
		{"ตะปู 3*10", "650", "", "20", "P0001", "", "", "", "", ""},
		{"ตะปู 3*10", "650", "", "5", "", "", "", "", "", ""},
	})
	sheet, err := ReadFirstSheet(data)
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	rows, problems, err := Parse(sheet)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if len(problems) != 0 {
		t.Fatalf("the parser should not judge duplicate names: %v", problems)
	}
	if len(rows) != 2 {
		t.Fatalf("expected both rows to reach the repository, got %d", len(rows))
	}
}

func TestParseSkipsBlankRowsAndStopsAtMaxRows(t *testing.T) {
	rows := [][]string{headerRow(), {"", "", "", "", "", "", "", "", "", ""}}
	for index := 0; index <= MaxRows; index++ {
		rows = append(rows, []string{fmt.Sprintf("สินค้า %d", index), "10", "", "", "", "", "", "", "", ""})
	}
	sheet, err := ReadFirstSheet(buildXLSX(t, "สินค้า", rows))
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	parsed, problems, err := Parse(sheet)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if len(parsed) != MaxRows {
		t.Fatalf("expected the batch to cap at %d rows, got %d", MaxRows, len(parsed))
	}
	if len(problems) != 1 || !strings.Contains(problems[0].Message, fmt.Sprint(MaxRows)) {
		t.Fatalf("expected one over-limit problem, got %v", problems)
	}
}

func TestParseRejectsAForeignSpreadsheet(t *testing.T) {
	data := buildXLSX(t, "Sheet1", [][]string{
		{"Product", "Price"},
		{"Widget", "10"},
	})
	sheet, err := ReadFirstSheet(data)
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	if _, _, err := Parse(sheet); err == nil {
		t.Fatal("a sheet without the template headers must be rejected")
	}
}

func TestParseFindsReorderedColumns(t *testing.T) {
	data := buildXLSX(t, "สินค้า", [][]string{
		{"ราคาขาย*", "หมายเหตุของฉัน", "ชื่อสินค้า", "จำนวนที่รับเข้าคลังหลัก"},
		{"99.50", "อะไรก็ได้", "ของทดสอบ", "3"},
	})
	sheet, err := ReadFirstSheet(data)
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	rows, problems, err := Parse(sheet)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if len(problems) != 0 {
		t.Fatalf("unexpected problems: %v", problems)
	}
	if len(rows) != 1 || rows[0].Name != "ของทดสอบ" || rows[0].Price != 99.5 || rows[0].Qty != 3 {
		t.Fatalf("reordered columns parsed wrong: %+v", rows)
	}
}

func TestReadFirstSheetRejectsNonXLSX(t *testing.T) {
	if _, err := ReadFirstSheet([]byte("this is a csv,not a workbook")); err == nil {
		t.Fatal("a non-zip payload must be rejected")
	}
}
