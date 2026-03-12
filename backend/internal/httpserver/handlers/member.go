package handlers

import (
	"net/http"
	"strconv"

	"backend/internal/config"
	"backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type MemberHandler struct {
	members repository.MemberRepository
}

func NewMemberHandler(members repository.MemberRepository) *MemberHandler {
	return &MemberHandler{members: members}
}

func (h *MemberHandler) List(c *gin.Context) {
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

	query := c.Query("q")
	var (
		members []repository.Member
		err     error
	)
	if query != "" {
		members, err = h.members.Search(c.Request.Context(), query, limit, offset)
	} else {
		members, err = h.members.List(c.Request.Context(), limit, offset)
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_list_members"})
		return
	}

	out := make([]gin.H, 0, len(members))
	for _, m := range members {
		out = append(out, gin.H{
			"id":        m.ID,
			"code":      m.Code,
			"name":      m.Name,
			"phone":     m.Phone,
			"email":     m.Email,
			"points":    m.Points,
			"createdAt": m.CreatedAt,
			"updatedAt": m.UpdatedAt,
		})
	}

	c.JSON(http.StatusOK, gin.H{"members": out})
}

func (h *MemberHandler) Search(c *gin.Context) {
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

	q := c.Query("q")
	members, err := h.members.Search(c.Request.Context(), q, limit, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_search_members"})
		return
	}

	out := make([]gin.H, 0, len(members))
	for _, m := range members {
		out = append(out, gin.H{
			"id":        m.ID,
			"code":      m.Code,
			"name":      m.Name,
			"phone":     m.Phone,
			"email":     m.Email,
			"points":    m.Points,
			"createdAt": m.CreatedAt,
			"updatedAt": m.UpdatedAt,
		})
	}

	c.JSON(http.StatusOK, gin.H{"members": out})
}

func (h *MemberHandler) Get(c *gin.Context) {
	id := c.Param("id")
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_member_id"})
		return
	}

	member, err := h.members.GetByID(c.Request.Context(), id)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "member_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_member"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"id":        member.ID,
		"code":      member.Code,
		"name":      member.Name,
		"phone":     member.Phone,
		"email":     member.Email,
		"points":    member.Points,
		"createdAt": member.CreatedAt,
		"updatedAt": member.UpdatedAt,
	})
}

func (h *MemberHandler) Create(c *gin.Context) {
	var req struct {
		Name   string `json:"name" binding:"required"`
		Phone  string `json:"phone" binding:"required"`
		Email  string `json:"email"`
		Points int    `json:"points"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": err.Error()})
		return
	}

	member := &repository.Member{
		Name:   req.Name,
		Phone:  req.Phone,
		Email:  req.Email,
		Points: req.Points,
	}
	if err := h.members.Create(c.Request.Context(), member); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_create_member", "message": err.Error()})
		return
	}

	created, err := h.members.GetByID(c.Request.Context(), member.ID)
	if err != nil {
		c.JSON(http.StatusCreated, gin.H{
			"id":     member.ID,
			"code":   member.Code,
			"name":   member.Name,
			"phone":  member.Phone,
			"email":  member.Email,
			"points": member.Points,
		})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"id":        created.ID,
		"code":      created.Code,
		"name":      created.Name,
		"phone":     created.Phone,
		"email":     created.Email,
		"points":    created.Points,
		"createdAt": created.CreatedAt,
		"updatedAt": created.UpdatedAt,
	})
}

func (h *MemberHandler) Update(c *gin.Context) {
	id := c.Param("id")
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_member_id"})
		return
	}

	var req struct {
		Name   string `json:"name" binding:"required"`
		Phone  string `json:"phone" binding:"required"`
		Email  string `json:"email"`
		Points int    `json:"points"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": err.Error()})
		return
	}

	member := &repository.Member{
		Name:   req.Name,
		Phone:  req.Phone,
		Email:  req.Email,
		Points: req.Points,
	}
	if err := h.members.UpdateByID(c.Request.Context(), id, member); err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "member_not_found"})
			return
		}
		c.JSON(http.StatusBadRequest, gin.H{"error": "failed_to_update_member", "message": err.Error()})
		return
	}

	updated, err := h.members.GetByID(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusOK, gin.H{
			"id":     id,
			"name":   member.Name,
			"phone":  member.Phone,
			"email":  member.Email,
			"points": member.Points,
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"id":        updated.ID,
		"code":      updated.Code,
		"name":      updated.Name,
		"phone":     updated.Phone,
		"email":     updated.Email,
		"points":    updated.Points,
		"createdAt": updated.CreatedAt,
		"updatedAt": updated.UpdatedAt,
	})
}

func (h *MemberHandler) Delete(c *gin.Context) {
	id := c.Param("id")
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_member_id"})
		return
	}

	if err := h.members.Delete(c.Request.Context(), id); err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "member_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_delete_member"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "member_deleted"})
}
