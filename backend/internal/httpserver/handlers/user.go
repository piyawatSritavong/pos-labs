package handlers

import (
	"net/http"
	"strconv"

	"backend/internal/repository"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"
)

type UserHandler struct {
	users repository.UserRepository
}

func NewUserHandler(users repository.UserRepository) *UserHandler {
	return &UserHandler{users: users}
}

func (h *UserHandler) List(c *gin.Context) {
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

	users, err := h.users.List(c.Request.Context(), limit, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_list_users"})
		return
	}

	out := make([]gin.H, 0, len(users))
	for _, u := range users {
		out = append(out, gin.H{
			"id":          u.ID,
			"username":    u.Username,
			"roleId":      u.RoleID,
			"name":        u.Name,
			"isActive":    u.IsActive,
			"isSuperuser": u.IsSuperuser,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"items": out,
	})
}

func (h *UserHandler) Get(c *gin.Context) {
	id := c.Param("id")
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_user_id"})
		return
	}

	user, err := h.users.GetByID(c.Request.Context(), id)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "user_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_user"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"id":          user.ID,
		"username":    user.Username,
		"roleId":      user.RoleID,
		"name":        user.Name,
		"isActive":    user.IsActive,
		"isSuperuser": user.IsSuperuser,
	})
}

func (h *UserHandler) Create(c *gin.Context) {
	var req struct {
		ID          string `json:"id" binding:"required"`
		Username    string `json:"username" binding:"required"`
		RoleID      string `json:"roleId" binding:"required"`
		Name        string `json:"name" binding:"required"`
		Password    string `json:"password" binding:"required"`
		IsActive    bool   `json:"isActive"`
		IsSuperuser bool   `json:"isSuperuser"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request"})
		return
	}

	// Hash password
	passwordHash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_hash_password"})
		return
	}

	user := &repository.User{
		ID:           req.ID,
		Username:     req.Username,
		RoleID:       req.RoleID,
		Name:         req.Name,
		PasswordHash: string(passwordHash),
		IsActive:     req.IsActive,
		IsSuperuser:  req.IsSuperuser,
	}

	if err := h.users.Create(c.Request.Context(), user); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_create_user"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"id":          user.ID,
		"username":    user.Username,
		"roleId":      user.RoleID,
		"name":        user.Name,
		"isActive":    user.IsActive,
		"isSuperuser": user.IsSuperuser,
	})
}

func (h *UserHandler) Update(c *gin.Context) {
	id := c.Param("id")
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_user_id"})
		return
	}

	var req struct {
		Username    string `json:"username" binding:"required"`
		RoleID      string `json:"roleId" binding:"required"`
		Name        string `json:"name" binding:"required"`
		Password    string `json:"password"` // optional - only update if provided
		IsActive    bool   `json:"isActive"`
		IsSuperuser bool   `json:"isSuperuser"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request"})
		return
	}

	// Get existing user to preserve password if not provided
	existing, err := h.users.GetByID(c.Request.Context(), id)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "user_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_user"})
		return
	}

	user := &repository.User{
		ID:          id,
		Username:    req.Username,
		RoleID:      req.RoleID,
		Name:        req.Name,
		PasswordHash: existing.PasswordHash, // Keep existing password by default
		IsActive:    req.IsActive,
		IsSuperuser: req.IsSuperuser,
	}

	// Update password if provided
	if req.Password != "" {
		passwordHash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_hash_password"})
			return
		}
		user.PasswordHash = string(passwordHash)
	}

	if err := h.users.Update(c.Request.Context(), user); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_update_user"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"id":          user.ID,
		"username":    user.Username,
		"roleId":      user.RoleID,
		"name":        user.Name,
		"isActive":    user.IsActive,
		"isSuperuser": user.IsSuperuser,
	})
}

func (h *UserHandler) Delete(c *gin.Context) {
	id := c.Param("id")
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_user_id"})
		return
	}

	// Check if user is superuser - prevent deletion
	user, err := h.users.GetByID(c.Request.Context(), id)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "user_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_user"})
		return
	}

	if user.IsSuperuser {
		c.JSON(http.StatusForbidden, gin.H{"error": "cannot_delete_superuser"})
		return
	}

	if err := h.users.Delete(c.Request.Context(), id); err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "user_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_delete_user"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "user_deleted"})
}

