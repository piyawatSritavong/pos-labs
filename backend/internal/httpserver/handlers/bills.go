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


