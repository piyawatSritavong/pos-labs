package handlers

import (
	"net/http"
	"slices"
	"strconv"
	"strings"

	"backend/internal/config"
	"backend/internal/repository"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"golang.org/x/crypto/bcrypt"
)

type UserHandler struct {
	users repository.UserRepository
}

func NewUserHandler(users repository.UserRepository) *UserHandler {
	return &UserHandler{users: users}
}

func currentManagedUser(c *gin.Context) (*repository.User, bool) {
	userVal, exists := c.Get("user")
	if !exists || userVal == nil {
		return nil, false
	}
	user, ok := userVal.(*repository.User)
	return user, ok && user != nil
}

func canViewManagedUser(caller, target *repository.User) bool {
	if caller == nil || target == nil {
		return false
	}
	if caller.ID == target.ID {
		return false
	}
	if caller.IsSuperuser || caller.RoleID == "role.admin" {
		return true
	}
	if caller.RoleID == "role.hq_manager" {
		return target.RoleID == "role.van_staff"
	}
	return false
}

func (h *UserHandler) List(c *gin.Context) {
	limit := config.DefaultLimit
	offset := config.DefaultOffset

	if v := c.Query("limit"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 && n <= config.MaxLimit {
			limit = n
		}
	}
	if v := c.Query("offset"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n >= 0 {
			offset = n
		}
	}

	caller, ok := currentManagedUser(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	users, err := h.users.List(c.Request.Context(), limit, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_list_users"})
		return
	}

	out := make([]gin.H, 0, len(users))
	for _, u := range users {
		target := u
		if !canViewManagedUser(caller, &target) {
			continue
		}
		out = append(out, gin.H{
			"id":                u.ID,
			"username":          u.Username,
			"roleId":            u.RoleID,
			"name":              u.Name,
			"isActive":          u.IsActive,
			"isSuperuser":       u.IsSuperuser,
			"customPermissions": u.CustomPermissions,
			"branchId":          u.BranchID,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"users": out,
	})
}

func (h *UserHandler) Get(c *gin.Context) {
	id := c.Param("id")
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_user_id"})
		return
	}

	caller, ok := currentManagedUser(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
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

	if !canViewManagedUser(caller, user) {
		c.JSON(http.StatusForbidden, gin.H{"error": "user_not_visible"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"id":                user.ID,
		"username":          user.Username,
		"roleId":            user.RoleID,
		"name":              user.Name,
		"isActive":          user.IsActive,
		"isSuperuser":       user.IsSuperuser,
		"customPermissions": user.CustomPermissions,
		"branchId":          user.BranchID,
	})
}

// allowedRoles maps a caller's role to the set of roles they may create/update.
var allowedRoles = map[string][]string{
	"role.admin":      {"role.hq_manager", "role.van_staff"},
	"role.hq_manager": {"role.van_staff"},
}

func (h *UserHandler) Create(c *gin.Context) {
	var req struct {
		Username          string   `json:"username" binding:"required"`
		RoleID            string   `json:"roleId" binding:"required"`
		Name              string   `json:"name" binding:"required"`
		Password          string   `json:"password" binding:"required"`
		IsActive          bool     `json:"isActive"`
		IsSuperuser       bool     `json:"isSuperuser"`
		CustomPermissions []string `json:"customPermissions"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request"})
		return
	}

	// Role hierarchy: check caller is allowed to create the requested role.
	callerUser, ok := c.Get("user")
	if ok && callerUser != nil {
		if caller, ok := callerUser.(*repository.User); ok && !caller.IsSuperuser {
			allowed, exists := allowedRoles[caller.RoleID]
			if !exists || !slices.Contains(allowed, req.RoleID) {
				c.JSON(http.StatusForbidden, gin.H{"error": "cannot_create_role_higher_than_own"})
				return
			}
		}
	}

	// Generate UUID without dashes for user ID
	userID := strings.ReplaceAll(uuid.New().String(), "-", "")

	// Hash password
	passwordHash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_hash_password"})
		return
	}

	user := &repository.User{
		ID:                userID,
		Username:          req.Username,
		RoleID:            req.RoleID,
		Name:              req.Name,
		PasswordHash:      string(passwordHash),
		IsActive:          req.IsActive,
		IsSuperuser:       req.IsSuperuser,
		CustomPermissions: req.CustomPermissions,
	}

	if err := h.users.Create(c.Request.Context(), user); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_create_user"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"id":                user.ID,
		"username":          user.Username,
		"roleId":            user.RoleID,
		"name":              user.Name,
		"isActive":          user.IsActive,
		"isSuperuser":       user.IsSuperuser,
		"customPermissions": user.CustomPermissions,
	})
}

func (h *UserHandler) Update(c *gin.Context) {
	id := c.Param("id")
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_user_id"})
		return
	}

	var req struct {
		Username          string   `json:"username" binding:"required"`
		RoleID            string   `json:"roleId" binding:"required"`
		Name              string   `json:"name" binding:"required"`
		Password          string   `json:"password"` // optional - only update if provided
		IsActive          bool     `json:"isActive"`
		IsSuperuser       bool     `json:"isSuperuser"`
		CustomPermissions []string `json:"customPermissions"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request"})
		return
	}

	// Role hierarchy: check caller is allowed to assign the requested role.
	callerUser, ok := c.Get("user")
	if ok && callerUser != nil {
		if caller, ok := callerUser.(*repository.User); ok && !caller.IsSuperuser {
			allowed, exists := allowedRoles[caller.RoleID]
			if !exists || !slices.Contains(allowed, req.RoleID) {
				c.JSON(http.StatusForbidden, gin.H{"error": "cannot_assign_role_higher_than_own"})
				return
			}
		}
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

	if caller, ok := currentManagedUser(c); !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	} else if !canViewManagedUser(caller, existing) {
		c.JSON(http.StatusForbidden, gin.H{"error": "user_not_visible"})
		return
	}

	user := &repository.User{
		ID:                id,
		Username:          req.Username,
		RoleID:            req.RoleID,
		Name:              req.Name,
		PasswordHash:      existing.PasswordHash, // Keep existing password by default
		IsActive:          req.IsActive,
		IsSuperuser:       req.IsSuperuser,
		CustomPermissions: req.CustomPermissions,
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
		"id":                user.ID,
		"username":          user.Username,
		"roleId":            user.RoleID,
		"name":              user.Name,
		"isActive":          user.IsActive,
		"isSuperuser":       user.IsSuperuser,
		"customPermissions": user.CustomPermissions,
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

	if caller, ok := currentManagedUser(c); !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	} else if !canViewManagedUser(caller, user) {
		c.JSON(http.StatusForbidden, gin.H{"error": "user_not_visible"})
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
