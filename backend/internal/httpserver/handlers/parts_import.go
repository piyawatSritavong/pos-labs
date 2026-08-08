package handlers

import (
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"

	"backend/internal/partsimport"
	"backend/internal/repository"

	"github.com/gin-gonic/gin"
)

// PartsImportHandler serves the spreadsheet template and takes filled-in
// copies of it back. Products created this way land in the single warehouse,
// exactly like the one-at-a-time create form.
type PartsImportHandler struct {
	parts repository.PartRepository
}

func NewPartsImportHandler(parts repository.PartRepository) *PartsImportHandler {
	return &PartsImportHandler{parts: parts}
}

// Template returns the blank workbook. It is deliberately unauthenticated: the
// file holds no business data, only column headers, and serving it without a
// token is what lets the client download it with a plain link.
func (h *PartsImportHandler) Template(c *gin.Context) {
	c.Header("Content-Disposition", fmt.Sprintf(
		`attachment; filename="parts-import-template.xlsx"; filename*=UTF-8''%s`,
		url.PathEscape(partsimport.TemplateFilename),
	))
	c.Header("Cache-Control", "no-cache")
	c.Data(http.StatusOK,
		"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
		partsimport.TemplateXLSX)
}

// Limits lets the client show the same numbers the server enforces instead of
// hard-coding its own copy.
func (h *PartsImportHandler) Limits(c *gin.Context) {
	columns := make([]gin.H, 0, len(partsimport.Columns))
	for _, column := range partsimport.Columns {
		columns = append(columns, gin.H{"header": column.Header, "required": column.Required})
	}
	c.JSON(http.StatusOK, gin.H{
		"maxFileBytes": partsimport.MaxFileBytes,
		"maxRows":      partsimport.MaxRows,
		"extensions":   []string{"xlsx"},
		"storeId":      partsimport.WarehouseStoreID,
		"columns":      columns,
	})
}

// Import reads an uploaded workbook and applies all of it, or none. A row whose
// รหัสสินค้า already exists restocks and reprices that product; the rest create
// new ones. Validation errors and catalog conflicts come back as a per-row list
// so the user can fix the spreadsheet in one pass.
func (h *PartsImportHandler) Import(c *gin.Context) {
	// Cap what the request body may consume before touching the multipart
	// reader, so an oversized upload is refused instead of buffered.
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, partsimport.MaxFileBytes+(1<<20))

	header, err := c.FormFile("file")
	if err != nil {
		if strings.Contains(err.Error(), "http: request body too large") {
			respondFileTooLarge(c)
			return
		}
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "missing_file",
			"message": "กรุณาแนบไฟล์ Excel (.xlsx)",
		})
		return
	}
	if !strings.HasSuffix(strings.ToLower(header.Filename), ".xlsx") {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "unsupported_file_type",
			"message": "รองรับเฉพาะไฟล์ Excel นามสกุล .xlsx เท่านั้น",
		})
		return
	}
	if header.Size > partsimport.MaxFileBytes {
		respondFileTooLarge(c)
		return
	}

	file, err := header.Open()
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "unreadable_file", "message": "เปิดไฟล์ไม่สำเร็จ"})
		return
	}
	defer file.Close()

	data, err := io.ReadAll(io.LimitReader(file, partsimport.MaxFileBytes+1))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "unreadable_file", "message": "อ่านไฟล์ไม่สำเร็จ"})
		return
	}
	if len(data) > partsimport.MaxFileBytes {
		respondFileTooLarge(c)
		return
	}

	sheet, err := partsimport.ReadFirstSheet(data)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_file", "message": err.Error()})
		return
	}

	rows, problems, err := partsimport.Parse(sheet)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_file", "message": err.Error()})
		return
	}
	if len(problems) > 0 {
		c.JSON(http.StatusUnprocessableEntity, gin.H{
			"error":   "invalid_rows",
			"message": fmt.Sprintf("พบข้อผิดพลาด %d จุด ยังไม่มีการบันทึกสินค้า", len(problems)),
			"rows":    problems,
		})
		return
	}

	input := make([]repository.PartImportRow, 0, len(rows))
	for _, row := range rows {
		input = append(input, repository.PartImportRow{
			SheetRow: row.SheetRow,
			Code:     row.Code,
			Name:     row.Name,
			BarCode:  row.BarCode,
			UnitID:   row.UnitID,
			Shelf:    row.Shelf,
			Details:  row.Details,
			Price:    row.Price,
			Cost:     row.Cost,
			MinPrice: row.MinPrice,
			Qty:      row.Qty,
		})
	}

	result, err := h.parts.ImportParts(c.Request.Context(), input)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "failed_to_import_parts",
			"message": err.Error(),
		})
		return
	}
	if len(result.Conflicts) > 0 {
		c.JSON(http.StatusConflict, gin.H{
			"error":   "conflicting_rows",
			"message": fmt.Sprintf("มี %d รายการที่ใช้ไม่ได้ ยังไม่มีการบันทึกสินค้า", len(result.Conflicts)),
			"rows":    result.Conflicts,
		})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"created":      result.Created,
		"updated":      result.Updated,
		"codes":        result.Codes,
		"updatedCodes": result.UpdatedCodes,
		"storeId":      partsimport.WarehouseStoreID,
		"message":      importSummary(result.Created, result.Updated),
	})
}

// importSummary says which of the two things happened, and stays honest when
// only one of them did.
func importSummary(created, updated int) string {
	switch {
	case created > 0 && updated > 0:
		return fmt.Sprintf("เพิ่มสินค้าใหม่ %d รายการ และอัปเดตของเดิม %d รายการ เข้าคลังหลัก",
			created, updated)
	case updated > 0:
		return fmt.Sprintf("อัปเดตสินค้าเดิม %d รายการ เข้าคลังหลัก", updated)
	default:
		return fmt.Sprintf("เพิ่มสินค้าเข้าคลังหลัก %d รายการ", created)
	}
}

func respondFileTooLarge(c *gin.Context) {
	c.JSON(http.StatusRequestEntityTooLarge, gin.H{
		"error": "file_too_large",
		"message": fmt.Sprintf("ไฟล์ใหญ่เกิน %d MB (รองรับประมาณ %d รายการต่อครั้ง)",
			partsimport.MaxFileBytes>>20, partsimport.MaxRows),
	})
}
