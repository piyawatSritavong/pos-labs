package handlers

import (
	"net/http"

	"backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type StoreHandler struct {
	stores repository.StoreRepository
}

func NewStoreHandler(stores repository.StoreRepository) *StoreHandler {
	return &StoreHandler{stores: stores}
}

// List returns the canonical store list (with branch names). Both the Parts and
// Addresses pages use this so their store dropdowns are always identical.
func (h *StoreHandler) List(c *gin.Context) {
	items, err := h.stores.ListStores(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_list_stores"})
		return
	}
	out := make([]gin.H, 0, len(items))
	for _, s := range items {
		out = append(out, gin.H{
			"id":           s.ID,
			"branchId":     s.BranchID,
			"branchName":   s.BranchName,
			"branchNameTh": s.BranchNameTH,
			"label":        s.Label,
			"labelTh":      s.LabelTH,
			"isDefault":    s.IsDefault,
			"locationType": s.LocationType,
		})
	}
	c.JSON(http.StatusOK, gin.H{"stores": out})
}
