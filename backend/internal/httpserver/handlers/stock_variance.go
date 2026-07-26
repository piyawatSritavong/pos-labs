package handlers

import (
	"net/http"
	"strings"
	"time"

	"backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type StockVarianceHandler struct {
	counts repository.StockCountRepository
}

func NewStockVarianceHandler(counts repository.StockCountRepository) *StockVarianceHandler {
	return &StockVarianceHandler{counts: counts}
}

func (h *StockVarianceHandler) GetVariance(c *gin.Context) {
	countID := strings.TrimSpace(c.Query("countId"))
	if countID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_count_id", "message": "countId query parameter is required"})
		return
	}

	count, items, err := h.counts.GetByID(c.Request.Context(), countID)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "stock_count_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_stock_count"})
		return
	}
	if !canReadOperationalBranch(c, count.BranchID) {
		c.JSON(http.StatusForbidden, gin.H{"error": "stock_variance_access_denied"})
		return
	}

	itemOut := make([]gin.H, 0, len(items))
	for _, item := range items {
		itemOut = append(itemOut, gin.H{
			"partCode":   item.PartCode,
			"partName":   item.PartName,
			"partNameTh": item.PartNameTH,
			"systemQty":  item.SystemQty,
			"countedQty": item.CountedQty,
			"variance":   item.Variance,
		})
	}

	out := gin.H{
		"countId":  count.ID,
		"branchId": count.BranchID,
		"storeId":  count.StoreID,
		"status":   count.Status,
		"items":    itemOut,
	}

	if count.SubmittedAt != nil {
		out["submittedAt"] = count.SubmittedAt.Format(time.RFC3339)
	} else {
		out["submittedAt"] = nil
	}

	c.JSON(http.StatusOK, gin.H{"data": out})
}
