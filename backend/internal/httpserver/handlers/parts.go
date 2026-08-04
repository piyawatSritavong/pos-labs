package handlers

import (
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"backend/internal/config"
	"backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type PartsHandler struct {
	parts repository.PartRepository
}

func (h *PartsHandler) NextCode(c *gin.Context) {
	code, err := h.parts.GetNextPartCode(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_generate_part_code"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"code": code, "barcode": code})
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
			"code":        p.Code,
			"barCode":     p.BarCode,
			"name":        p.Name,
			"nameTh":      p.NameTH,
			"receiptName": p.ReceiptName,
			"price":       p.Price,
			"isActive":    p.IsActive,
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
			"totalStock":   p.TotalStock,
			"reorderPoint": p.ReorderPoint,
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
	// Get part detail without branch filtering (general endpoint).
	// If lookup by code misses, fall back to bar_code so a scan of either
	// the part code or the printed barcode resolves to the same part.
	start := time.Now()
	part, addresses, err := h.parts.GetPartDetail(ctx, code, nil)
	logSlowTiming("parts.get.detail_by_code", start, "code", code, "found", err == nil)
	if err != nil {
		if !repository.IsNotFoundError(err) {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_load_part"})
			return
		}
		start = time.Now()
		part, addresses, err = h.parts.GetPartByBarcode(ctx, code, "")
		logSlowTiming("parts.get.detail_by_barcode", start, "barcode", code, "found", err == nil)
		if err != nil {
			if repository.IsNotFoundError(err) {
				c.JSON(http.StatusNotFound, gin.H{"error": "part_not_found"})
				return
			}
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_load_part"})
			return
		}
	}

	// Build response shape as requested
	resp := gin.H{
		"code":        part.Code,
		"barCode":     part.BarCode,
		"name":        part.Name,
		"nameTh":      part.NameTH,
		"receiptName": part.ReceiptName,
		"details":     part.Details,
		"cost":        part.Cost,
		"price":       part.Price,
		"image":       part.Image,
		"isActive":    part.IsActive,
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

	// Load addresses for every result in a single query (avoids N+1).
	// crossBranch ignores the branch filter; otherwise filter by branch when set.
	addrBranchID := branchID
	if crossBranch {
		addrBranchID = nil
	}
	codes := make([]string, 0, len(parts))
	for _, part := range parts {
		codes = append(codes, part.Code)
	}
	addressesByCode, err := h.parts.GetAddressesByPartCodes(ctx, codes, addrBranchID)
	if err != nil {
		// Degrade gracefully: return parts without addresses rather than failing.
		addressesByCode = map[string][]repository.PartAddress{}
	}

	// Build response with addresses for each part
	out := make([]gin.H, 0, len(parts))
	for _, part := range parts {
		addresses := addressesByCode[part.Code]

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
				"rop":       a.Rop,
				"remarks":   a.Remarks,
				"isDefault": a.IsDefault,
			})
		}

		out = append(out, gin.H{
			"code":        part.Code,
			"barCode":     part.BarCode,
			"name":        part.Name,
			"nameTh":      part.NameTH,
			"receiptName": part.ReceiptName,
			"details":     part.Details,
			"cost":        part.Cost,
			"price":       part.Price,
			"image":       part.Image,
			"isActive":    part.IsActive,
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

	// Total matching count (ignores limit/offset) for page-jump pagination.
	total, err := h.parts.CountParts(ctx, query, categoryIDPtr, isActive, branchID)
	if err != nil {
		total = len(out) // degrade gracefully
	}

	c.JSON(http.StatusOK, gin.H{
		"parts": out,
		"total": total,
	})
}

// Create inserts a new part. The code is always allocated by the server.
// a unit_master id (stored NULL when it doesn't match).
func (h *PartsHandler) Create(c *gin.Context) {
	var req struct {
		Code       string  `json:"code"`
		Name       string  `json:"name"`
		NameTh     string  `json:"nameTh"`
		Barcode    string  `json:"barcode"`
		Unit       string  `json:"unit"`
		UnitId     string  `json:"unitId"`
		CategoryId string  `json:"categoryId"`
		Price      float64 `json:"price"`
		Cost       float64 `json:"cost"`
		Details    string  `json:"details"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": err.Error()})
		return
	}
	name := strings.TrimSpace(req.Name)
	if name == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_fields", "message": "name is required"})
		return
	}
	nameTh := strings.TrimSpace(req.NameTh)
	if nameTh == "" {
		nameTh = name
	}
	barcode := strings.TrimSpace(req.Barcode)
	unitID := strings.TrimSpace(req.UnitId)
	if unitID == "" {
		unitID = strings.TrimSpace(req.Unit)
	}
	created, err := h.parts.CreatePart(c.Request.Context(), repository.PartInput{
		Name: name, NameTH: nameTh, BarCode: barcode,
		UnitID: unitID, CategoryID: strings.TrimSpace(req.CategoryId),
		Price: req.Price, Cost: req.Cost, Details: strings.TrimSpace(req.Details),
		IsActive: true,
	})
	if err != nil {
		if errors.Is(err, repository.ErrBarcodeExists) {
			c.JSON(http.StatusConflict, gin.H{"error": "barcode_already_exists", "message": "Barcode นี้ถูกใช้งานแล้ว"})
			return
		}
		if strings.Contains(err.Error(), "duplicate") || strings.Contains(err.Error(), "unique") {
			c.JSON(http.StatusConflict, gin.H{"error": "part_code_exists", "message": "รหัสสินค้านี้มีอยู่แล้ว"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_create_part", "message": err.Error()})
		return
	}
	c.JSON(http.StatusCreated, gin.H{"code": created.Code, "barcode": created.BarCode, "name": name})
}

// Update edits an existing part's name/barcode/unit/price.
func (h *PartsHandler) Update(c *gin.Context) {
	code := strings.TrimSpace(c.Param("code"))
	if code == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_code"})
		return
	}
	var req struct {
		Name    string  `json:"name"`
		NameTh  string  `json:"nameTh"`
		Barcode string  `json:"barcode"`
		Unit    string  `json:"unit"`
		UnitId  string  `json:"unitId"`
		Price   float64 `json:"price"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": err.Error()})
		return
	}
	name := strings.TrimSpace(req.Name)
	if name == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_fields", "message": "name is required"})
		return
	}
	nameTh := strings.TrimSpace(req.NameTh)
	if nameTh == "" {
		nameTh = name
	}
	barcode := strings.TrimSpace(req.Barcode)
	if barcode == "" {
		barcode = code
	}
	unitID := strings.TrimSpace(req.UnitId)
	if unitID == "" {
		unitID = strings.TrimSpace(req.Unit)
	}
	err := h.parts.UpdatePart(c.Request.Context(), code, repository.PartInput{
		Name: name, NameTH: nameTh, BarCode: barcode, UnitID: unitID, Price: req.Price,
	})
	if err != nil {
		if errors.Is(err, repository.ErrBarcodeExists) {
			c.JSON(http.StatusConflict, gin.H{"error": "barcode_already_exists", "message": "Barcode นี้ถูกใช้งานแล้ว"})
			return
		}
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "part_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_update_part", "message": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"code": code, "name": name})
}

// Delete removes a part.
func (h *PartsHandler) Delete(c *gin.Context) {
	code := strings.TrimSpace(c.Param("code"))
	if code == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_code"})
		return
	}
	err := h.parts.DeletePart(c.Request.Context(), code)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "part_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_delete_part", "message": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"ok": true})
}
