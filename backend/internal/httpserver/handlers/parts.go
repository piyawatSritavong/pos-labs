package handlers

import (
	"net/http"
	"strconv"
	"strings"

	"backend/internal/config"
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

	var branchIDPtr *string
	if b := strings.TrimSpace(c.Query("branchId")); b != "" {
		branchIDPtr = &b
	}

	items, err := h.parts.ListParts(c.Request.Context(), limit, offset, branchIDPtr)
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
	// Get part detail without branch filtering (general endpoint)
	part, addresses, err := h.parts.GetPartDetail(ctx, code, nil)
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
		"code":     part.Code,
		"barCode":  part.BarCode,
		"name":     part.Name,
		"nameTh":   part.NameTH,
		"details":  part.Details,
		"cost":     part.Cost,
		"price":    part.Price,
		"image":    part.Image,
		"isActive": part.IsActive,
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
			"shelf":     a.Shelf,
			"qty":       a.Qty,
			"min":       a.Min,
			"max":       a.Max,
			"rop":       a.Rop,
			"remarks":   a.Remarks,
			"isDefault": a.IsDefault,
		})
	}
	resp["addresses"] = addrs

	c.JSON(http.StatusOK, resp)
}

// Search searches for parts with filters and returns detailed results
// Query parameters:
//   - q: universal search query (searches in: part code, barcode, part name, name_th,
//     category name, category name_th, address code, store address shelf,
//     store address remarks, store label, store label_th)
//   - categoryId: filter by category ID (optional)
//   - isActive: filter by active status (true/false) (optional)
//   - crossBranch: if true, search across all branches; if false, only session branch (default: false)
//   - limit: pagination limit (default: 20, max: 500)
//   - offset: pagination offset (default: 0)
func (h *PartsHandler) Search(c *gin.Context) {
	// Parse query parameters
	query := c.Query("q")
	categoryID := c.Query("categoryId")
	isActiveStr := c.Query("isActive")
	crossBranchStr := c.Query("crossBranch")

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

	// Parse isActive filter
	var isActive *bool
	if isActiveStr != "" {
		if val, err := strconv.ParseBool(isActiveStr); err == nil {
			isActive = &val
		}
	}

	// Parse categoryId filter
	var categoryIDPtr *string
	if categoryID != "" {
		categoryIDPtr = &categoryID
	}

	// Determine branch filtering
	var branchID *string
	crossBranch := false
	if crossBranchStr != "" {
		if val, err := strconv.ParseBool(crossBranchStr); err == nil {
			crossBranch = val
		}
	}

	// If not cross-branch, get branchId from session
	if !crossBranch {
		branchIDVal, exists := c.Get("branch_id")
		if exists {
			if b, ok := branchIDVal.(string); ok && b != "" {
				branchID = &b
			}
		}
	}

	ctx := c.Request.Context()

	// Search parts
	parts, err := h.parts.SearchParts(ctx, query, categoryIDPtr, isActive, branchID, limit, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_search_parts"})
		return
	}

	// Build response with addresses for each part
	out := make([]gin.H, 0, len(parts))
	for _, part := range parts {
		// Get addresses for this part (filtered by branch if not crossBranch)
		var addresses []repository.PartAddress
		if crossBranch {
			// Get all addresses
			_, addresses, err = h.parts.GetPartDetail(ctx, part.Code, nil)
		} else {
			// Get addresses filtered by branch
			if branchID != nil {
				_, addresses, err = h.parts.GetPartDetail(ctx, part.Code, branchID)
			} else {
				_, addresses, err = h.parts.GetPartDetail(ctx, part.Code, nil)
			}
		}
		if err != nil {
			// Log error but continue with empty addresses
			addresses = []repository.PartAddress{}
		}

		// Build addresses array
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
				"shelf":     a.Shelf,
				"qty":       a.Qty,
				"min":       a.Min,
				"max":       a.Max,
				"rop":       a.Rop,
				"remarks":   a.Remarks,
				"isDefault": a.IsDefault,
			})
		}

		out = append(out, gin.H{
			"code":     part.Code,
			"barCode":  part.BarCode,
			"name":     part.Name,
			"nameTh":   part.NameTH,
			"details":  part.Details,
			"cost":     part.Cost,
			"price":    part.Price,
			"image":    part.Image,
			"isActive": part.IsActive,
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
			"addresses":  addrs,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"parts": out,
	})
}
