package handlers

import (
	"net/http"

	"backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type UserBranchHandler struct {
	userBranch repository.UserBranchRepository
}

func NewUserBranchHandler(userBranch repository.UserBranchRepository) *UserBranchHandler {
	return &UserBranchHandler{userBranch: userBranch}
}

func (h *UserBranchHandler) ListByUser(c *gin.Context) {
	userID := c.Param("user_id")
	if userID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_user_id"})
		return
	}

	userBranches, err := h.userBranch.GetByUserID(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_list_user_branches"})
		return
	}

	out := make([]gin.H, 0, len(userBranches))
	for _, ub := range userBranches {
		out = append(out, gin.H{
			"userId":   ub.UserID,
			"branchId": ub.BranchID,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"items": out,
	})
}

func (h *UserBranchHandler) ListByBranch(c *gin.Context) {
	branchID := c.Param("branch_id")
	if branchID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_branch_id"})
		return
	}

	userBranches, err := h.userBranch.GetByBranchID(c.Request.Context(), branchID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_list_user_branches"})
		return
	}

	out := make([]gin.H, 0, len(userBranches))
	for _, ub := range userBranches {
		out = append(out, gin.H{
			"userId":   ub.UserID,
			"branchId": ub.BranchID,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"items": out,
	})
}

func (h *UserBranchHandler) Get(c *gin.Context) {
	userID := c.Param("user_id")
	branchID := c.Param("branch_id")
	if userID == "" || branchID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_user_id_or_branch_id"})
		return
	}

	userBranch, err := h.userBranch.GetByUserAndBranch(c.Request.Context(), userID, branchID)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "user_branch_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_user_branch"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"userId":   userBranch.UserID,
		"branchId": userBranch.BranchID,
	})
}

func (h *UserBranchHandler) Create(c *gin.Context) {
	var req struct {
		UserID   string `json:"userId" binding:"required"`
		BranchID string `json:"branchId" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request"})
		return
	}

	userBranch := &repository.UserBranch{
		UserID:   req.UserID,
		BranchID: req.BranchID,
	}

	if err := h.userBranch.Create(c.Request.Context(), userBranch); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_create_user_branch"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"userId":   userBranch.UserID,
		"branchId": userBranch.BranchID,
	})
}

func (h *UserBranchHandler) Delete(c *gin.Context) {
	userID := c.Param("user_id")
	branchID := c.Param("branch_id")
	if userID == "" || branchID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_user_id_or_branch_id"})
		return
	}

	if err := h.userBranch.Delete(c.Request.Context(), userID, branchID); err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "user_branch_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_delete_user_branch"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "user_branch_deleted"})
}

