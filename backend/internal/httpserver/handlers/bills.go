package handlers

import (
	"net/http"
	"strconv"
	"time"

	"backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type BillsHandler struct {
	bills repository.BillRepository
}

func NewBillsHandler(bills repository.BillRepository) *BillsHandler {
	return &BillsHandler{bills: bills}
}

// Create creates a new empty bill with status "new".
// No input required; generates bill ID automatically using bill_counter.
func (h *BillsHandler) Create(c *gin.Context) {
	// Get authenticated user from context (set by RequireAuth middleware)
	userVal, exists := c.Get("user")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	user, ok := userVal.(*repository.User)
	if !ok {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "user_cast_error"})
		return
	}

	ctx := c.Request.Context()

	// Generate systematic bill ID (YYYYMMDD + 6-digit counter)
	billID, err := h.bills.GenerateBillID(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_generate_bill_id"})
		return
	}

	now := time.Now().UTC()

	// Create empty bill
	bill := &repository.Bill{
		ID:            billID,
		Status:        "new",
		PaymentMethod: "", // empty initially
		PurchaseAmount: 0,
		TotalDiscount:  0,
		TotalAmount:    0,
		VATAmount:      0,
		XVATAmount:     0,
		CreatedAt:      now,
		UpdatedAt:      now,
		CreatedBy:      user.ID,
		UpdatedBy:      user.ID,
	}

	if err := h.bills.Create(ctx, bill); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_create_bill"})
		return
	}

	// Return only the generated bill ID
	c.JSON(http.StatusCreated, gin.H{
		"id": billID,
	})
}

// List returns a paginated list of bills.
func (h *BillsHandler) List(c *gin.Context) {
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

	bills, err := h.bills.List(c.Request.Context(), limit, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_list_bills"})
		return
	}

	out := make([]gin.H, 0, len(bills))
	for _, b := range bills {
		out = append(out, gin.H{
			"id":            b.ID,
			"status":        b.Status,
			"paymentMethod": b.PaymentMethod,
			"purchaseAmount": b.PurchaseAmount,
			"totalDiscount":  b.TotalDiscount,
			"totalAmount":    b.TotalAmount,
			"vatAmount":      b.VATAmount,
			"xvatAmount":     b.XVATAmount,
			"createdAt":      b.CreatedAt.Format(time.RFC3339),
			"updatedAt":      b.UpdatedAt.Format(time.RFC3339),
			"createdBy":      b.CreatedBy,
			"updatedBy":      b.UpdatedBy,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"items": out,
	})
}

// Get returns a full bill with its details and discounts.
// Response format:
// {
//   ...bill_master_fields,
//   "details":   [ { ...bill_details } ],
//   "discounts": [ { ...bill_discount_detail } ]
// }
func (h *BillsHandler) Get(c *gin.Context) {
	id := c.Param("id")
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_bill_id"})
		return
	}

	b, details, discounts, err := h.bills.GetFullByID(c.Request.Context(), id)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "bill_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_bill"})
		return
	}

	detailOut := make([]gin.H, 0, len(details))
	for _, d := range details {
		detailOut = append(detailOut, gin.H{
			"billId":      d.BillID,
			"partCode":    d.PartCode,
			"addressCode": d.AddressCode,
			"unitId":      d.UnitID,
			"unitLabel":   d.UnitLabel,
			"unitLabelTh": d.UnitLabelTH,
			"name":        d.Name,
			"cost":        d.Cost,
			"price":       d.Price,
			"qty":         d.Qty,
		})
	}

	discountOut := make([]gin.H, 0, len(discounts))
	for _, d := range discounts {
		discountOut = append(discountOut, gin.H{
			"billId":        d.BillID,
			"promotionCode": d.PromotionCode,
			"unit":          d.Unit,
			"amount":        d.Amount,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"id":             b.ID,
		"status":         b.Status,
		"paymentMethod":  b.PaymentMethod,
		"purchaseAmount": b.PurchaseAmount,
		"totalDiscount":  b.TotalDiscount,
		"totalAmount":    b.TotalAmount,
		"vatAmount":      b.VATAmount,
		"xvatAmount":     b.XVATAmount,
		"createdAt":      b.CreatedAt.Format(time.RFC3339),
		"updatedAt":      b.UpdatedAt.Format(time.RFC3339),
		"createdBy":      b.CreatedBy,
		"updatedBy":      b.UpdatedBy,
		"details":        detailOut,
		"discounts":      discountOut,
	})
}

// AddItem adds an item to a bill (mock implementation)
func (h *BillsHandler) AddItem(c *gin.Context) {
	id := c.Param("id")
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_bill_id"})
		return
	}

	// Mock response
	c.JSON(http.StatusOK, gin.H{
		"message": "item_added",
		"billId":  id,
	})
}

// RemoveItem removes an item from a bill (mock implementation)
func (h *BillsHandler) RemoveItem(c *gin.Context) {
	id := c.Param("id")
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_bill_id"})
		return
	}

	// Mock response
	c.JSON(http.StatusOK, gin.H{
		"message": "item_removed",
		"billId":  id,
	})
}

// AddDiscount applies a discount to a bill (mock implementation)
func (h *BillsHandler) AddDiscount(c *gin.Context) {
	id := c.Param("id")
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_bill_id"})
		return
	}

	// Mock response
	c.JSON(http.StatusOK, gin.H{
		"message": "discount_added",
		"billId":  id,
	})
}

// RemoveDiscount removes a discount from a bill (mock implementation)
func (h *BillsHandler) RemoveDiscount(c *gin.Context) {
	id := c.Param("id")
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_bill_id"})
		return
	}

	// Mock response
	c.JSON(http.StatusOK, gin.H{
		"message": "discount_removed",
		"billId":  id,
	})
}

// Hold holds a bill (mock implementation)
func (h *BillsHandler) Hold(c *gin.Context) {
	id := c.Param("id")
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_bill_id"})
		return
	}

	// Mock response
	c.JSON(http.StatusOK, gin.H{
		"message": "bill_held",
		"billId":  id,
		"status":  "hold",
	})
}

// Resume resumes a held bill (mock implementation)
func (h *BillsHandler) Resume(c *gin.Context) {
	id := c.Param("id")
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_bill_id"})
		return
	}

	// Mock response
	c.JSON(http.StatusOK, gin.H{
		"message": "bill_resumed",
		"billId":  id,
		"status":  "new",
	})
}

// Checkout completes a bill (mock implementation)
func (h *BillsHandler) Checkout(c *gin.Context) {
	id := c.Param("id")
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_bill_id"})
		return
	}

	// Mock response
	c.JSON(http.StatusOK, gin.H{
		"message": "bill_checkout_completed",
		"billId":  id,
		"status":  "completed",
	})
}

// Payment processes payment for a bill (mock implementation)
func (h *BillsHandler) Payment(c *gin.Context) {
	id := c.Param("id")
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_bill_id"})
		return
	}

	// Mock response
	c.JSON(http.StatusOK, gin.H{
		"message": "payment_processed",
		"billId":  id,
		"status":  "completed",
	})
}


