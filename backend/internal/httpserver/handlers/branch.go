package handlers

import (
	"net/http"
	"strconv"

	"backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type BranchHandler struct {
	branch repository.BranchRepository
}

func NewBranchHandler(branch repository.BranchRepository) *BranchHandler {
	return &BranchHandler{branch: branch}
}

func (h *BranchHandler) List(c *gin.Context) {
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

	branches, err := h.branch.List(c.Request.Context(), limit, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_list_branches"})
		return
	}

	out := make([]gin.H, 0, len(branches))
	for _, b := range branches {
		out = append(out, gin.H{
			"branchId":       b.BranchID,
			"companyId":      b.CompanyID,
			"branchName":     b.BranchName,
			"branchNameTh":   b.BranchNameTH,
			"branchAddress":  b.BranchAddress,
			"branchAddressTh": b.BranchAddressTH,
			"phone":          b.Phone,
			"email":          b.Email,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"branches": out,
	})
}

func (h *BranchHandler) Get(c *gin.Context) {
	id := c.Param("id")
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_branch_id"})
		return
	}

	branch, err := h.branch.GetByID(c.Request.Context(), id)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "branch_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_branch"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"branchId":       branch.BranchID,
		"companyId":      branch.CompanyID,
		"branchName":     branch.BranchName,
		"branchNameTh":   branch.BranchNameTH,
		"branchAddress":  branch.BranchAddress,
		"branchAddressTh": branch.BranchAddressTH,
		"phone":          branch.Phone,
		"email":          branch.Email,
	})
}

func (h *BranchHandler) Create(c *gin.Context) {
	var req struct {
		BranchID        string  `json:"branchId" binding:"required"`
		CompanyID       string  `json:"companyId" binding:"required"`
		BranchName      string  `json:"branchName" binding:"required"`
		BranchNameTH    string  `json:"branchNameTh" binding:"required"`
		BranchAddress   string  `json:"branchAddress" binding:"required"`
		BranchAddressTH string  `json:"branchAddressTh" binding:"required"`
		Phone           string  `json:"phone" binding:"required"`
		Email           *string `json:"email"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request"})
		return
	}

	branch := &repository.Branch{
		BranchID:        req.BranchID,
		CompanyID:       req.CompanyID,
		BranchName:      req.BranchName,
		BranchNameTH:    req.BranchNameTH,
		BranchAddress:   req.BranchAddress,
		BranchAddressTH: req.BranchAddressTH,
		Phone:           req.Phone,
		Email:           req.Email,
	}

	if err := h.branch.Create(c.Request.Context(), branch); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_create_branch"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"branchId":       branch.BranchID,
		"companyId":      branch.CompanyID,
		"branchName":     branch.BranchName,
		"branchNameTh":   branch.BranchNameTH,
		"branchAddress":  branch.BranchAddress,
		"branchAddressTh": branch.BranchAddressTH,
		"phone":          branch.Phone,
		"email":          branch.Email,
	})
}

func (h *BranchHandler) Update(c *gin.Context) {
	id := c.Param("id")
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_branch_id"})
		return
	}

	var req struct {
		CompanyID       string  `json:"companyId" binding:"required"`
		BranchName      string  `json:"branchName" binding:"required"`
		BranchNameTH    string  `json:"branchNameTh" binding:"required"`
		BranchAddress   string  `json:"branchAddress" binding:"required"`
		BranchAddressTH string  `json:"branchAddressTh" binding:"required"`
		Phone           string  `json:"phone" binding:"required"`
		Email           *string `json:"email"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request"})
		return
	}

	branch := &repository.Branch{
		BranchID:        id,
		CompanyID:       req.CompanyID,
		BranchName:      req.BranchName,
		BranchNameTH:    req.BranchNameTH,
		BranchAddress:   req.BranchAddress,
		BranchAddressTH: req.BranchAddressTH,
		Phone:           req.Phone,
		Email:           req.Email,
	}

	if err := h.branch.Update(c.Request.Context(), branch); err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "branch_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_update_branch"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"branchId":       branch.BranchID,
		"companyId":      branch.CompanyID,
		"branchName":     branch.BranchName,
		"branchNameTh":   branch.BranchNameTH,
		"branchAddress":  branch.BranchAddress,
		"branchAddressTh": branch.BranchAddressTH,
		"phone":          branch.Phone,
		"email":          branch.Email,
	})
}

func (h *BranchHandler) Delete(c *gin.Context) {
	id := c.Param("id")
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_branch_id"})
		return
	}

	// Check if only 1 record exists
	count, err := h.branch.Count(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_count_branches"})
		return
	}

	if count <= 1 {
		c.JSON(http.StatusForbidden, gin.H{"error": "cannot_delete_last_branch"})
		return
	}

	if err := h.branch.Delete(c.Request.Context(), id); err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "branch_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_delete_branch"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "branch_deleted"})
}

