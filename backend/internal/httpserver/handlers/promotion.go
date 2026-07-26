package handlers

import (
	"net/http"
	"strconv"
	"strings"

	"backend/internal/config"
	"backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type PromotionHandler struct {
	promotions repository.PromotionRepository
}

func NewPromotionHandler(promotions repository.PromotionRepository) *PromotionHandler {
	return &PromotionHandler{promotions: promotions}
}

func (h *PromotionHandler) List(c *gin.Context) {
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

	promotions, err := h.promotions.List(c.Request.Context(), limit, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_list_promotions"})
		return
	}

	out := make([]gin.H, 0, len(promotions))
	for _, p := range promotions {
		out = append(out, gin.H{
			"code":    p.Code,
			"details": p.Details,
			"unit":    p.Unit,
			"amount":  p.Amount,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"promotions": out,
	})
}

func (h *PromotionHandler) Get(c *gin.Context) {
	code := c.Param("code")
	if code == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_promotion_code"})
		return
	}

	promotion, err := h.promotions.GetByCode(c.Request.Context(), code)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "promotion_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_promotion"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"code":    promotion.Code,
		"details": promotion.Details,
		"unit":    promotion.Unit,
		"amount":  promotion.Amount,
	})
}

func (h *PromotionHandler) Create(c *gin.Context) {
	var req struct {
		Code    string  `json:"code" binding:"required"`
		Details string  `json:"details"`
		Unit    string  `json:"unit" binding:"required"`
		Amount  float64 `json:"amount" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": err.Error()})
		return
	}

	// Validate unit is "THB" or "percentage"
	unitUpper := strings.ToUpper(req.Unit)
	if unitUpper != "THB" && unitUpper != "PERCENTAGE" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "invalid_unit",
			"message": "Unit must be 'THB' or 'percentage'",
		})
		return
	}

	// Validate amount > 0
	if req.Amount <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "invalid_amount",
			"message": "Amount must be greater than 0",
		})
		return
	}

	// Normalize unit to match database (THB or percentage)
	normalizedUnit := "THB"
	if unitUpper == "PERCENTAGE" {
		normalizedUnit = "percentage"
	}

	promotion := &repository.Promotion{
		Code:    req.Code,
		Details: req.Details,
		Unit:    normalizedUnit,
		Amount:  req.Amount,
	}

	if err := h.promotions.Create(c.Request.Context(), promotion); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_create_promotion"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"code":    promotion.Code,
		"details": promotion.Details,
		"unit":    promotion.Unit,
		"amount":  promotion.Amount,
	})
}

func (h *PromotionHandler) Update(c *gin.Context) {
	code := c.Param("code")
	if code == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_promotion_code"})
		return
	}

	var req struct {
		Details string  `json:"details"`
		Unit    string  `json:"unit" binding:"required"`
		Amount  float64 `json:"amount" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": err.Error()})
		return
	}

	// Validate unit is "THB" or "percentage"
	unitUpper := strings.ToUpper(req.Unit)
	if unitUpper != "THB" && unitUpper != "PERCENTAGE" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "invalid_unit",
			"message": "Unit must be 'THB' or 'percentage'",
		})
		return
	}

	// Validate amount > 0
	if req.Amount <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "invalid_amount",
			"message": "Amount must be greater than 0",
		})
		return
	}

	// Normalize unit to match database (THB or percentage)
	normalizedUnit := "THB"
	if unitUpper == "PERCENTAGE" {
		normalizedUnit = "percentage"
	}

	promotion := &repository.Promotion{
		Code:    code,
		Details: req.Details,
		Unit:    normalizedUnit,
		Amount:  req.Amount,
	}

	if err := h.promotions.Update(c.Request.Context(), promotion); err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "promotion_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_update_promotion"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"code":    promotion.Code,
		"details": promotion.Details,
		"unit":    promotion.Unit,
		"amount":  promotion.Amount,
	})
}

func (h *PromotionHandler) Delete(c *gin.Context) {
	code := c.Param("code")
	if code == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_promotion_code"})
		return
	}

	if err := h.promotions.Delete(c.Request.Context(), code); err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "promotion_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_delete_promotion"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "promotion_deleted"})
}
