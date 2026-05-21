package handlers

import (
	"encoding/csv"
	"fmt"
	"net/http"
	"strconv"
	"time"

	"backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type ReportsHandler struct {
	reports repository.ReportRepository
}

func NewReportsHandler(reports repository.ReportRepository) *ReportsHandler {
	return &ReportsHandler{reports: reports}
}

// parseDate parses date string in ISO format (RFC3339) or yyyy-mm-dd format
func parseDate(dateStr string) (time.Time, error) {
	// Try ISO 8601 / RFC3339 format first
	if t, err := time.Parse(time.RFC3339, dateStr); err == nil {
		return t, nil
	}

	// Try yyyy-mm-dd format
	if t, err := time.Parse("2006-01-02", dateStr); err == nil {
		return t, nil
	}

	return time.Time{}, fmt.Errorf("invalid date format, expected ISO string or yyyy-mm-dd")
}

// writeCSV writes CSV data to response with proper headers
func writeCSV(c *gin.Context, filename string, headers []string, rows [][]string) {
	c.Header("Content-Type", "text/csv; charset=utf-8")
	c.Header("Content-Disposition", fmt.Sprintf(`attachment; filename="%s"`, filename))

	// Write UTF-8 BOM for Excel compatibility
	c.Writer.WriteString("\ufeff")

	writer := csv.NewWriter(c.Writer)
	defer writer.Flush()

	// Write headers
	if err := writer.Write(headers); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_write_csv"})
		return
	}

	// Write rows
	for _, row := range rows {
		if err := writer.Write(row); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_write_csv"})
			return
		}
	}
}

// toString converts a value to string, handling nil/null values
func toString(v interface{}) string {
	if v == nil {
		return ""
	}
	switch val := v.(type) {
	case string:
		return val
	case int:
		return strconv.Itoa(val)
	case int64:
		return strconv.FormatInt(val, 10)
	case float64:
		return strconv.FormatFloat(val, 'f', 2, 64)
	case bool:
		return strconv.FormatBool(val)
	case time.Time:
		return val.Format(time.RFC3339)
	default:
		return fmt.Sprintf("%v", val)
	}
}

// BillsReport handles GET /reports/bills?date=YYYY-MM-DD&items=0|1
func (h *ReportsHandler) BillsReport(c *gin.Context) {
	// Get and validate date parameter
	dateStr := c.Query("date")
	if dateStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_date", "message": "Date parameter is required"})
		return
	}

	date, err := parseDate(dateStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "invalid_date_format",
			"message": err.Error(),
		})
		return
	}

	// Get items parameter (default: 0/false)
	itemsParam := c.DefaultQuery("items", "0")
	includeItems := itemsParam == "1" || itemsParam == "true"

	ctx := c.Request.Context()

	var filename string
	var headers []string
	var rows [][]string

	if includeItems {
		// Get bills with items
		billsWithItems, err := h.reports.GetBillsWithItemsByDate(ctx, date)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_generate_report"})
			return
		}

		filename = fmt.Sprintf("bills_%s_items.csv", date.Format("2006-01-02"))
		headers = []string{
			"id", "branch_id", "pos_id", "status", "payment_method", "payment_ref",
			"member_id", "customer_name", "purchase_amount", "total_discount",
			"total_amount", "vat_amount", "xvat_amount", "created_at", "updated_at",
			"created_by", "updated_by", "part_code", "address_code", "name", "price", "qty",
		}

		for _, bi := range billsWithItems {
			row := []string{
				bi.ID,
				bi.BranchID,
				bi.POSID,
				bi.Status,
				bi.PaymentMethod,
				bi.PaymentRef,
				bi.MemberID,
				bi.CustomerName,
				toString(bi.PurchaseAmount),
				toString(bi.TotalDiscount),
				toString(bi.TotalAmount),
				toString(bi.VATAmount),
				toString(bi.XVATAmount),
				bi.CreatedAt.Format(time.RFC3339),
				bi.UpdatedAt.Format(time.RFC3339),
				bi.CreatedBy,
				bi.UpdatedBy,
				bi.PartCode,
				bi.AddressCode,
				bi.Name,
				toString(bi.Price),
				toString(bi.Qty),
			}
			rows = append(rows, row)
		}
	} else {
		// Get bills without items
		bills, err := h.reports.GetBillsByDate(ctx, date)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_generate_report"})
			return
		}

		filename = fmt.Sprintf("bills_%s.csv", date.Format("2006-01-02"))
		headers = []string{
			"id", "branch_id", "pos_id", "status", "payment_method", "payment_ref",
			"member_id", "customer_name", "purchase_amount", "total_discount",
			"total_amount", "vat_amount", "xvat_amount", "created_at", "updated_at",
			"created_by", "updated_by",
		}

		for _, b := range bills {
			row := []string{
				b.ID,
				b.BranchID,
				b.POSID,
				b.Status,
				b.PaymentMethod,
				b.PaymentRef,
				b.MemberID,
				b.CustomerName,
				toString(b.PurchaseAmount),
				toString(b.TotalDiscount),
				toString(b.TotalAmount),
				toString(b.VATAmount),
				toString(b.XVATAmount),
				b.CreatedAt.Format(time.RFC3339),
				b.UpdatedAt.Format(time.RFC3339),
				b.CreatedBy,
				b.UpdatedBy,
			}
			rows = append(rows, row)
		}
	}

	writeCSV(c, filename, headers, rows)
}

// PartsReport handles GET /reports/parts
func (h *ReportsHandler) PartsReport(c *gin.Context) {
	ctx := c.Request.Context()

	parts, err := h.reports.GetAllParts(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_generate_report"})
		return
	}

	filename := fmt.Sprintf("parts_%s.csv", time.Now().Format("2006-01-02_150405"))
	headers := []string{
		"code", "bar_code", "category_id", "unit_id", "name", "name_th",
		"receipt_name", "details", "cost", "price", "image", "is_active",
	}

	var rows [][]string
	for _, p := range parts {
		row := []string{
			p.Code,
			p.BarCode,
			p.CategoryID,
			p.UnitID,
			p.Name,
			p.NameTH,
			p.ReceiptName,
			p.Details,
			toString(p.Cost),
			toString(p.Price),
			p.Image,
			toString(p.IsActive),
		}
		rows = append(rows, row)
	}

	writeCSV(c, filename, headers, rows)
}

// InventoryReport handles GET /reports/inventory
func (h *ReportsHandler) InventoryReport(c *gin.Context) {
	ctx := c.Request.Context()

	addresses, err := h.reports.GetAllAddresses(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_generate_report"})
		return
	}

	filename := fmt.Sprintf("inventory_%s.csv", time.Now().Format("2006-01-02_150405"))
	headers := []string{
		"code", "part_code", "store_id", "shelf", "qty", "min", "max", "rop", "remarks",
	}

	var rows [][]string
	for _, a := range addresses {
		row := []string{
			a.Code,
			a.PartCode,
			a.StoreID,
			a.Shelf,
			toString(a.Qty),
			toString(a.Min),
			toString(a.Max),
			toString(a.Rop),
			a.Remarks,
		}
		rows = append(rows, row)
	}

	writeCSV(c, filename, headers, rows)
}
