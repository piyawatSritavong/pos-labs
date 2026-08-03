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

var bangkokLocation = time.FixedZone("Asia/Bangkok", 7*60*60)

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
	// Accept a date range (dateFrom/dateTo). Falls back to the legacy single
	// `date` param. Window is [fromStart 00:00, toEnd+1day) in UTC.
	fromStr := c.Query("dateFrom")
	toStr := c.Query("dateTo")
	if fromStr == "" {
		fromStr = c.Query("date")
	}
	if toStr == "" {
		toStr = fromStr
	}
	if fromStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_date", "message": "dateFrom is required"})
		return
	}
	fromDate, err := parseDate(fromStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_date_format", "message": err.Error()})
		return
	}
	toDate, err := parseDate(toStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_date_format", "message": err.Error()})
		return
	}
	if toDate.Before(fromDate) {
		fromDate, toDate = toDate, fromDate
	}
	winStart := time.Date(fromDate.Year(), fromDate.Month(), fromDate.Day(), 0, 0, 0, 0, time.UTC)
	winEnd := time.Date(toDate.Year(), toDate.Month(), toDate.Day(), 0, 0, 0, 0, time.UTC).Add(24 * time.Hour)
	rangeLabel := fromDate.Format("2006-01-02")
	if toDate.Format("2006-01-02") != fromDate.Format("2006-01-02") {
		rangeLabel += "_to_" + toDate.Format("2006-01-02")
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
		billsWithItems, err := h.reports.GetBillsWithItemsByDateRange(ctx, winStart, winEnd)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_generate_report"})
			return
		}

		filename = fmt.Sprintf("bills_%s_items.csv", rangeLabel)
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
		bills, err := h.reports.GetBillsByDateRange(ctx, winStart, winEnd)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_generate_report"})
			return
		}

		filename = fmt.Sprintf("bills_%s.csv", rangeLabel)
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
		"receipt_name", "details", "cost", "price", "min_price", "image", "is_active",
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
			toString(p.MinPrice),
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
		"code", "part_code", "store_id", "branch_id", "shelf", "qty", "rop", "remarks",
		"cost", "price", "min_price",
	}

	var rows [][]string
	for _, a := range addresses {
		row := []string{
			a.Code,
			a.PartCode,
			a.StoreID,
			a.BranchID,
			a.Shelf,
			toString(a.Qty),
			toString(a.Rop),
			a.Remarks,
			toString(a.Cost),
			toString(a.Price),
			toString(a.MinPrice),
		}
		rows = append(rows, row)
	}

	writeCSV(c, filename, headers, rows)
}

func (h *ReportsHandler) IncomeReport(c *gin.Context) {
	if !canReadAllOperationalData(c) {
		c.JSON(http.StatusForbidden, gin.H{"error": "income_report_access_denied"})
		return
	}

	fromStr := c.Query("dateFrom")
	toStr := c.Query("dateTo")
	if fromStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_date", "message": "dateFrom is required"})
		return
	}
	if toStr == "" {
		toStr = fromStr
	}
	fromDate, err := time.ParseInLocation("2006-01-02", fromStr, bangkokLocation)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_date_from"})
		return
	}
	toDate, err := time.ParseInLocation("2006-01-02", toStr, bangkokLocation)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_date_to"})
		return
	}
	if toDate.Before(fromDate) {
		fromDate, toDate = toDate, fromDate
	}
	report, err := h.reports.GetIncomeReport(c.Request.Context(), fromDate.UTC(), toDate.AddDate(0, 0, 1).UTC())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_generate_income_report"})
		return
	}

	accounts := make([]gin.H, 0, len(report.Accounts))
	for _, account := range report.Accounts {
		accounts = append(accounts, gin.H{
			"userId":       account.UserID,
			"username":     account.Username,
			"name":         account.Name,
			"revenue":      account.Revenue,
			"returns":      account.Returns,
			"netRevenue":   account.NetRevenue,
			"soldCost":     account.SoldCost,
			"returnedCost": account.ReturnedCost,
			"netCost":      account.NetCost,
			"grossProfit":  account.GrossProfit,
			"expenses":     account.Expenses,
			"netProfit":    account.NetProfit,
			"result":       profitResult(account.NetProfit),
		})
	}
	expenses := make([]gin.H, 0, len(report.ExpenseDetails))
	for _, detail := range report.ExpenseDetails {
		expenses = append(expenses, gin.H{
			"id":                 detail.ID,
			"closeDate":          detail.CloseDate.Format("2006-01-02"),
			"createdAt":          detail.CreatedAt.Format(time.RFC3339),
			"userId":             detail.UserID,
			"username":           detail.Username,
			"name":               detail.Name,
			"branchId":           detail.BranchID,
			"posId":              detail.POSID,
			"fuelAmount":         detail.FuelAmount,
			"foodAmount":         detail.FoodAmount,
			"transferAmount":     detail.TransferAmount,
			"specialAmount":      detail.SpecialAmount,
			"tailDiscountAmount": detail.TailDiscountAmount,
			"finalSummaryAmount": detail.FinalSummaryAmount,
			"notes":              detail.Notes,
			"specialNote":        detail.SpecialNote,
			"totalExpense":       detail.TotalExpense,
		})
	}

	s := report.Summary
	c.JSON(http.StatusOK, gin.H{
		"dateFrom": fromDate.Format("2006-01-02"),
		"dateTo":   toDate.Format("2006-01-02"),
		"summary": gin.H{
			"revenue":      s.Revenue,
			"returns":      s.Returns,
			"netRevenue":   s.NetRevenue,
			"soldCost":     s.SoldCost,
			"returnedCost": s.ReturnedCost,
			"netCost":      s.NetCost,
			"grossProfit":  s.GrossProfit,
			"expenses":     s.Expenses,
			"netProfit":    s.NetProfit,
			"result":       profitResult(s.NetProfit),
		},
		"accounts":       accounts,
		"expenseDetails": expenses,
	})
}

func profitResult(value float64) string {
	if value < 0 {
		return "loss"
	}
	return "profit"
}
