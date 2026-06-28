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

type StockCountHandler struct {
	counts   repository.StockCountRepository
	branches repository.BranchRepository
}

func NewStockCountHandler(counts repository.StockCountRepository, branches repository.BranchRepository) *StockCountHandler {
	return &StockCountHandler{
		counts:   counts,
		branches: branches,
	}
}

func buildStockCountOutput(count *repository.StockCount, items []repository.StockCountItem) gin.H {
	itemOut := make([]gin.H, 0, len(items))
	for _, item := range items {
		itemOut = append(itemOut, gin.H{
			"countId":    item.CountID,
			"partCode":   item.PartCode,
			"systemQty":  item.SystemQty,
			"countedQty": item.CountedQty,
			"variance":   item.Variance,
			"partName":   item.PartName,
			"partNameTh": item.PartNameTH,
		})
	}

	out := gin.H{
		"id":        count.ID,
		"branchId":  count.BranchID,
		"storeId":   count.StoreID,
		"countedBy": count.CountedBy,
		"status":    count.Status,
		"notes":     count.Notes,
		"createdAt": count.CreatedAt.Format(time.RFC3339),
		"items":     itemOut,
	}

	if count.SubmittedAt != nil {
		out["submittedAt"] = count.SubmittedAt.Format(time.RFC3339)
	} else {
		out["submittedAt"] = nil
	}

	return out
}

func (h *StockCountHandler) List(c *gin.Context) {
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

	var branchID, status *string
	if raw := strings.TrimSpace(c.Query("branchId")); raw != "" {
		branchID = &raw
	}
	if raw := strings.TrimSpace(c.Query("status")); raw != "" {
		status = &raw
	}

	counts, err := h.counts.List(c.Request.Context(), limit, offset, branchID, status)
	if err != nil {
		log.Printf("Error listing stock counts: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_list_stock_counts"})
		return
	}

	out := make([]gin.H, 0, len(counts))
	for _, count := range counts {
		cc := count
		out = append(out, buildStockCountOutput(&cc, nil))
	}

	c.JSON(http.StatusOK, gin.H{"data": out, "total": len(out)})
}

func (h *StockCountHandler) Create(c *gin.Context) {
	userVal, _ := c.Get("user")
	user, _ := userVal.(*repository.User)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var req struct {
		BranchID string `json:"branchId" binding:"required"`
		StoreID  string `json:"storeId"` // optional — resolved from default store if empty
		Notes    string `json:"notes"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": err.Error()})
		return
	}

	storeID := strings.TrimSpace(req.StoreID)
	if storeID == "" {
		// Resolve the default store for this branch
		stores, err := h.branches.GetStoresByBranchID(c.Request.Context(), strings.TrimSpace(req.BranchID))
		if err != nil || len(stores) == 0 {
			c.JSON(http.StatusBadRequest, gin.H{
				"error":   "store_not_found",
				"message": "ไม่พบคลังสินค้าของสาขานี้ กรุณาระบุ storeId",
			})
			return
		}
		// Prefer default store; fall back to first available
		storeID = stores[0].ID
		for _, s := range stores {
			if s.IsDefault {
				storeID = s.ID
				break
			}
		}
	}

	countID, err := h.counts.GenerateStockCountID(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_generate_count_id"})
		return
	}

	count := &repository.StockCount{
		ID:        countID,
		BranchID:  strings.TrimSpace(req.BranchID),
		StoreID:   storeID,
		CountedBy: user.ID,
		Status:    "draft",
		Notes:     req.Notes,
		CreatedAt: time.Now().UTC(),
	}

	if err := h.counts.Create(c.Request.Context(), count); err != nil {
		log.Printf("Error creating stock count: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_create_stock_count"})
		return
	}

	createdCount, createdItems, err := h.counts.GetByID(c.Request.Context(), countID)
	if err != nil {
		c.JSON(http.StatusCreated, gin.H{"data": buildStockCountOutput(count, nil)})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"data": buildStockCountOutput(createdCount, createdItems)})
}

func (h *StockCountHandler) GetByID(c *gin.Context) {
	id := strings.TrimSpace(c.Param("id"))
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_count_id"})
		return
	}

	count, items, err := h.counts.GetByID(c.Request.Context(), id)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "stock_count_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_stock_count"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": buildStockCountOutput(count, items)})
}

func (h *StockCountHandler) UpdateItems(c *gin.Context) {
	id := strings.TrimSpace(c.Param("id"))
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_count_id"})
		return
	}

	var req struct {
		Items []struct {
			PartCode   string `json:"partCode" binding:"required"`
			CountedQty int    `json:"countedQty" binding:"min=0"`
		} `json:"items" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": err.Error()})
		return
	}

	count, _, err := h.counts.GetByID(c.Request.Context(), id)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "stock_count_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_stock_count"})
		return
	}

	if count.Status != "draft" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_status", "message": "Stock count must be in 'draft' status to update items"})
		return
	}

	items := make([]repository.StockCountItem, 0, len(req.Items))
	for _, item := range req.Items {
		items = append(items, repository.StockCountItem{
			CountID:    id,
			PartCode:   strings.TrimSpace(item.PartCode),
			CountedQty: item.CountedQty,
		})
	}

	if err := h.counts.UpdateItemCounts(c.Request.Context(), id, items); err != nil {
		log.Printf("Error updating stock count items: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_update_stock_count_items"})
		return
	}

	updatedCount, updatedItems, err := h.counts.GetByID(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusOK, gin.H{"data": gin.H{"id": id}})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": buildStockCountOutput(updatedCount, updatedItems)})
}

func (h *StockCountHandler) Submit(c *gin.Context) {
	id := strings.TrimSpace(c.Param("id"))
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_count_id"})
		return
	}

	count, items, err := h.counts.GetByID(c.Request.Context(), id)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "stock_count_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_stock_count"})
		return
	}

	if count.Status != "draft" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_status", "message": "Stock count must be in 'draft' status to submit"})
		return
	}

	if err := h.counts.Submit(c.Request.Context(), id); err != nil {
		log.Printf("Error submitting stock count: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_submit_stock_count"})
		return
	}

	updatedCount, updatedItems, err := h.counts.GetByID(c.Request.Context(), id)
	if err != nil {
		// Return what we have, just patched
		now := time.Now().UTC()
		count.Status = "submitted"
		count.SubmittedAt = &now
		c.JSON(http.StatusOK, gin.H{"data": buildStockCountOutput(count, items)})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": buildStockCountOutput(updatedCount, updatedItems)})
}
