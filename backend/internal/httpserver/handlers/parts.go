package handlers

import (
	"net/http"
	"strconv"
	"strings"
	"time"

	"backend/internal/config"
	"backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type PartsHandler struct {
	parts     repository.PartRepository
	addresses repository.AddressRepository
	pos       repository.POSRepository
}

func NewPartsHandler(parts repository.PartRepository, addresses repository.AddressRepository, pos repository.POSRepository) *PartsHandler {
	return &PartsHandler{parts: parts, addresses: addresses, pos: pos}
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
	if !canReadAllOperationalData(c) {
		value, _ := c.Get("branch_id")
		branchID, _ := value.(string)
		if strings.TrimSpace(branchID) == "" {
			c.JSON(http.StatusForbidden, gin.H{"error": "part_access_denied"})
			return
		}
		branchIDPtr = &branchID
	}

	items, err := h.parts.ListParts(c.Request.Context(), limit, offset, branchIDPtr)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_list_parts"})
		return
	}

	// includeAddresses=true embeds each part's warehouse locations (one batch
	// query) so the Parts page can show/filter by store.
	var addressesByCode map[string][]repository.PartAddress
	if c.Query("includeAddresses") == "true" {
		codes := make([]string, 0, len(items))
		for _, p := range items {
			codes = append(codes, p.Code)
		}
		addressesByCode, err = h.parts.GetAddressesByPartCodes(c.Request.Context(), codes, branchIDPtr)
		if err != nil {
			addressesByCode = map[string][]repository.PartAddress{} // degrade gracefully
		}
	}

	out := make([]gin.H, 0, len(items))
	for _, p := range items {
		entry := gin.H{
			"code":        p.Code,
			"barCode":     p.BarCode,
			"name":        p.Name,
			"nameTh":      p.NameTH,
			"receiptName": p.ReceiptName,
			"cost":        p.Cost,
			"price":       p.Price,
			"minPrice":    p.MinPrice,
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
		}
		if addressesByCode != nil {
			addrs := make([]gin.H, 0, len(addressesByCode[p.Code]))
			for _, a := range addressesByCode[p.Code] {
				addrs = append(addrs, gin.H{
					"code": a.Code,
					"store": gin.H{
						"id":      a.StoreID,
						"label":   a.StoreLabel,
						"labelTh": a.StoreLabelTH,
					},
					"shelf": a.Shelf,
					"qty":   a.Qty,
				})
			}
			entry["addresses"] = addrs
		}
		out = append(out, entry)
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
	var branchID *string
	if !canReadAllOperationalData(c) {
		value, _ := c.Get("branch_id")
		sessionBranch, _ := value.(string)
		if strings.TrimSpace(sessionBranch) == "" {
			c.JSON(http.StatusForbidden, gin.H{"error": "part_access_denied"})
			return
		}
		branchID = &sessionBranch
	}
	// Admin gets the global catalog; other roles get only addresses/stock in
	// their current branch.
	// If lookup by code misses, fall back to bar_code so a scan of either
	// the part code or the printed barcode resolves to the same part.
	start := time.Now()
	part, addresses, err := h.parts.GetPartDetail(ctx, code, branchID)
	logSlowTiming("parts.get.detail_by_code", start, "code", code, "found", err == nil)
	if err != nil {
		if !repository.IsNotFoundError(err) {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_load_part"})
			return
		}
		start = time.Now()
		barcodeBranch := ""
		if branchID != nil {
			barcodeBranch = *branchID
		}
		part, addresses, err = h.parts.GetPartByBarcode(ctx, code, barcodeBranch)
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
		"minPrice":    part.MinPrice,
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
//   - saleableOnly: if true, force the session POS store and qty > 0
//   - limit: pagination limit (default: 20, max: 500)
//   - offset: pagination offset (default: 0)
func (h *PartsHandler) Search(c *gin.Context) {
	// Parse query parameters
	query := c.Query("q")
	categoryID := c.Query("categoryId")
	isActiveStr := c.Query("isActive")
	crossBranchStr := c.Query("crossBranch")
	saleableOnlyStr := c.Query("saleableOnly")

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
	var storeIDPtr *string
	crossBranch := false
	if crossBranchStr != "" {
		if val, err := strconv.ParseBool(crossBranchStr); err == nil {
			crossBranch = val
		}
	}
	if crossBranch && !canReadAllOperationalData(c) {
		c.JSON(http.StatusForbidden, gin.H{"error": "cross_branch_access_denied"})
		return
	}

	saleableOnly := false
	if saleableOnlyStr != "" {
		if val, err := strconv.ParseBool(saleableOnlyStr); err == nil {
			saleableOnly = val
		}
	}
	if saleableOnly {
		// A sale search is always scoped by the authenticated terminal. Caller
		// supplied cross-branch/store filters must never widen the stock source.
		crossBranch = false
		posIDValue, _ := c.Get("pos_id")
		posID, _ := posIDValue.(string)
		posSetting, err := h.pos.GetByID(c.Request.Context(), posID)
		if err != nil || strings.TrimSpace(posSetting.VehicleStoreID) == "" {
			c.JSON(http.StatusConflict, gin.H{
				"error":   "pos_store_not_configured",
				"message": "POS does not have a stock store configured",
			})
			return
		}
		storeID := strings.TrimSpace(posSetting.VehicleStoreID)
		storeIDPtr = &storeID
		active := true
		isActive = &active
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

	// Optional store (คลังสินค้า) filter for the Parts page.
	if !saleableOnly {
		if st := strings.TrimSpace(c.Query("storeId")); st != "" {
			storeIDPtr = &st
		}
	}

	ctx := c.Request.Context()

	// Search parts
	parts, err := h.parts.SearchParts(ctx, query, categoryIDPtr, isActive, branchID, storeIDPtr, saleableOnly, limit, offset)
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
		if storeIDPtr != nil {
			filtered := make([]repository.PartAddress, 0, len(addresses))
			for _, address := range addresses {
				if address.StoreID == *storeIDPtr && (!saleableOnly || address.Qty > 0) {
					filtered = append(filtered, address)
				}
			}
			addresses = filtered
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
			"minPrice":    part.MinPrice,
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
	total, err := h.parts.CountParts(ctx, query, categoryIDPtr, isActive, branchID, storeIDPtr, saleableOnly)
	if err != nil {
		total = len(out) // degrade gracefully
	}

	c.JSON(http.StatusOK, gin.H{
		"parts": out,
		"total": total,
	})
}

// Create inserts a new part. Required: code, name. Free-text unit is matched to
// a unit_master id (stored NULL when it doesn't match).
func (h *PartsHandler) Create(c *gin.Context) {
	var req struct {
		Code       string   `json:"code"`
		Name       string   `json:"name"`
		NameTh     string   `json:"nameTh"`
		Barcode    string   `json:"barcode"`
		Unit       string   `json:"unit"`
		UnitId     string   `json:"unitId"`
		CategoryId string   `json:"categoryId"`
		Price      float64  `json:"price"`
		Cost       float64  `json:"cost"`
		MinPrice   *float64 `json:"minPrice"`
		Details    string   `json:"details"`
		// Optional initial warehouse placement: when storeId is given an
		// address_master row is created so the part immediately lives in a store.
		StoreID string `json:"storeId"`
		Shelf   string `json:"shelf"`
		Qty     int    `json:"qty"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": err.Error()})
		return
	}
	if requestedStore := strings.TrimSpace(req.StoreID); requestedStore != "" && requestedStore != "main" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "invalid_warehouse",
			"message": "สินค้าใหม่ต้องรับเข้าคลังหลักเท่านั้น",
		})
		return
	}
	minPrice := req.Price * 0.90
	if req.MinPrice != nil {
		minPrice = *req.MinPrice
	}
	if req.Cost < 0 || req.Price < 0 || minPrice < 0 || minPrice > req.Price {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "invalid_prices",
			"message": "cost and prices must be non-negative, and minPrice must not exceed price",
		})
		return
	}
	code := strings.TrimSpace(req.Code)
	name := strings.TrimSpace(req.Name)
	if name == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_fields", "message": "name is required"})
		return
	}
	// Auto-generate the running code when not given (P0001, P0002, …).
	if code == "" {
		generated, err := h.parts.GenerateNextPartCode(c.Request.Context())
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_generate_code"})
			return
		}
		code = generated
	}
	nameTh := strings.TrimSpace(req.NameTh)
	if nameTh == "" {
		nameTh = name
	}
	// Default barcode = the part code (Code128 renders it directly, same
	// convention as migration 0012); the client may override with its own.
	barcode := strings.TrimSpace(req.Barcode)
	if barcode == "" {
		barcode = code
	}
	// Unit is optional — default to "pcs" (ชิ้น).
	unitID := strings.TrimSpace(req.UnitId)
	if unitID == "" {
		unitID = strings.TrimSpace(req.Unit)
	}
	if unitID == "" {
		unitID = "pcs"
	}
	err := h.parts.CreatePart(c.Request.Context(), repository.PartInput{
		Code: code, Name: name, NameTH: nameTh, BarCode: barcode,
		UnitID: unitID, CategoryID: strings.TrimSpace(req.CategoryId),
		Price: req.Price, Cost: req.Cost, MinPrice: minPrice, Details: strings.TrimSpace(req.Details),
		IsActive: true,
	})
	if err != nil {
		if strings.Contains(err.Error(), "duplicate") || strings.Contains(err.Error(), "unique") {
			c.JSON(http.StatusConflict, gin.H{"error": "part_code_exists", "message": "รหัสสินค้านี้มีอยู่แล้ว"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_create_part", "message": err.Error()})
		return
	}
	// Initial placement in a store. When the client doesn't specify one, the
	// product goes into the main warehouse ('main' = คลังหลัก) by default.
	storeID := "main"
	addrErr := h.addresses.Create(c.Request.Context(), &repository.Address{
		Code:     "ADDR-" + code + "-" + storeID,
		PartCode: code,
		StoreID:  storeID,
		Shelf:    strings.TrimSpace(req.Shelf),
		Qty:      req.Qty,
	})
	if addrErr != nil {
		// Part was created; report placement failure without failing the call.
		c.JSON(http.StatusCreated, gin.H{
			"code": code, "barCode": barcode, "name": name,
			"warning": "part_created_but_address_failed",
		})
		return
	}
	c.JSON(http.StatusCreated, gin.H{"code": code, "barCode": barcode, "name": name})
}

// GenerateCode returns the next auto-generated part code and its default
// barcode so the create dialog can prefill both (both stay editable).
func (h *PartsHandler) GenerateCode(c *gin.Context) {
	code, err := h.parts.GenerateNextPartCode(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_generate_code"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"code": code, "barCode": code})
}

// Update edits an existing part's name/barcode/unit/price.
func (h *PartsHandler) Update(c *gin.Context) {
	code := strings.TrimSpace(c.Param("code"))
	if code == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_code"})
		return
	}
	var req struct {
		Name     string   `json:"name"`
		NameTh   string   `json:"nameTh"`
		Barcode  string   `json:"barcode"`
		Unit     string   `json:"unit"`
		UnitId   string   `json:"unitId"`
		Price    float64  `json:"price"`
		Cost     *float64 `json:"cost"`
		MinPrice *float64 `json:"minPrice"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": err.Error()})
		return
	}
	existing, _, err := h.parts.GetPartDetail(c.Request.Context(), code, nil)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "part_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_load_part"})
		return
	}
	cost := existing.Cost
	if req.Cost != nil {
		cost = *req.Cost
	}
	minPrice := existing.MinPrice
	if req.MinPrice != nil {
		minPrice = *req.MinPrice
	}
	if cost < 0 || req.Price < 0 || minPrice < 0 || minPrice > req.Price {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "invalid_prices",
			"message": "cost and prices must be non-negative, and minPrice must not exceed price",
		})
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
	if unitID == "" {
		unitID = "pcs" // หน่วยไม่บังคับ — ค่าเริ่มต้น "ชิ้น"
	}
	err = h.parts.UpdatePart(c.Request.Context(), code, repository.PartInput{
		Name: name, NameTH: nameTh, BarCode: barcode, UnitID: unitID,
		Price: req.Price, Cost: cost, MinPrice: minPrice,
	})
	if err != nil {
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
	mode, err := h.parts.DeletePart(c.Request.Context(), code)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "part_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_delete_part", "message": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"ok": true, "mode": mode})
}
