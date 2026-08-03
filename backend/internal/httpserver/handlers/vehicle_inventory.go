package handlers

import (
	"net/http"
	"strings"
	"time"

	"backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type VehicleInventoryHandler struct {
	inventory repository.VehicleInventoryRepository
	pos       repository.POSRepository
}

func NewVehicleInventoryHandler(inventory repository.VehicleInventoryRepository, pos repository.POSRepository) *VehicleInventoryHandler {
	return &VehicleInventoryHandler{inventory: inventory, pos: pos}
}

func (h *VehicleInventoryHandler) List(c *gin.Context) {
	if !canReadAllOperationalData(c) {
		c.JSON(http.StatusForbidden, gin.H{"error": "global_scope_forbidden"})
		return
	}
	posID := strings.TrimSpace(c.Query("posId"))
	if posID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_pos_id"})
		return
	}
	pos, err := h.pos.GetByID(c.Request.Context(), posID)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "pos_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_pos"})
		return
	}
	if strings.TrimSpace(pos.VehicleStoreID) == "" || pos.VehicleStoreID == "main" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "pos_has_no_vehicle_stock"})
		return
	}
	location, err := time.LoadLocation("Asia/Bangkok")
	if err != nil {
		location = time.FixedZone("Asia/Bangkok", 7*60*60)
	}
	today := time.Now().In(location).Format("2006-01-02")
	fromText := strings.TrimSpace(c.Query("dateFrom"))
	toText := strings.TrimSpace(c.Query("dateTo"))
	if fromText == "" {
		fromText = today
	}
	if toText == "" {
		toText = fromText
	}
	from, err := time.ParseInLocation("2006-01-02", fromText, location)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_date_from"})
		return
	}
	to, err := time.ParseInLocation("2006-01-02", toText, location)
	if err != nil || to.Before(from) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_date_to"})
		return
	}
	items, err := h.inventory.List(c.Request.Context(), posID, from.UTC(), to.AddDate(0, 0, 1).UTC())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_list_vehicle_inventory"})
		return
	}
	totalCurrent, totalReceived, totalSold := 0, 0, 0
	totalValue := 0.0
	out := make([]gin.H, 0, len(items))
	for _, item := range items {
		totalCurrent += item.CurrentQty
		totalReceived += item.ReceivedQty
		totalSold += item.NetSoldQty
		totalValue += item.CurrentSaleValue
		out = append(out, gin.H{
			"partCode": item.PartCode, "partName": item.PartName, "partNameTh": item.PartNameTH,
			"barCode": item.BarCode, "currentQty": item.CurrentQty, "receivedQty": item.ReceivedQty,
			"netSoldQty": item.NetSoldQty, "price": item.Price, "currentSaleValue": item.CurrentSaleValue,
		})
	}
	c.JSON(http.StatusOK, gin.H{
		"pos":      gin.H{"posId": pos.POSID, "posName": pos.POSName, "branchId": pos.BranchID},
		"dateFrom": fromText, "dateTo": toText, "items": out,
		"summary": gin.H{
			"currentQty": totalCurrent, "receivedQty": totalReceived,
			"netSoldQty": totalSold, "currentSaleValue": totalValue,
		},
	})
}
