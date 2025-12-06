package handlers

import (
	"net/http"
	"strconv"

	"backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type POSHandler struct {
	pos repository.POSRepository
}

func NewPOSHandler(pos repository.POSRepository) *POSHandler {
	return &POSHandler{pos: pos}
}

func (h *POSHandler) List(c *gin.Context) {
	limit := 50
	offset := 0

	if v := c.Query("limit"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 && n <= 500 {
			limit = n
		}
	}
	if v := c.Query("offset"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n >= 0 {
			offset = n
		}
	}

	posList, err := h.pos.List(c.Request.Context(), limit, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_list_pos"})
		return
	}

	out := make([]gin.H, 0, len(posList))
	for _, p := range posList {
		out = append(out, gin.H{
			"posId":    p.POSID,
			"branchId": p.BranchID,
			"posName":  p.POSName,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"pos": out,
	})
}

func (h *POSHandler) Get(c *gin.Context) {
	id := c.Param("id")
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_pos_id"})
		return
	}

	pos, err := h.pos.GetByID(c.Request.Context(), id)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "pos_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_pos"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"posId":    pos.POSID,
		"branchId": pos.BranchID,
		"posName":  pos.POSName,
	})
}

func (h *POSHandler) Create(c *gin.Context) {
	var req struct {
		POSID    string `json:"posId" binding:"required"`
		BranchID string `json:"branchId" binding:"required"`
		POSName  string `json:"posName" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request"})
		return
	}

	pos := &repository.POS{
		POSID:    req.POSID,
		BranchID: req.BranchID,
		POSName:  req.POSName,
	}

	if err := h.pos.Create(c.Request.Context(), pos); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_create_pos"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"posId":    pos.POSID,
		"branchId": pos.BranchID,
		"posName":  pos.POSName,
	})
}

func (h *POSHandler) Update(c *gin.Context) {
	id := c.Param("id")
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_pos_id"})
		return
	}

	var req struct {
		BranchID string `json:"branchId" binding:"required"`
		POSName  string `json:"posName" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request"})
		return
	}

	pos := &repository.POS{
		POSID:    id,
		BranchID: req.BranchID,
		POSName:  req.POSName,
	}

	if err := h.pos.Update(c.Request.Context(), pos); err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "pos_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_update_pos"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"posId":    pos.POSID,
		"branchId": pos.BranchID,
		"posName":  pos.POSName,
	})
}

func (h *POSHandler) Delete(c *gin.Context) {
	id := c.Param("id")
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_pos_id"})
		return
	}

	if err := h.pos.Delete(c.Request.Context(), id); err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "pos_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_delete_pos"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "pos_deleted"})
}

