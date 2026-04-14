package handlers

import (
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type DailyCloseHandler struct {
	closes   repository.DailyCloseRepository
	branches repository.BranchRepository
}

func NewDailyCloseHandler(closes repository.DailyCloseRepository, branches repository.BranchRepository) *DailyCloseHandler {
	return &DailyCloseHandler{
		closes:   closes,
		branches: branches,
	}
}

func buildDailyCloseOutput(dc *repository.DailyClose) gin.H {
	return gin.H{
		"id":            dc.ID,
		"branchId":      dc.BranchID,
		"posId":         dc.PosID,
		"closedBy":      dc.ClosedBy,
		"closeDate":     dc.CloseDate.Format("2006-01-02"),
		"totalSales":    dc.TotalSales,
		"totalCash":     dc.TotalCash,
		"totalTransfer": dc.TotalTransfer,
		"totalBills":    dc.TotalBills,
		"totalReturns":  dc.TotalReturns,
		"netAmount":     dc.NetAmount,
		"status":        dc.Status,
		"notes":         dc.Notes,
		"createdAt":     dc.CreatedAt.Format(time.RFC3339),
	}
}

func (h *DailyCloseHandler) List(c *gin.Context) {
	limit := 50
	offset := 0
	if raw := c.Query("limit"); raw != "" {
		if parsed, err := strconv.Atoi(raw); err == nil && parsed > 0 {
			limit = parsed
		}
	}
	if raw := c.Query("offset"); raw != "" {
		if parsed, err := strconv.Atoi(raw); err == nil && parsed >= 0 {
			offset = parsed
		}
	}

	var branchID *string
	if raw := strings.TrimSpace(c.Query("branchId")); raw != "" {
		branchID = &raw
	}

	var dateFrom, dateTo *time.Time
	if raw := strings.TrimSpace(c.Query("dateFrom")); raw != "" {
		t, err := time.Parse("2006-01-02", raw)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_date_from", "message": "dateFrom must be in YYYY-MM-DD format"})
			return
		}
		dateFrom = &t
	}
	if raw := strings.TrimSpace(c.Query("dateTo")); raw != "" {
		t, err := time.Parse("2006-01-02", raw)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_date_to", "message": "dateTo must be in YYYY-MM-DD format"})
			return
		}
		dateTo = &t
	}

	closes, err := h.closes.List(c.Request.Context(), limit, offset, branchID, dateFrom, dateTo)
	if err != nil {
		log.Printf("Error listing daily closes: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_list_daily_closes"})
		return
	}

	out := make([]gin.H, 0, len(closes))
	for _, dc := range closes {
		dcc := dc
		out = append(out, buildDailyCloseOutput(&dcc))
	}

	c.JSON(http.StatusOK, gin.H{"data": out, "total": len(out)})
}

func (h *DailyCloseHandler) GetSummary(c *gin.Context) {
	branchID := strings.TrimSpace(c.Query("branchId"))
	posID := strings.TrimSpace(c.Query("posId"))

	if branchID == "" || posID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_params", "message": "branchId and posId are required"})
		return
	}

	// Get today in UTC+7
	utc7 := time.Now().UTC().Add(7 * time.Hour)
	today := time.Date(utc7.Year(), utc7.Month(), utc7.Day(), 0, 0, 0, 0, time.UTC)

	summary, err := h.closes.GetSummary(c.Request.Context(), branchID, posID, today)
	if err != nil {
		log.Printf("Error getting daily summary: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_summary"})
		return
	}

	alreadyClosed, err := h.closes.ExistsByBranchPosDate(c.Request.Context(), branchID, posID, today)
	if err != nil {
		log.Printf("Error checking daily close existence: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_check_close_status"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data": gin.H{
			"branchId":      branchID,
			"posId":         posID,
			"closeDate":     today.Format("2006-01-02"),
			"totalSales":    summary.TotalSales,
			"totalCash":     summary.TotalCash,
			"totalTransfer": summary.TotalTransfer,
			"totalBills":    summary.TotalBills,
			"totalReturns":  summary.TotalReturns,
			"netAmount":     summary.NetAmount,
			"alreadyClosed": alreadyClosed,
		},
	})
}

func (h *DailyCloseHandler) Create(c *gin.Context) {
	userVal, _ := c.Get("user")
	user, _ := userVal.(*repository.User)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var req struct {
		BranchID string `json:"branchId" binding:"required"`
		PosID    string `json:"posId" binding:"required"`
		Notes    string `json:"notes"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": err.Error()})
		return
	}

	branchID := strings.TrimSpace(req.BranchID)
	posID := strings.TrimSpace(req.PosID)

	// Get today in UTC+7
	utc7 := time.Now().UTC().Add(7 * time.Hour)
	today := time.Date(utc7.Year(), utc7.Month(), utc7.Day(), 0, 0, 0, 0, time.UTC)

	alreadyClosed, err := h.closes.ExistsByBranchPosDate(c.Request.Context(), branchID, posID, today)
	if err != nil {
		log.Printf("Error checking daily close existence: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_check_close_status"})
		return
	}
	if alreadyClosed {
		c.JSON(http.StatusConflict, gin.H{"error": "already_closed", "message": "Daily close already exists for this branch/pos today"})
		return
	}

	summary, err := h.closes.GetSummary(c.Request.Context(), branchID, posID, today)
	if err != nil {
		log.Printf("Error getting daily summary: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_summary"})
		return
	}

	closeID, err := h.closes.GenerateDailyCloseID(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_generate_close_id"})
		return
	}

	dc := &repository.DailyClose{
		ID:            closeID,
		BranchID:      branchID,
		PosID:         posID,
		ClosedBy:      user.ID,
		CloseDate:     today,
		TotalSales:    summary.TotalSales,
		TotalCash:     summary.TotalCash,
		TotalTransfer: summary.TotalTransfer,
		TotalBills:    summary.TotalBills,
		TotalReturns:  summary.TotalReturns,
		NetAmount:     summary.NetAmount,
		Status:        "pending_reconciliation",
		Notes:         req.Notes,
		CreatedAt:     time.Now().UTC(),
	}

	if err := h.closes.Create(c.Request.Context(), dc); err != nil {
		log.Printf("Error creating daily close: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_create_daily_close"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"data": buildDailyCloseOutput(dc)})
}

func (h *DailyCloseHandler) GetByID(c *gin.Context) {
	id := strings.TrimSpace(c.Param("id"))
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_close_id"})
		return
	}

	dc, err := h.closes.GetByID(c.Request.Context(), id)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "daily_close_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_daily_close"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": buildDailyCloseOutput(dc)})
}
