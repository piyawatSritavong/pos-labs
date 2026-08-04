package handlers

import (
	"net/http"
	"strconv"
	"strings"
	"time"

	"backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type PurchaseOrderHandler struct {
	orders repository.PurchaseOrderRepository
}

func NewPurchaseOrderHandler(orders repository.PurchaseOrderRepository) *PurchaseOrderHandler {
	return &PurchaseOrderHandler{orders: orders}
}

func purchaseOrderOutput(order *repository.PurchaseOrder, items []repository.PurchaseOrderItem) gin.H {
	itemOut := make([]gin.H, 0, len(items))
	for _, item := range items {
		itemOut = append(itemOut, gin.H{
			"lineNo": item.LineNo, "partCode": item.PartCode, "partName": item.PartName,
			"barCode": item.BarCode, "qty": item.Qty, "cost": item.Cost, "price": item.Price,
			"minPrice": item.MinPrice, "lineCost": item.LineCost, "lineSaleValue": item.LineSaleValue,
		})
	}
	return gin.H{
		"id": order.ID, "requestId": order.RequestID, "orderDate": order.OrderDate.Format("2006-01-02"),
		"notes": order.Notes, "createdBy": order.CreatedBy, "createdAt": order.CreatedAt.Format(time.RFC3339),
		"totalCost": order.TotalCost, "totalSaleValue": order.TotalSaleValue, "items": itemOut,
	}
}

func requirePurchaseOrderAdmin(c *gin.Context) bool {
	if canReadAllOperationalData(c) {
		return true
	}
	c.JSON(http.StatusForbidden, gin.H{"error": "admin_only"})
	return false
}

func (h *PurchaseOrderHandler) Create(c *gin.Context) {
	if !requirePurchaseOrderAdmin(c) {
		return
	}
	user := currentRequestUser(c)
	var req struct {
		RequestID string `json:"requestId"`
		OrderDate string `json:"orderDate"`
		Notes     string `json:"notes"`
		Items     []struct {
			PartCode string  `json:"partCode"`
			PartName string  `json:"partName"`
			BarCode  string  `json:"barCode"`
			Qty      int     `json:"qty"`
			Cost     float64 `json:"cost"`
			Price    float64 `json:"price"`
			MinPrice float64 `json:"minPrice"`
		} `json:"items"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": err.Error()})
		return
	}
	requestID := strings.TrimSpace(req.RequestID)
	if requestID == "" || len(req.Items) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_fields", "message": "requestId and items are required"})
		return
	}
	location, err := time.LoadLocation("Asia/Bangkok")
	if err != nil {
		location = time.FixedZone("Asia/Bangkok", 7*60*60)
	}
	orderDate := time.Now().In(location)
	if strings.TrimSpace(req.OrderDate) != "" {
		orderDate, err = time.ParseInLocation("2006-01-02", strings.TrimSpace(req.OrderDate), location)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_order_date"})
			return
		}
	}
	items := make([]repository.PurchaseOrderInputItem, 0, len(req.Items))
	for index, item := range req.Items {
		if strings.TrimSpace(item.PartName) == "" || item.Qty <= 0 || item.Cost < 0 || item.Price < 0 || item.MinPrice < 0 || item.MinPrice > item.Price {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "invalid_item", "line": index + 1,
				"message": "name is required, qty must be positive, and 0 <= minPrice <= price",
			})
			return
		}
		items = append(items, repository.PurchaseOrderInputItem{
			PartCode: item.PartCode, PartName: item.PartName, BarCode: item.BarCode,
			Qty: item.Qty, Cost: item.Cost, Price: item.Price, MinPrice: item.MinPrice,
		})
	}
	order, createdItems, created, err := h.orders.Create(c.Request.Context(), requestID, orderDate, req.Notes, user.ID, items)
	if err != nil {
		message := err.Error()
		switch {
		case strings.HasPrefix(message, "duplicate_part_code:"):
			c.JSON(http.StatusBadRequest, gin.H{"error": "duplicate_part_code", "message": message})
		case strings.HasPrefix(message, "duplicate_barcode:"):
			c.JSON(http.StatusBadRequest, gin.H{"error": "duplicate_barcode", "message": message})
		case strings.HasPrefix(message, "barcode_exists:"):
			c.JSON(http.StatusConflict, gin.H{"error": "barcode_exists", "message": message})
		default:
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_create_purchase_order"})
		}
		return
	}
	status := http.StatusCreated
	if !created {
		status = http.StatusOK
	}
	c.JSON(status, gin.H{"data": purchaseOrderOutput(order, createdItems), "created": created})
}

func (h *PurchaseOrderHandler) List(c *gin.Context) {
	if !requirePurchaseOrderAdmin(c) {
		return
	}
	limit, offset := 50, 0
	if value, err := strconv.Atoi(c.Query("limit")); err == nil && value > 0 && value <= 200 {
		limit = value
	}
	if value, err := strconv.Atoi(c.Query("offset")); err == nil && value >= 0 {
		offset = value
	}
	orders, err := h.orders.List(c.Request.Context(), limit, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_list_purchase_orders"})
		return
	}
	out := make([]gin.H, 0, len(orders))
	for index := range orders {
		out = append(out, purchaseOrderOutput(&orders[index], nil))
	}
	c.JSON(http.StatusOK, gin.H{"data": out, "total": len(out)})
}

func (h *PurchaseOrderHandler) GetByID(c *gin.Context) {
	if !requirePurchaseOrderAdmin(c) {
		return
	}
	order, items, err := h.orders.GetByID(c.Request.Context(), strings.TrimSpace(c.Param("id")))
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "purchase_order_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_purchase_order"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": purchaseOrderOutput(order, items)})
}

func (h *PurchaseOrderHandler) Delete(c *gin.Context) {
	if !requirePurchaseOrderAdmin(c) {
		return
	}
	id := strings.TrimSpace(c.Param("id"))
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_purchase_order_id"})
		return
	}
	if err := h.orders.Delete(c.Request.Context(), id); err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "purchase_order_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_delete_purchase_order"})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"data": gin.H{"id": id, "mode": "document_only"},
	})
}
