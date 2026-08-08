package partsimport

import (
	"archive/zip"
	"bytes"
	"encoding/xml"
	"fmt"
	"io"
	"path"
	"strconv"
	"strings"
)

// Enough of the XLSX format to read the first worksheet of a workbook the user
// filled in. Written against the standard library on purpose: the template is
// ours, the sheet is a flat grid of text and numbers, and a spreadsheet library
// would pull a large dependency tree into a service that needs none of it.

const (
	sheetMainNS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
	// A worksheet with more rows than this is not a product list; refuse it
	// before allocating for it.
	maxRows = 20000
	// Widest row the importer will look at. The template has 10 columns.
	maxColumns = 64
)

type workbookXML struct {
	Sheets []struct {
		Name    string `xml:"name,attr"`
		SheetID string `xml:"sheetId,attr"`
		RID     string `xml:"http://schemas.openxmlformats.org/officeDocument/2006/relationships id,attr"`
	} `xml:"sheets>sheet"`
}

type relationshipsXML struct {
	Relationships []struct {
		ID     string `xml:"Id,attr"`
		Target string `xml:"Target,attr"`
	} `xml:"Relationship"`
}

// Sheet is a worksheet flattened to strings. Empty trailing cells are dropped,
// so callers must index defensively.
type Sheet struct {
	Name string
	Rows [][]string
}

// ReadFirstSheet opens an XLSX payload and returns its first worksheet in
// workbook order. Numbers come back in their stored form ("650", "199.5"), not
// as Excel displays them.
func ReadFirstSheet(data []byte) (*Sheet, error) {
	reader, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil {
		return nil, fmt.Errorf("ไฟล์ไม่ใช่ไฟล์ Excel (.xlsx) ที่อ่านได้")
	}

	files := make(map[string]*zip.File, len(reader.File))
	for _, file := range reader.File {
		files[path.Clean(file.Name)] = file
	}

	sheetPath, sheetName, err := firstSheetPath(files)
	if err != nil {
		return nil, err
	}
	shared, err := readSharedStrings(files)
	if err != nil {
		return nil, err
	}
	rows, err := readSheetRows(files[sheetPath], shared)
	if err != nil {
		return nil, err
	}
	return &Sheet{Name: sheetName, Rows: rows}, nil
}

// firstSheetPath resolves the first <sheet> in workbook.xml through the
// workbook relationships. Sheet order in the workbook is what the user sees in
// Excel's tab bar; the file name (sheet1.xml) does not have to match it.
func firstSheetPath(files map[string]*zip.File) (sheetPath string, sheetName string, err error) {
	workbookFile, ok := files["xl/workbook.xml"]
	if !ok {
		return "", "", fmt.Errorf("ไฟล์ Excel ไม่สมบูรณ์ (ไม่พบ workbook)")
	}
	raw, err := readAll(workbookFile)
	if err != nil {
		return "", "", err
	}
	var workbook workbookXML
	if err := xml.Unmarshal(raw, &workbook); err != nil {
		return "", "", fmt.Errorf("ไฟล์ Excel ไม่สมบูรณ์ (workbook เสียหาย)")
	}
	if len(workbook.Sheets) == 0 {
		return "", "", fmt.Errorf("ไฟล์ Excel ไม่มีชีตข้อมูล")
	}
	first := workbook.Sheets[0]

	targets := map[string]string{}
	if relsFile, ok := files["xl/_rels/workbook.xml.rels"]; ok {
		raw, err := readAll(relsFile)
		if err != nil {
			return "", "", err
		}
		var rels relationshipsXML
		if err := xml.Unmarshal(raw, &rels); err == nil {
			for _, rel := range rels.Relationships {
				targets[rel.ID] = rel.Target
			}
		}
	}

	target := targets[first.RID]
	if target == "" {
		target = "worksheets/sheet1.xml"
	}
	if strings.HasPrefix(target, "/") {
		sheetPath = path.Clean(strings.TrimPrefix(target, "/"))
	} else {
		sheetPath = path.Clean(path.Join("xl", target))
	}
	if _, ok := files[sheetPath]; !ok {
		return "", "", fmt.Errorf("ไฟล์ Excel ไม่สมบูรณ์ (ไม่พบชีตแรก)")
	}
	return sheetPath, first.Name, nil
}

func readSharedStrings(files map[string]*zip.File) ([]string, error) {
	file, ok := files["xl/sharedStrings.xml"]
	if !ok {
		return nil, nil // a workbook written with inline strings has none
	}
	raw, err := readAll(file)
	if err != nil {
		return nil, err
	}
	var doc struct {
		Items []struct {
			Text string   `xml:"t"`
			Runs []string `xml:"r>t"`
		} `xml:"si"`
	}
	if err := xml.Unmarshal(raw, &doc); err != nil {
		return nil, fmt.Errorf("ไฟล์ Excel ไม่สมบูรณ์ (ตารางข้อความเสียหาย)")
	}
	shared := make([]string, 0, len(doc.Items))
	for _, item := range doc.Items {
		if len(item.Runs) > 0 {
			shared = append(shared, strings.Join(item.Runs, ""))
			continue
		}
		shared = append(shared, item.Text)
	}
	return shared, nil
}

// readSheetRows streams the worksheet so a large file never lands in memory
// twice. Cells carry their address ("C7"), so a row with gaps still lines its
// values up under the right headers.
func readSheetRows(file *zip.File, shared []string) ([][]string, error) {
	handle, err := file.Open()
	if err != nil {
		return nil, fmt.Errorf("อ่านไฟล์ Excel ไม่สำเร็จ")
	}
	defer handle.Close()

	decoder := xml.NewDecoder(handle)
	rows := make([][]string, 0, 256)
	var current []string
	inRow := false

	for {
		token, err := decoder.Token()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("ไฟล์ Excel ไม่สมบูรณ์ (ชีตเสียหาย)")
		}
		start, ok := token.(xml.StartElement)
		if !ok {
			if end, ok := token.(xml.EndElement); ok && inRow &&
				end.Name.Local == "row" && end.Name.Space == sheetMainNS {
				rows = append(rows, current)
				current = nil
				inRow = false
				if len(rows) > maxRows {
					return nil, fmt.Errorf("ไฟล์มีมากกว่า %d แถว", maxRows)
				}
			}
			continue
		}
		if start.Name.Space != sheetMainNS {
			continue
		}
		switch start.Name.Local {
		case "row":
			inRow = true
			current = nil
		case "c":
			if !inRow {
				_ = decoder.Skip()
				continue
			}
			column, value, err := decodeCell(decoder, start, shared)
			if err != nil {
				return nil, err
			}
			if column >= maxColumns {
				continue
			}
			for len(current) <= column {
				current = append(current, "")
			}
			current[column] = value
		}
	}
	return rows, nil
}

// decodeCell consumes one <c> element and returns its zero-based column index
// and text. It must always consume to the matching </c>.
func decodeCell(decoder *xml.Decoder, start xml.StartElement, shared []string) (int, string, error) {
	var reference, cellType string
	for _, attr := range start.Attr {
		switch attr.Name.Local {
		case "r":
			reference = attr.Value
		case "t":
			cellType = attr.Value
		}
	}

	var value, inline strings.Builder
	depth := 0
	for {
		token, err := decoder.Token()
		if err != nil {
			return 0, "", fmt.Errorf("ไฟล์ Excel ไม่สมบูรณ์ (เซลล์เสียหาย)")
		}
		switch element := token.(type) {
		case xml.StartElement:
			depth++
			if element.Name.Space == sheetMainNS {
				switch element.Name.Local {
				case "v":
					text, err := readElementText(decoder)
					if err != nil {
						return 0, "", err
					}
					value.WriteString(text)
					depth--
				case "t":
					text, err := readElementText(decoder)
					if err != nil {
						return 0, "", err
					}
					inline.WriteString(text)
					depth--
				}
			}
		case xml.EndElement:
			if depth == 0 && element.Name.Local == "c" {
				text := value.String()
				if cellType == "inlineStr" || inline.Len() > 0 {
					text = inline.String()
				} else if cellType == "s" {
					index, err := strconv.Atoi(strings.TrimSpace(text))
					if err != nil || index < 0 || index >= len(shared) {
						text = ""
					} else {
						text = shared[index]
					}
				} else if cellType == "b" {
					if strings.TrimSpace(text) == "1" {
						text = "TRUE"
					} else {
						text = "FALSE"
					}
				}
				return columnIndex(reference), strings.TrimSpace(text), nil
			}
			depth--
		}
	}
}

func readElementText(decoder *xml.Decoder) (string, error) {
	var builder strings.Builder
	for {
		token, err := decoder.Token()
		if err != nil {
			return "", fmt.Errorf("ไฟล์ Excel ไม่สมบูรณ์")
		}
		switch element := token.(type) {
		case xml.CharData:
			builder.Write(element)
		case xml.EndElement:
			return builder.String(), nil
		case xml.StartElement:
			if err := decoder.Skip(); err != nil {
				return "", fmt.Errorf("ไฟล์ Excel ไม่สมบูรณ์")
			}
		}
	}
}

// columnIndex turns "C7" into 2. An unreadable reference falls back to 0 so a
// malformed cell never shifts the rest of the row.
func columnIndex(reference string) int {
	index := 0
	for _, char := range reference {
		if char >= 'A' && char <= 'Z' {
			index = index*26 + int(char-'A') + 1
			continue
		}
		if char >= 'a' && char <= 'z' {
			index = index*26 + int(char-'a') + 1
			continue
		}
		break
	}
	if index == 0 {
		return 0
	}
	return index - 1
}

func readAll(file *zip.File) ([]byte, error) {
	handle, err := file.Open()
	if err != nil {
		return nil, fmt.Errorf("อ่านไฟล์ Excel ไม่สำเร็จ")
	}
	defer handle.Close()
	return io.ReadAll(io.LimitReader(handle, 32<<20))
}
