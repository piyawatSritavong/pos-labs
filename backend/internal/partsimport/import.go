package partsimport

import (
	"fmt"
	"strconv"
	"strings"
	"unicode"
)

const (
	// MaxFileBytes caps the upload. A 1,000-row sheet written by this repo's
	// generator is ~45 KB; the same content saved by Excel — shared strings,
	// theme, styles, calc chain — lands well under 300 KB. 2 MB leaves room for
	// whatever formatting a user adds without letting an arbitrary file through.
	MaxFileBytes = 2 << 20

	// MaxRows is the batch size the feature promises. Keeping it explicit means
	// a user who pastes ten thousand rows gets told to split the file instead of
	// waiting on a transaction that holds the catalog for minutes.
	MaxRows = 1000

	// DefaultUnitID matches the /parts create handler.
	DefaultUnitID = "pcs"

	// WarehouseStoreID is the only store new products may enter. The catalog is
	// modelled as one warehouse that vehicles draw from.
	WarehouseStoreID = "main"

	// MinPriceRatio is the fallback floor price when the sheet leaves it blank,
	// mirroring the create handler's `price * 0.90`.
	MinPriceRatio = 0.90
)

// Field identifies a template column. The header text is the contract with the
// spreadsheet; scripts/generate-parts-import-template.py writes exactly these.
type Field struct {
	Header   string
	Required bool
}

// Columns is the template layout, in order. Changing it means regenerating the
// template with scripts/generate-parts-import-template.py.
var Columns = []Field{
	{Header: "ชื่อสินค้า", Required: true},
	{Header: "ราคาขาย", Required: true},
	{Header: "ต้นทุน"},
	{Header: "จำนวนที่รับเข้าคลังหลัก"},
	{Header: "รหัสสินค้า"},
	{Header: "บาร์โค้ด"},
	{Header: "หน่วย"},
	{Header: "ราคาขายขั้นต่ำ"},
	{Header: "ชั้นวาง"},
	{Header: "รายละเอียด"},
}

const (
	colName = iota
	colPrice
	colCost
	colQty
	colCode
	colBarcode
	colUnit
	colMinPrice
	colShelf
	colDetails
)

// Row is one validated product from the sheet, ready for the repository.
// Code and BarCode may be empty — the repository assigns running codes then.
type Row struct {
	SheetRow int // 1-based row number in the worksheet, for error messages
	Name     string
	Code     string
	BarCode  string
	UnitID   string
	Shelf    string
	Details  string
	Price    float64
	Cost     float64
	MinPrice float64
	Qty      int
}

// RowError points at one cell the user has to fix.
type RowError struct {
	SheetRow int    `json:"row"`
	Column   string `json:"column,omitempty"`
	Message  string `json:"message"`
}

func (e RowError) Error() string {
	if e.Column == "" {
		return fmt.Sprintf("แถว %d: %s", e.SheetRow, e.Message)
	}
	return fmt.Sprintf("แถว %d (%s): %s", e.SheetRow, e.Column, e.Message)
}

// normalizeHeader makes header matching forgiving about the "*" marker, casing
// and the stray spaces a user picks up while editing.
func normalizeHeader(text string) string {
	text = strings.Map(func(r rune) rune {
		if r == '*' || unicode.IsSpace(r) {
			return -1
		}
		return unicode.ToLower(r)
	}, text)
	return text
}

// Parse validates a worksheet against the template and returns its products.
// It reports every problem it finds rather than stopping at the first, so a
// user fixes one round of errors instead of discovering them one at a time.
func Parse(sheet *Sheet) ([]Row, []RowError, error) {
	if sheet == nil || len(sheet.Rows) == 0 {
		return nil, nil, fmt.Errorf("ชีตแรกของไฟล์ว่างเปล่า")
	}

	positions, err := mapHeaders(sheet.Rows[0])
	if err != nil {
		return nil, nil, err
	}

	body := sheet.Rows[1:]
	rows := make([]Row, 0, len(body))
	problems := make([]RowError, 0)
	seenCodes := map[string]int{}

	for index, raw := range body {
		sheetRow := index + 2 // worksheet rows are 1-based and row 1 is the header
		if isBlank(raw) {
			continue
		}
		if len(rows) >= MaxRows {
			problems = append(problems, RowError{
				SheetRow: sheetRow,
				Message:  fmt.Sprintf("เกิน %d รายการต่อไฟล์ กรุณาแบ่งไฟล์", MaxRows),
			})
			break
		}

		row := Row{SheetRow: sheetRow}
		before := len(problems)

		// Names are only checked for collisions once the catalog is in hand:
		// a row whose code already exists updates that product and its name is
		// left alone, so it cannot collide with anything. The repository does
		// that check inside the import transaction.
		row.Name = cellAt(raw, positions, colName)
		if row.Name == "" {
			problems = append(problems, RowError{sheetRow, Columns[colName].Header, "ต้องกรอกชื่อสินค้า"})
		}

		row.Price = parseAmount(cellAt(raw, positions, colPrice), sheetRow, colPrice, true, &problems)
		row.Cost = parseAmount(cellAt(raw, positions, colCost), sheetRow, colCost, false, &problems)

		minPriceText := cellAt(raw, positions, colMinPrice)
		if minPriceText == "" {
			row.MinPrice = round2(row.Price * MinPriceRatio)
		} else {
			row.MinPrice = parseAmount(minPriceText, sheetRow, colMinPrice, false, &problems)
		}
		if row.MinPrice > row.Price {
			problems = append(problems, RowError{
				SheetRow: sheetRow,
				Column:   Columns[colMinPrice].Header,
				Message:  "ราคาขายขั้นต่ำต้องไม่เกินราคาขาย",
			})
		}

		row.Qty = parseQty(cellAt(raw, positions, colQty), sheetRow, &problems)

		row.Code = cellAt(raw, positions, colCode)
		if row.Code != "" {
			if !isSafeCode(row.Code) {
				problems = append(problems, RowError{
					SheetRow: sheetRow,
					Column:   Columns[colCode].Header,
					Message:  "ใช้ได้เฉพาะ A-Z a-z 0-9 - _ เท่านั้น",
				})
			} else if previous, duplicate := seenCodes[strings.ToUpper(row.Code)]; duplicate {
				problems = append(problems, RowError{
					SheetRow: sheetRow,
					Column:   Columns[colCode].Header,
					Message:  fmt.Sprintf("รหัสซ้ำกับแถว %d ในไฟล์เดียวกัน", previous),
				})
			} else {
				seenCodes[strings.ToUpper(row.Code)] = sheetRow
			}
		}

		row.BarCode = cellAt(raw, positions, colBarcode)
		row.UnitID = cellAt(raw, positions, colUnit)
		if row.UnitID == "" {
			row.UnitID = DefaultUnitID
		}
		row.Shelf = cellAt(raw, positions, colShelf)
		row.Details = cellAt(raw, positions, colDetails)

		if len(problems) == before {
			rows = append(rows, row)
		}
	}

	if len(rows) == 0 && len(problems) == 0 {
		return nil, nil, fmt.Errorf("ไม่พบรายการสินค้าในไฟล์ (กรอกข้อมูลตั้งแต่แถวที่ 2 เป็นต้นไป)")
	}
	return rows, problems, nil
}

// mapHeaders locates each template column in the sheet's header row, so a user
// who reorders or adds columns still gets a correct import.
func mapHeaders(header []string) ([]int, error) {
	found := make(map[string]int, len(header))
	for index, text := range header {
		key := normalizeHeader(text)
		if key == "" {
			continue
		}
		if _, exists := found[key]; !exists {
			found[key] = index
		}
	}

	positions := make([]int, len(Columns))
	missing := make([]string, 0)
	for field, column := range Columns {
		index, ok := found[normalizeHeader(column.Header)]
		if !ok {
			positions[field] = -1
			if column.Required {
				missing = append(missing, column.Header)
			}
			continue
		}
		positions[field] = index
	}
	if len(missing) > 0 {
		return nil, fmt.Errorf(
			"หัวคอลัมน์ในแถวที่ 1 ไม่ครบ ขาด: %s — กรุณาใช้ไฟล์เทมเพลต",
			strings.Join(missing, ", "),
		)
	}
	return positions, nil
}

func cellAt(row []string, positions []int, field int) string {
	index := positions[field]
	if index < 0 || index >= len(row) {
		return ""
	}
	return strings.TrimSpace(row[index])
}

func isBlank(row []string) bool {
	for _, cell := range row {
		if strings.TrimSpace(cell) != "" {
			return false
		}
	}
	return true
}

// parseAmount reads a money cell. Thousands separators are tolerated because
// they survive a copy-paste out of another spreadsheet.
func parseAmount(text string, sheetRow, field int, required bool, problems *[]RowError) float64 {
	text = strings.ReplaceAll(text, ",", "")
	if text == "" {
		if required {
			*problems = append(*problems, RowError{sheetRow, Columns[field].Header, "ต้องกรอกตัวเลข"})
		}
		return 0
	}
	value, err := strconv.ParseFloat(text, 64)
	if err != nil {
		*problems = append(*problems, RowError{sheetRow, Columns[field].Header, "กรอกเป็นตัวเลขเท่านั้น"})
		return 0
	}
	if value < 0 {
		*problems = append(*problems, RowError{sheetRow, Columns[field].Header, "ต้องไม่ติดลบ"})
		return 0
	}
	return round2(value)
}

func parseQty(text string, sheetRow int, problems *[]RowError) int {
	text = strings.ReplaceAll(text, ",", "")
	if text == "" {
		return 0
	}
	value, err := strconv.ParseFloat(text, 64)
	if err != nil {
		*problems = append(*problems, RowError{sheetRow, Columns[colQty].Header, "กรอกเป็นตัวเลขเท่านั้น"})
		return 0
	}
	if value < 0 {
		*problems = append(*problems, RowError{sheetRow, Columns[colQty].Header, "ต้องไม่ติดลบ"})
		return 0
	}
	// Excel stores whole numbers as floats; round rather than truncate so 57.6
	// becomes 58 like the catalog seeds do.
	return int(value + 0.5)
}

func isSafeCode(code string) bool {
	for _, char := range code {
		switch {
		case char >= 'A' && char <= 'Z',
			char >= 'a' && char <= 'z',
			char >= '0' && char <= '9',
			char == '-', char == '_':
		default:
			return false
		}
	}
	return len(code) <= 64
}

func round2(value float64) float64 {
	if value < 0 {
		return -round2(-value)
	}
	return float64(int64(value*100+0.5)) / 100
}
