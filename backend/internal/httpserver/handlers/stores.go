package handlers

import (
	"net/http"
	"strings"

	"backend/internal/repository"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
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
		})
	}
	c.JSON(http.StatusOK, gin.H{"stores": out})
}

// Create adds a new store (the "เพิ่มคลังใหม่" button). id is auto-generated
// when not supplied; labelTh + branchId are required.
func (h *StoreHandler) Create(c *gin.Context) {
	var req struct {
		ID        string `json:"id"`
		BranchID  string `json:"branchId"`
		Label     string `json:"label"`
		LabelTh   string `json:"labelTh"`
		IsDefault bool   `json:"isDefault"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": err.Error()})
		return
	}
	branchID := strings.TrimSpace(req.BranchID)
	labelTh := strings.TrimSpace(req.LabelTh)
	if branchID == "" || labelTh == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_fields", "message": "branchId and labelTh are required"})
		return
	}
	id := strings.TrimSpace(req.ID)
	if id == "" {
		id = "store_" + strings.ReplaceAll(uuid.New().String(), "-", "")[:12]
	}
	label := strings.TrimSpace(req.Label)
	if label == "" {
		label = labelTh
	}
	err := h.stores.CreateStore(c.Request.Context(), repository.StoreInput{
		ID: id, BranchID: branchID, Label: label, LabelTH: labelTh, IsDefault: req.IsDefault,
	})
	if err != nil {
		if strings.Contains(err.Error(), "duplicate") || strings.Contains(err.Error(), "unique") {
			c.JSON(http.StatusConflict, gin.H{"error": "store_exists", "message": "รหัสคลังนี้มีอยู่แล้ว"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_create_store", "message": err.Error()})
		return
	}
	c.JSON(http.StatusCreated, gin.H{"id": id, "branchId": branchID, "labelTh": labelTh})
}
