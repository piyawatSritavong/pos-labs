package handlers

import (
	"net/http"
	"strconv"

	"backend/internal/config"
	"backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type AddressHandler struct {
	addresses repository.AddressRepository
}

func NewAddressHandler(addresses repository.AddressRepository) *AddressHandler {
	return &AddressHandler{addresses: addresses}
}

func (h *AddressHandler) List(c *gin.Context) {
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

	// Optional server-side filters so the Addresses page can search + page on the
	// server instead of loading the whole catalog and filtering client-side.
	q := c.Query("q")
	storeID := c.Query("storeId")

	addresses, err := h.addresses.Search(c.Request.Context(), q, storeID, limit, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_list_addresses"})
		return
	}

	total, err := h.addresses.Count(c.Request.Context(), q, storeID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_count_addresses"})
		return
	}

	out := make([]gin.H, 0, len(addresses))
	for _, a := range addresses {
		out = append(out, gin.H{
			"code":      a.Code,
			"partCode":  a.PartCode,
			"partName":  a.PartName, // joined from part_master.name_th / name
			"storeId":   a.StoreID,
			"storeName": a.StoreName, // joined from store_master.label_th / label
			"shelf":     a.Shelf,
			"qty":       a.Qty,
			"min":       a.Min,
			"max":       a.Max,
			"rop":       a.Rop,
			"remarks":   a.Remarks,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"addresses": out,
		"total":     total,
	})
}

func (h *AddressHandler) Get(c *gin.Context) {
	code := c.Param("code")
	if code == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_address_code"})
		return
	}

	address, err := h.addresses.GetByCode(c.Request.Context(), code)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "address_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_address"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"code":     address.Code,
		"partCode": address.PartCode,
		"storeId":  address.StoreID,
		"shelf":    address.Shelf,
		"qty":      address.Qty,
		"min":      address.Min,
		"max":      address.Max,
		"rop":      address.Rop,
		"remarks":  address.Remarks,
	})
}

func (h *AddressHandler) Create(c *gin.Context) {
	var req struct {
		Code     string `json:"code" binding:"required"`
		PartCode string `json:"partCode" binding:"required"`
		StoreID  string `json:"storeId" binding:"required"`
		Shelf    string `json:"shelf"`
		Qty      int    `json:"qty"`
		Min      int    `json:"min"`
		Max      int    `json:"max"`
		Rop      int    `json:"rop"`
		Remarks  string `json:"remarks"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": err.Error()})
		return
	}

	address := &repository.Address{
		Code:     req.Code,
		PartCode: req.PartCode,
		StoreID:  req.StoreID,
		Shelf:    req.Shelf,
		Qty:      req.Qty,
		Min:      req.Min,
		Max:      req.Max,
		Rop:      req.Rop,
		Remarks:  req.Remarks,
	}

	if err := h.addresses.Create(c.Request.Context(), address); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_create_address"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"code":     address.Code,
		"partCode": address.PartCode,
		"storeId":  address.StoreID,
		"shelf":    address.Shelf,
		"qty":      address.Qty,
		"min":      address.Min,
		"max":      address.Max,
		"rop":      address.Rop,
		"remarks":  address.Remarks,
	})
}

func (h *AddressHandler) Update(c *gin.Context) {
	code := c.Param("code")
	if code == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_address_code"})
		return
	}

	var req struct {
		PartCode string `json:"partCode" binding:"required"`
		StoreID  string `json:"storeId" binding:"required"`
		Shelf    string `json:"shelf"`
		Qty      int    `json:"qty"`
		Min      int    `json:"min"`
		Max      int    `json:"max"`
		Rop      int    `json:"rop"`
		Remarks  string `json:"remarks"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": err.Error()})
		return
	}

	address := &repository.Address{
		Code:     code,
		PartCode: req.PartCode,
		StoreID:  req.StoreID,
		Shelf:    req.Shelf,
		Qty:      req.Qty,
		Min:      req.Min,
		Max:      req.Max,
		Rop:      req.Rop,
		Remarks:  req.Remarks,
	}

	if err := h.addresses.Update(c.Request.Context(), address); err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "address_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_update_address"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"code":     address.Code,
		"partCode": address.PartCode,
		"storeId":  address.StoreID,
		"shelf":    address.Shelf,
		"qty":      address.Qty,
		"min":      address.Min,
		"max":      address.Max,
		"rop":      address.Rop,
		"remarks":  address.Remarks,
	})
}

func (h *AddressHandler) Delete(c *gin.Context) {
	code := c.Param("code")
	if code == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_address_code"})
		return
	}

	if err := h.addresses.Delete(c.Request.Context(), code); err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "address_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_delete_address"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "address_deleted"})
}
