package handlers

import (
	"net/http"
	"strconv"

	"backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type PartsHandler struct {
	parts repository.PartRepository
}

func NewPartsHandler(parts repository.PartRepository) *PartsHandler {
	return &PartsHandler{parts: parts}
}

func (h *PartsHandler) List(c *gin.Context) {
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

	items, err := h.parts.ListParts(c.Request.Context(), limit, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_list_parts"})
		return
	}

	out := make([]gin.H, 0, len(items))
	for _, p := range items {
		out = append(out, gin.H{
			"code":     p.Code,
			"barCode":  p.BarCode,
			"name":     p.Name,
			"nameTh":   p.NameTH,
			"price":    p.Price,
			"isActive": p.IsActive,
			"category": gin.H{
				"id":      p.CategoryID,
				"label":   p.CategoryLabel,
				"labelTh": p.CategoryLabelTH,
			},
			"unit": gin.H{
				"id":      p.UnitID,
				"label":   p.UnitLabel,
				"labelTh": p.UnitLabelTH,
			},
			"totalStock": p.TotalStock,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"parts": out,
	})
}

// Get returns a single part with related category, unit, stock summary, and addresses.
func (h *PartsHandler) Get(c *gin.Context) {
	code := c.Param("code")
	if code == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_code"})
		return
	}

	ctx := c.Request.Context()
	part, addresses, err := h.parts.GetPartDetail(ctx, code)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "part_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_load_part"})
		return
	}

	// Build response shape as requested
	resp := gin.H{
		"code":      part.Code,
		"barCode":   part.BarCode,
		"name":      part.Name,
		"nameTh":    part.NameTH,
		"details":   part.Details,
		"cost":      part.Cost,
		"price":     part.Price,
		"image":     part.Image,
		"isActive":  part.IsActive,
		"category": gin.H{
			"id":      part.CategoryID,
			"label":   part.CategoryLabel,
			"labelTh": part.CategoryLabelTH,
		},
		"unit": gin.H{
			"id":      part.UnitID,
			"label":   part.UnitLabel,
			"labelTh": part.UnitLabelTH,
		},
		"totalStock": part.TotalStock,
	}

	addrs := make([]gin.H, 0, len(addresses))
	for _, a := range addresses {
		addrs = append(addrs, gin.H{
			"code":     a.Code,
			"partCode": a.PartCode,
			"store": gin.H{
				"id":      a.StoreID,
				"label":   a.StoreLabel,
				"labelTh": a.StoreLabelTH,
			},
			"shelf":   a.Shelf,
			"qty":     a.Qty,
			"min":     a.Min,
			"max":     a.Max,
			"rop":     a.Rop,
			"remarks": a.Remarks,
		})
	}
	resp["addresses"] = addrs

	c.JSON(http.StatusOK, resp)
}

