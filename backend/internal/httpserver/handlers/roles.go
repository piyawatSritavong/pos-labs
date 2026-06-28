package handlers

import (
	"fmt"
	"net/http"
	"regexp"
	"strings"

	"backend/internal/repository"

	"github.com/gin-gonic/gin"
)

// RolesHandler exposes role listing + creation so the admin can define custom
// roles (Admin + POS Staff are the seeded base roles).
type RolesHandler struct {
	rbac repository.RBACRepository
}

func NewRolesHandler(rbac repository.RBACRepository) *RolesHandler {
	return &RolesHandler{rbac: rbac}
}

func (h *RolesHandler) List(c *gin.Context) {
	roles, err := h.rbac.ListRoles(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_list_roles"})
		return
	}
	out := make([]gin.H, 0, len(roles))
	for _, r := range roles {
		out = append(out, gin.H{"id": r.ID, "name": r.Name, "detail": r.Detail})
	}
	c.JSON(http.StatusOK, gin.H{"roles": out})
}

var roleSlugRe = regexp.MustCompile(`[^a-z0-9]+`)

func (h *RolesHandler) Create(c *gin.Context) {
	var req struct {
		Name        string   `json:"name"`
		Detail      string   `json:"detail"`
		Permissions []string `json:"permissions"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_body"})
		return
	}
	name := strings.TrimSpace(req.Name)
	if name == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "name_required"})
		return
	}

	// Derive a stable id "role.<slug>", uniquified with a numeric suffix.
	slug := strings.Trim(roleSlugRe.ReplaceAllString(strings.ToLower(name), "_"), "_")
	if slug == "" {
		slug = "custom"
	}
	base := "role." + slug
	id := base
	for i := 2; ; i++ {
		exists, err := h.rbac.RoleExists(c.Request.Context(), id)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_check_role"})
			return
		}
		if !exists {
			break
		}
		id = fmt.Sprintf("%s_%d", base, i)
	}

	if err := h.rbac.CreateRole(c.Request.Context(), id, name, req.Detail, req.Permissions); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "failed_to_create_role",
			"message": err.Error(),
		})
		return
	}
	c.JSON(http.StatusCreated, gin.H{"id": id, "name": name})
}
