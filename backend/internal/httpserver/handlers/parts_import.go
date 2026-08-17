package handlers

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

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

	// The file's own bytes are what identify it. A user who cannot remember
	// whether yesterday's upload went through gets told, rather than finding
	// out from doubled stock.
	digest := sha256.Sum256(data)
	fileHash := hex.EncodeToString(digest[:])
	previous, err := h.parts.FindImportsOfFile(c.Request.Context(), fileHash)
	if err != nil {
		previous = nil // history is not worth failing an import over
	}
	if len(previous) > 0 && !strings.EqualFold(c.Query("confirmDuplicate"), "true") {
		c.JSON(http.StatusConflict, gin.H{
			"error": "file_already_imported",
			"message": fmt.Sprintf(
				"ไฟล์นี้เคยนำเข้าแล้วเมื่อ %s โดย %s (เพิ่มใหม่ %d รายการ อัปเดต %d รายการ) "+
					"ถ้านำเข้าอีกครั้ง จำนวนจะถูกบวกซ้ำ",
				formatThaiTime(previous[0].CreatedAt), previous[0].CreatedByName,
				previous[0].Created, previous[0].Updated),
			"previousImports": importSummaryList(previous),
		})
		return
	}

	user := currentRequestUser(c)
	userID := ""
	if user != nil {
		userID = user.ID
	}
	result, err := h.parts.ImportParts(c.Request.Context(), input, repository.PartImportBatch{
		FileHash: fileHash,
		FileName: header.Filename,
		FileSize: len(data),
		UserID:   userID,
	})
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
		"batchId":      result.BatchID,
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

// History returns past imports, newest first, so "did we already load this
// file?" is answerable without guessing.
func (h *PartsImportHandler) History(c *gin.Context) {
	limit, offset := 20, 0
	if v, err := strconv.Atoi(c.Query("limit")); err == nil && v > 0 && v <= 200 {
		limit = v
	}
	if v, err := strconv.Atoi(c.Query("offset")); err == nil && v >= 0 {
		offset = v
	}
	batches, total, err := h.parts.ListImportBatches(c.Request.Context(), limit, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_list_imports"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"imports": importSummaryList(batches), "total": total})
}

// HistoryDetail returns the lines one import wrote.
func (h *PartsImportHandler) HistoryDetail(c *gin.Context) {
	batch, lines, err := h.parts.GetImportBatch(c.Request.Context(), strings.TrimSpace(c.Param("id")))
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "import_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_load_import"})
		return
	}
	items := make([]gin.H, 0, len(lines))
	for _, line := range lines {
		items = append(items, gin.H{
			"partCode": line.PartCode, "partName": line.PartName,
			"action": line.Action, "sheetRow": line.SheetRow, "qty": line.Qty,
			"qtyBefore": line.QtyBefore, "qtyAfter": line.QtyAfter,
			"cost": line.Cost, "price": line.Price,
		})
	}
	out := importBatchJSON(*batch)
	out["items"] = items
	c.JSON(http.StatusOK, out)
}

func importBatchJSON(s repository.PartImportSummary) gin.H {
	return gin.H{
		"id": s.ID, "fileName": s.FileName, "fileSize": s.FileSize,
		"fileHash": s.FileHash, "storeId": s.StoreID,
		"createdBy": s.CreatedByName, "createdAt": s.CreatedAt.Format(time.RFC3339),
		"createdAtLabel": formatThaiTime(s.CreatedAt),
		"created":        s.Created, "updated": s.Updated, "totalQty": s.TotalQty,
	}
}

func importSummaryList(items []repository.PartImportSummary) []gin.H {
	out := make([]gin.H, 0, len(items))
	for _, item := range items {
		out = append(out, importBatchJSON(item))
	}
	return out
}

// formatThaiTime renders a timestamp the way the staff reading it think about
// dates: local time, day first.
func formatThaiTime(at time.Time) string {
	return at.In(time.FixedZone("Asia/Bangkok", 7*60*60)).Format("02/01/2006 15:04")
}
