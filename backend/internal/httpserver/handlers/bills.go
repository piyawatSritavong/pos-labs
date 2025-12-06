package handlers

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"backend/internal/repository"

	"github.com/gin-gonic/gin"
)

// contains checks if a string contains a substring (case-insensitive)
func contains(s, substr string) bool {
	return strings.Contains(strings.ToLower(s), strings.ToLower(substr))
}

// getBranchAndPOSFromContext gets branchId and posId from context (set by RequireAuth middleware)
func (h *BillsHandler) getBranchAndPOSFromContext(c *gin.Context) (branchID, posID string, err error) {
	branchIDVal, exists := c.Get("branch_id")
	if !exists {
		return "", "", fmt.Errorf("missing_branch_id")
	}
	branchID, ok := branchIDVal.(string)
	if !ok || branchID == "" {
		return "", "", fmt.Errorf("invalid_branch_id")
	}

	posIDVal, exists := c.Get("pos_id")
	if !exists {
		return "", "", fmt.Errorf("missing_pos_id")
	}
	posID, ok = posIDVal.(string)
	if !ok || posID == "" {
		return "", "", fmt.Errorf("invalid_pos_id")
	}
	return branchID, posID, nil
}

// validateBillAccess validates that a bill belongs to the session's branch and POS
func (h *BillsHandler) validateBillAccess(ctx context.Context, billID, branchID, posID string) error {
	bill, err := h.bills.GetByID(ctx, billID)
	if err != nil {
		return err
	}
	if bill.BranchID != branchID || bill.POSID != posID {
		return fmt.Errorf("bill does not belong to branch %s and POS %s", branchID, posID)
	}
	return nil
}

type BillsHandler struct {
	bills   repository.BillRepository
	branches repository.BranchRepository
	pos     repository.POSRepository
}

func NewBillsHandler(bills repository.BillRepository, branches repository.BranchRepository, pos repository.POSRepository) *BillsHandler {
	return &BillsHandler{
		bills:    bills,
		branches: branches,
		pos:      pos,
	}
}

// Create creates a new empty bill with status "new".
// Uses branchId and posId from session (set at login).
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

	// Get branchId and posId from session (set by RequireAuth middleware)
	branchIDVal, exists := c.Get("branch_id")
	if !exists {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_branch_id"})
		return
	}
	branchID, ok := branchIDVal.(string)
	if !ok || branchID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_branch_id"})
		return
	}

	posIDVal, exists := c.Get("pos_id")
	if !exists {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_pos_id"})
		return
	}
	posID, ok := posIDVal.(string)
	if !ok || posID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_pos_id"})
		return
	}

	ctx := c.Request.Context()

	// Check if POS already has a bill with status "new"
	existingBill, err := h.bills.GetNewBillByPOS(ctx, posID)
	if err != nil && !repository.IsNotFoundError(err) {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_check_existing_bill"})
		return
	}
	if err == nil && existingBill != nil {
		c.JSON(http.StatusConflict, gin.H{
			"error": "pos_has_active_bill",
			"message": "POS already has a bill with status 'new'. Please hold the existing bill before creating a new one.",
			"existingBillId": existingBill.ID,
		})
		return
	}

	// Generate systematic bill ID (YYYYMMDD + 6-digit counter)
	billID, err := h.bills.GenerateBillID(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_generate_bill_id"})
		return
	}

	now := time.Now().UTC()

		// Create empty bill (using branchId and posId from session)
		newBill := &repository.Bill{
			ID:            billID,
			BranchID:      branchID,
			POSID:         posID,
			Status:        "new",
			PaymentMethod: "", // empty initially
			PaymentRef:    "",
			MemberID:      "",
			CustomerName:  "ทั่วไป", // default customer name
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

	if err := h.bills.Create(ctx, newBill); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": "failed_to_create_bill",
			"message": "Failed to create bill",
		})
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
		log.Printf("Error listing bills: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": "failed_to_list_bills",
			"message": err.Error(),
		})
		return
	}

	out := make([]gin.H, 0, len(bills))
	for _, b := range bills {
		out = append(out, gin.H{
			"id":            b.ID,
			"branchId":     b.BranchID,
			"posId":        b.POSID,
			"status":       b.Status,
			"paymentMethod": b.PaymentMethod,
			"paymentRef":   b.PaymentRef,
			"memberId":     b.MemberID,
			"customerName": b.CustomerName,
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
		"bills": out,
	})
}

// Get returns a full bill with its details and discounts.
// Uses branchId and posId from session (set at login).
// Response format:
// {
//   ...bill_master_fields,
//   "details":   [ { ...bill_item_detail } ],
//   "discounts": [ { ...bill_discount_detail } ]
// }
func (h *BillsHandler) Get(c *gin.Context) {
	id := c.Param("id")
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_bill_id"})
		return
	}

	// Get branchId and posId from session (set by RequireAuth middleware)
	branchID, posID, err := h.getBranchAndPOSFromContext(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
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

	// Validate bill belongs to session's branch and POS
	if b.BranchID != branchID || b.POSID != posID {
		c.JSON(http.StatusForbidden, gin.H{
			"error": "bill_access_denied",
			"message": "Bill does not belong to your current branch and POS",
		})
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
		"branchId":       b.BranchID,
		"posId":          b.POSID,
		"status":         b.Status,
		"paymentMethod":  b.PaymentMethod,
		"paymentRef":     b.PaymentRef,
		"memberId":       b.MemberID,
		"customerName":  b.CustomerName,
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

	branchID, posID, err := h.getBranchAndPOSFromContext(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate bill belongs to session's branch and POS
	if err := h.validateBillAccess(c.Request.Context(), id, branchID, posID); err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "bill_not_found"})
			return
		}
		c.JSON(http.StatusForbidden, gin.H{
			"error": "bill_access_denied",
			"message": "Bill does not belong to your current branch and POS",
		})
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

	branchID, posID, err := h.getBranchAndPOSFromContext(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate bill belongs to session's branch and POS
	if err := h.validateBillAccess(c.Request.Context(), id, branchID, posID); err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "bill_not_found"})
			return
		}
		c.JSON(http.StatusForbidden, gin.H{
			"error": "bill_access_denied",
			"message": "Bill does not belong to your current branch and POS",
		})
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

	branchID, posID, err := h.getBranchAndPOSFromContext(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate bill belongs to session's branch and POS
	if err := h.validateBillAccess(c.Request.Context(), id, branchID, posID); err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "bill_not_found"})
			return
		}
		c.JSON(http.StatusForbidden, gin.H{
			"error": "bill_access_denied",
			"message": "Bill does not belong to your current branch and POS",
		})
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

	branchID, posID, err := h.getBranchAndPOSFromContext(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate bill belongs to session's branch and POS
	if err := h.validateBillAccess(c.Request.Context(), id, branchID, posID); err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "bill_not_found"})
			return
		}
		c.JSON(http.StatusForbidden, gin.H{
			"error": "bill_access_denied",
			"message": "Bill does not belong to your current branch and POS",
		})
		return
	}

	// Mock response
	c.JSON(http.StatusOK, gin.H{
		"message": "discount_removed",
		"billId":  id,
	})
}

// Hold holds a bill
func (h *BillsHandler) Hold(c *gin.Context) {
	id := c.Param("id")
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_bill_id"})
		return
	}

	branchID, posID, err := h.getBranchAndPOSFromContext(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Get authenticated user from context
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

	// Validate bill belongs to session's branch and POS
	if err := h.validateBillAccess(c.Request.Context(), id, branchID, posID); err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "bill_not_found"})
			return
		}
		c.JSON(http.StatusForbidden, gin.H{
			"error": "bill_access_denied",
			"message": "Bill does not belong to your current branch and POS",
		})
		return
	}

	// Check if bill exists
	bill, err := h.bills.GetByID(c.Request.Context(), id)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "bill_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_bill"})
		return
	}

	// Only allow holding bills with status "new"
	if bill.Status != "new" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "invalid_bill_status",
			"message": "Only bills with status 'new' can be held",
			"currentStatus": bill.Status,
		})
		return
	}

	// Update status to "hold"
	if err := h.bills.UpdateStatus(c.Request.Context(), id, "hold", user.ID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_hold_bill"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "bill_held",
		"billId":  id,
		"status":  "hold",
	})
}

// SwitchBill switches to a target bill or creates a new bill:
// - If targetBillId is provided: switches to that bill (holds current "new" bill, resumes target)
// - If targetBillId is not provided or empty: creates a new bill (holds current "new" bill if exists)
func (h *BillsHandler) SwitchBill(c *gin.Context) {
	// Get branchId and posId from session (set by RequireAuth middleware)
	branchID, posID, err := h.getBranchAndPOSFromContext(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var req struct {
		TargetBillID string `json:"targetBillId"` // Optional - bill to resume (must be "hold" or "new")
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request"})
		return
	}

	// Get authenticated user from context
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

	// Case 1: Create new bill if targetBillId is not provided or empty
	if req.TargetBillID == "" {
		// Find current "new" bill for the same POS
		currentBill, err := h.bills.GetNewBillByPOS(ctx, posID)
		if err != nil && !repository.IsNotFoundError(err) {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_check_existing_bill"})
			return
		}

		var heldBillID string
		// If a "new" bill exists, hold it first
		if err == nil && currentBill != nil {
			if err := h.bills.UpdateStatus(ctx, currentBill.ID, "hold", user.ID); err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_hold_current_bill"})
				return
			}
			heldBillID = currentBill.ID
		}

		// Generate bill ID
		billID, err := h.bills.GenerateBillID(ctx)
		if err != nil {
			// Rollback: resume the held bill if we just held it
			if heldBillID != "" {
				h.bills.UpdateStatus(ctx, heldBillID, "new", user.ID)
			}
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_generate_bill_id"})
			return
		}

		now := time.Now().UTC()

		// Create new bill (using branchId and posId from session)
		bill := &repository.Bill{
			ID:            billID,
			BranchID:      branchID,
			POSID:         posID,
			Status:        "new",
			PaymentMethod: "",
			PaymentRef:    "",
			MemberID:      "",
			CustomerName:  "ทั่วไป",
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
			// Rollback: resume the held bill if we just held it
			if heldBillID != "" {
				h.bills.UpdateStatus(ctx, heldBillID, "new", user.ID)
			}
			c.JSON(http.StatusInternalServerError, gin.H{
				"error": "failed_to_create_bill",
				"message": "Failed to create bill",
			})
			return
		}

		// Get full bill details
		newBill, details, discounts, err := h.bills.GetFullByID(ctx, billID)
		if err != nil {
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

		response := gin.H{
			"id":             newBill.ID,
			"branchId":       newBill.BranchID,
			"posId":          newBill.POSID,
			"status":         newBill.Status,
			"paymentMethod":  newBill.PaymentMethod,
			"paymentRef":     newBill.PaymentRef,
			"memberId":       newBill.MemberID,
			"customerName":  newBill.CustomerName,
			"purchaseAmount": newBill.PurchaseAmount,
			"totalDiscount":  newBill.TotalDiscount,
			"totalAmount":    newBill.TotalAmount,
			"vatAmount":      newBill.VATAmount,
			"xvatAmount":     newBill.XVATAmount,
			"createdAt":      newBill.CreatedAt.Format(time.RFC3339),
			"updatedAt":      newBill.UpdatedAt.Format(time.RFC3339),
			"createdBy":      newBill.CreatedBy,
			"updatedBy":      newBill.UpdatedBy,
			"details":        detailOut,
			"discounts":      discountOut,
		}
		if heldBillID != "" {
			response["heldBillId"] = heldBillID
		}
		c.JSON(http.StatusOK, response)
		return
	}

	// Case 2: Switch to existing target bill
	// Get target bill
	targetBill, err := h.bills.GetByID(ctx, req.TargetBillID)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "target_bill_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_target_bill"})
		return
	}

	// If target bill is already "new" (current active bill), just return it
	if targetBill.Status == "new" {
		// Get full bill details
		bill, details, discounts, err := h.bills.GetFullByID(ctx, req.TargetBillID)
		if err != nil {
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
			"id":             bill.ID,
			"branchId":       bill.BranchID,
			"posId":          bill.POSID,
			"status":         bill.Status,
			"paymentMethod":  bill.PaymentMethod,
			"paymentRef":     bill.PaymentRef,
			"memberId":       bill.MemberID,
			"customerName":  bill.CustomerName,
			"purchaseAmount": bill.PurchaseAmount,
			"totalDiscount":  bill.TotalDiscount,
			"totalAmount":    bill.TotalAmount,
			"vatAmount":      bill.VATAmount,
			"xvatAmount":     bill.XVATAmount,
			"createdAt":      bill.CreatedAt.Format(time.RFC3339),
			"updatedAt":      bill.UpdatedAt.Format(time.RFC3339),
			"createdBy":      bill.CreatedBy,
			"updatedBy":      bill.UpdatedBy,
			"details":        detailOut,
			"discounts":      discountOut,
		})
		return
	}

	if targetBill.Status != "hold" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "invalid_target_bill_status",
			"message": "Target bill must have status 'hold' or 'new'",
			"currentStatus": targetBill.Status,
		})
		return
	}

	// Find current "new" bill for the same POS
	currentBill, err := h.bills.GetNewBillByPOS(ctx, targetBill.POSID)
	if err != nil && !repository.IsNotFoundError(err) {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_check_existing_bill"})
		return
	}

	// If no "new" bill exists, return error
	if repository.IsNotFoundError(err) || currentBill == nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "no_active_bill",
			"message": "No active bill found for this POS. Please create a new bill first.",
		})
		return
	}

	// Hold the current "new" bill
	var heldBillID string
	if err := h.bills.UpdateStatus(ctx, currentBill.ID, "hold", user.ID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_hold_current_bill"})
		return
	}
	heldBillID = currentBill.ID

	// Resume target bill
	if err := h.bills.UpdateStatus(ctx, req.TargetBillID, "new", user.ID); err != nil {
		// Rollback: resume the held bill if we just held it
		if heldBillID != "" {
			h.bills.UpdateStatus(ctx, heldBillID, "new", user.ID)
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_resume_target_bill"})
		return
	}

	// Get full bill details for the resumed bill
	resumedBill, details, discounts, err := h.bills.GetFullByID(ctx, req.TargetBillID)
	if err != nil {
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

	response := gin.H{
		"id":             resumedBill.ID,
		"branchId":       resumedBill.BranchID,
		"posId":          resumedBill.POSID,
		"status":         resumedBill.Status,
		"paymentMethod":  resumedBill.PaymentMethod,
		"paymentRef":     resumedBill.PaymentRef,
		"memberId":       resumedBill.MemberID,
		"customerName":  resumedBill.CustomerName,
		"purchaseAmount": resumedBill.PurchaseAmount,
		"totalDiscount":  resumedBill.TotalDiscount,
		"totalAmount":    resumedBill.TotalAmount,
		"vatAmount":      resumedBill.VATAmount,
		"xvatAmount":     resumedBill.XVATAmount,
		"createdAt":      resumedBill.CreatedAt.Format(time.RFC3339),
		"updatedAt":      resumedBill.UpdatedAt.Format(time.RFC3339),
		"createdBy":      resumedBill.CreatedBy,
		"updatedBy":      resumedBill.UpdatedBy,
		"details":        detailOut,
		"discounts":      discountOut,
	}
	if heldBillID != "" {
		response["heldBillId"] = heldBillID
	}
	c.JSON(http.StatusOK, response)
}

// Checkout completes a bill (mock implementation)
func (h *BillsHandler) Checkout(c *gin.Context) {
	id := c.Param("id")
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_bill_id"})
		return
	}

	branchID, posID, err := h.getBranchAndPOSFromContext(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate bill belongs to session's branch and POS
	if err := h.validateBillAccess(c.Request.Context(), id, branchID, posID); err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "bill_not_found"})
			return
		}
		c.JSON(http.StatusForbidden, gin.H{
			"error": "bill_access_denied",
			"message": "Bill does not belong to your current branch and POS",
		})
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

	branchID, posID, err := h.getBranchAndPOSFromContext(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate bill belongs to session's branch and POS
	if err := h.validateBillAccess(c.Request.Context(), id, branchID, posID); err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "bill_not_found"})
			return
		}
		c.JSON(http.StatusForbidden, gin.H{
			"error": "bill_access_denied",
			"message": "Bill does not belong to your current branch and POS",
		})
		return
	}

	// Mock response
	c.JSON(http.StatusOK, gin.H{
		"message": "payment_processed",
		"billId":  id,
		"status":  "completed",
	})
}


