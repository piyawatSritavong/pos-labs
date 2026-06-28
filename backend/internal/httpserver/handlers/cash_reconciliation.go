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

type CashReconciliationHandler struct {
	recons      repository.CashReconciliationRepository
	dailyCloses repository.DailyCloseRepository
}

func NewCashReconciliationHandler(recons repository.CashReconciliationRepository, dailyCloses repository.DailyCloseRepository) *CashReconciliationHandler {
	return &CashReconciliationHandler{
		recons:      recons,
		dailyCloses: dailyCloses,
	}
}

func buildCashReconciliationOutput(cr *repository.CashReconciliation) gin.H {
	return gin.H{
		"id":             cr.ID,
		"dailyCloseId":   cr.DailyCloseID,
		"confirmedBy":    cr.ConfirmedBy,
		"expectedAmount": cr.ExpectedAmount,
		"actualAmount":   cr.ActualAmount,
		"difference":     cr.Difference,
		"notes":          cr.Notes,
		"createdAt":      cr.CreatedAt.Format(time.RFC3339),
		"branchId":       cr.BranchID,
		"posId":          cr.PosID,
		"closeDate":      cr.CloseDate.Format("2006-01-02"),
	}
}

func (h *CashReconciliationHandler) List(c *gin.Context) {
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

	recons, err := h.recons.List(c.Request.Context(), limit, offset, branchID)
	if err != nil {
		log.Printf("Error listing cash reconciliations: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_list_cash_reconciliations"})
		return
	}

	out := make([]gin.H, 0, len(recons))
	for _, cr := range recons {
		crc := cr
		out = append(out, buildCashReconciliationOutput(&crc))
	}

	c.JSON(http.StatusOK, gin.H{"data": out, "total": len(out)})
}

func (h *CashReconciliationHandler) Create(c *gin.Context) {
	userVal, _ := c.Get("user")
	user, _ := userVal.(*repository.User)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var req struct {
		DailyCloseID string  `json:"dailyCloseId" binding:"required"`
		ActualAmount float64 `json:"actualAmount" binding:"required"`
		Notes        string  `json:"notes"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": err.Error()})
		return
	}

	dailyClose, err := h.dailyCloses.GetByID(c.Request.Context(), strings.TrimSpace(req.DailyCloseID))
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "daily_close_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_daily_close"})
		return
	}

	if dailyClose.Status != "pending_reconciliation" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_status", "message": "Daily close must be in 'pending_reconciliation' status"})
		return
	}

	reconID, err := h.recons.GenerateCashReconciliationID(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_generate_reconciliation_id"})
		return
	}

	expectedAmount := dailyClose.NetAmount
	if dailyClose.FinalSummaryAmount != nil {
		expectedAmount = *dailyClose.FinalSummaryAmount
	}
	difference := req.ActualAmount - expectedAmount

	cr := &repository.CashReconciliation{
		ID:             reconID,
		DailyCloseID:   strings.TrimSpace(req.DailyCloseID),
		ConfirmedBy:    user.ID,
		ExpectedAmount: expectedAmount,
		ActualAmount:   req.ActualAmount,
		Difference:     difference,
		Notes:          req.Notes,
		CreatedAt:      time.Now().UTC(),
		BranchID:       dailyClose.BranchID,
		PosID:          dailyClose.PosID,
		CloseDate:      dailyClose.CloseDate,
	}

	if err := h.recons.Create(c.Request.Context(), cr); err != nil {
		log.Printf("Error creating cash reconciliation: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_create_cash_reconciliation"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"data": buildCashReconciliationOutput(cr)})
}

func (h *CashReconciliationHandler) GetByID(c *gin.Context) {
	id := strings.TrimSpace(c.Param("id"))
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_reconciliation_id"})
		return
	}

	cr, err := h.recons.GetByID(c.Request.Context(), id)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "cash_reconciliation_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_cash_reconciliation"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": buildCashReconciliationOutput(cr)})
}
