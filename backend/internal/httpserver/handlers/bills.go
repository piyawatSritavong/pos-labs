package handlers

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"backend/internal/config"
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
	bills      repository.BillRepository
	branches   repository.BranchRepository
	pos        repository.POSRepository
	parts      repository.PartRepository
	company    repository.CompanyRepository
	promotions repository.PromotionRepository
}

func NewBillsHandler(bills repository.BillRepository, branches repository.BranchRepository, pos repository.POSRepository, parts repository.PartRepository, company repository.CompanyRepository, promotions repository.PromotionRepository) *BillsHandler {
	return &BillsHandler{
		bills:      bills,
		branches:   branches,
		pos:        pos,
		parts:      parts,
		company:    company,
		promotions: promotions,
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

	var req struct {
		PartCode    string `json:"partCode" binding:"required"`
		AddressCode string `json:"addressCode" binding:"required"`
		Qty         int    `json:"qty" binding:"required,min=1"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": err.Error()})
		return
	}

	ctx := c.Request.Context()

	// Check if part exists in the branch
	exists, err := h.parts.CheckPartExistsInBranch(ctx, req.PartCode, branchID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_check_part"})
		return
	}
	if !exists {
		c.JSON(http.StatusNotFound, gin.H{"error": "part_not_found", "message": "Part does not exist in this branch"})
		return
	}

	// Get part detail to get unit and price info (filtered by branch)
	partDetail, addresses, err := h.parts.GetPartDetail(ctx, req.PartCode, &branchID)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "part_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_part"})
		return
	}

	// Find the address in the addresses list
	var selectedAddress *repository.PartAddress
	for i := range addresses {
		if addresses[i].Code == req.AddressCode {
			selectedAddress = &addresses[i]
			break
		}
	}
	if selectedAddress == nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_address_code", "message": "Address code does not exist for this part"})
		return
	}

	// Check if item already exists in bill
	existingItem, err := h.bills.GetItemByPartCode(ctx, id, req.PartCode, req.AddressCode)
	if err != nil && !repository.IsNotFoundError(err) {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_check_existing_item"})
		return
	}

	// Get user for updated_by
	userVal, _ := c.Get("user")
	user, _ := userVal.(*repository.User)

	if existingItem != nil {
		// Update quantity (add to existing)
		newQty := existingItem.Qty + req.Qty
		if err := h.bills.UpdateItemQty(ctx, id, req.PartCode, req.AddressCode, newQty); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_update_item"})
			return
		}
	} else {
		// Insert new item
		detail := &repository.BillDetail{
			BillID:      id,
			PartCode:    req.PartCode,
			AddressCode: req.AddressCode,
			UnitID:     partDetail.UnitID,
			UnitLabel:  partDetail.UnitLabel,
			UnitLabelTH: partDetail.UnitLabelTH,
			Name:       partDetail.Name,
			Cost:       partDetail.Cost,
			Price:      partDetail.Price,
			Qty:        req.Qty,
		}
		if err := h.bills.AddItem(ctx, detail); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_add_item"})
			return
		}
	}

	// Update bill updated_at and updated_by
	if err := h.bills.UpdateTimestamp(ctx, id, user.ID); err != nil {
		// Log error but don't fail the request
		log.Printf("Warning: failed to update bill timestamp: %v", err)
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Item added successfully",
		"billId":  id,
	})
}

// AddItemByBarcode adds an item to a bill by barcode
func (h *BillsHandler) AddItemByBarcode(c *gin.Context) {
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

	var req struct {
		Barcode string `json:"barcode" binding:"required"`
		Qty     int    `json:"qty" binding:"required,min=1"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": err.Error()})
		return
	}

	ctx := c.Request.Context()

	// Get part by barcode (filtered by branch)
	partDetail, addresses, err := h.parts.GetPartByBarcode(ctx, req.Barcode, branchID)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "part_not_found", "message": "Part with this barcode not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_part"})
		return
	}

	// Check if part exists in the branch (addresses will be empty if not in branch stores)
	if len(addresses) == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "part_not_found", "message": "Part does not exist in this branch"})
		return
	}

	// Find default address (SQL already orders by is_default DESC, so first address should be default)
	// But we verify and require a default store to be configured
	var selectedAddress repository.PartAddress
	hasDefault := false
	for _, addr := range addresses {
		if addr.IsDefault {
			selectedAddress = addr
			hasDefault = true
			break
		}
	}

	// If no default store is configured, return error so frontend can use add-item endpoint
	if !hasDefault {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "no_default_store",
			"message": "Part exists in multiple stores but no default store is configured. Please use add-item endpoint to select a specific store address.",
		})
		return
	}

	// Check if item already exists in bill
	existingItem, err := h.bills.GetItemByPartCode(ctx, id, partDetail.Code, selectedAddress.Code)
	if err != nil && !repository.IsNotFoundError(err) {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_check_existing_item"})
		return
	}

	// Get user for updated_by
	userVal, _ := c.Get("user")
	user, _ := userVal.(*repository.User)

	if existingItem != nil {
		// Update quantity (add to existing)
		newQty := existingItem.Qty + req.Qty
		if err := h.bills.UpdateItemQty(ctx, id, partDetail.Code, selectedAddress.Code, newQty); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_update_item"})
			return
		}
	} else {
		// Insert new item
		detail := &repository.BillDetail{
			BillID:      id,
			PartCode:    partDetail.Code,
			AddressCode: selectedAddress.Code,
			UnitID:     partDetail.UnitID,
			UnitLabel:  partDetail.UnitLabel,
			UnitLabelTH: partDetail.UnitLabelTH,
			Name:       partDetail.Name,
			Cost:       partDetail.Cost,
			Price:      partDetail.Price,
			Qty:        req.Qty,
		}
		if err := h.bills.AddItem(ctx, detail); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_add_item"})
			return
		}
	}

	// Recalculate bill amounts
	if err := h.recalculateBillAmounts(ctx, id); err != nil {
		log.Printf("Warning: failed to recalculate bill amounts: %v", err)
	}

	// Update bill updated_at and updated_by
	if err := h.bills.UpdateTimestamp(ctx, id, user.ID); err != nil {
		log.Printf("Warning: failed to update bill timestamp: %v", err)
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Item added successfully",
		"billId":  id,
	})
}

// RemoveItem removes an item from a bill by part code
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

	var req struct {
		PartCode    string `json:"partCode" binding:"required"`
		AddressCode string `json:"addressCode" binding:"required"`
		Qty         int    `json:"qty"`         // Optional, default 1
		IsRemoveAll bool   `json:"isRemoveAll"` // If true, removes all regardless of qty
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": err.Error()})
		return
	}

	ctx := c.Request.Context()

	// Check if item exists in bill
	existingItem, err := h.bills.GetItemByPartCode(ctx, id, req.PartCode, req.AddressCode)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "item_not_found", "message": "Item does not exist in this bill"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_item"})
		return
	}

	// Get user for updated_by
	userVal, _ := c.Get("user")
	user, _ := userVal.(*repository.User)

	// Determine quantity to remove
	removeQty := req.Qty
	if removeQty <= 0 {
		removeQty = 1 // Default to 1 if not specified or invalid
	}

	if req.IsRemoveAll {
		// Delete the item completely
		if err := h.bills.RemoveItem(ctx, id, req.PartCode, req.AddressCode); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_remove_item"})
			return
		}
	} else {
		// Deduct quantity
		if existingItem.Qty > removeQty {
			newQty := existingItem.Qty - removeQty
			if err := h.bills.UpdateItemQty(ctx, id, req.PartCode, req.AddressCode, newQty); err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_update_item"})
				return
			}
		} else {
			// If qty to remove >= existing qty, delete the item
			if err := h.bills.RemoveItem(ctx, id, req.PartCode, req.AddressCode); err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_remove_item"})
				return
			}
		}
	}

	// Recalculate bill amounts
	if err := h.recalculateBillAmounts(ctx, id); err != nil {
		log.Printf("Warning: failed to recalculate bill amounts: %v", err)
	}

	// Update bill updated_at and updated_by
	if err := h.bills.UpdateTimestamp(ctx, id, user.ID); err != nil {
		log.Printf("Warning: failed to update bill timestamp: %v", err)
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Item removed successfully",
		"billId":  id,
	})
}

// recalculateBillAmounts calculates and updates bill amounts based on items and discounts
func (h *BillsHandler) recalculateBillAmounts(ctx context.Context, billID string) error {
	// Get all items
	items, err := h.bills.GetAllItems(ctx, billID)
	if err != nil {
		return err
	}

	// Calculate purchaseAmount (sum of all item prices * qty)
	var purchaseAmount float64
	for _, item := range items {
		purchaseAmount += item.Price * float64(item.Qty)
	}

	// Get all discounts
	discounts, err := h.bills.GetAllDiscounts(ctx, billID)
	if err != nil {
		return err
	}

	// Calculate totalDiscount
	var totalDiscount float64
	for _, discount := range discounts {
		if discount.Unit == "THB" {
			// Fixed amount discount
			totalDiscount += discount.Amount
		} else if discount.Unit == "percentage" {
			// Percentage discount on purchaseAmount
			totalDiscount += purchaseAmount * (discount.Amount / 100.0)
		}
	}

	// Get company settings for tax calculation
	company, err := h.company.Get(ctx)
	if err != nil {
		return err
	}

	// Calculate amounts after discount
	amountAfterDiscount := purchaseAmount - totalDiscount
	if amountAfterDiscount < 0 {
		amountAfterDiscount = 0
	}

	var vatAmount, xvatAmount, totalAmount float64

	if company.TaxType == "xvat" {
		// xvat: vatAmount = 0, xvatAmount = totalAmount - vatAmount = totalAmount
		vatAmount = 0
		totalAmount = amountAfterDiscount
		xvatAmount = totalAmount - vatAmount // = totalAmount
	} else {
		// vat: price already includes VAT, so we extract VAT from the amount
		// totalAmount = amountAfterDiscount (price including VAT)
		// vatAmount = amountAfterDiscount * (taxRate / (1 + taxRate))
		// xvatAmount = amountAfterDiscount - vatAmount
		totalAmount = amountAfterDiscount
		// Extract VAT: if price includes VAT, VAT = price * (rate / (1 + rate))
		// Example: if price is 107 and rate is 0.07, VAT = 107 * (0.07 / 1.07) = 7
		vatAmount = amountAfterDiscount * (company.TaxRate / (1.0 + company.TaxRate))
		xvatAmount = amountAfterDiscount - vatAmount
	}

	// Update bill amounts
	return h.bills.UpdateAmounts(ctx, billID, purchaseAmount, totalDiscount, totalAmount, vatAmount, xvatAmount)
}

// AddDiscount applies a discount to a bill
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

	var req struct {
		PromotionCode string `json:"promotionCode" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": err.Error()})
		return
	}

	ctx := c.Request.Context()

	// Validate promotion exists
	promotion, err := h.promotions.GetByCode(ctx, req.PromotionCode)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "promotion_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_promotion"})
		return
	}

	// Add discount
	discount := &repository.BillDiscountDetail{
		BillID:        id,
		PromotionCode: promotion.Code,
		Unit:          promotion.Unit,
		Amount:        promotion.Amount,
	}

	if err := h.bills.AddDiscount(ctx, discount); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_add_discount"})
		return
	}

	// Recalculate bill amounts
	if err := h.recalculateBillAmounts(ctx, id); err != nil {
		log.Printf("Warning: failed to recalculate bill amounts: %v", err)
	}

	// Get user for updated_by
	userVal, _ := c.Get("user")
	user, _ := userVal.(*repository.User)

	// Update bill updated_at and updated_by
	if err := h.bills.UpdateTimestamp(ctx, id, user.ID); err != nil {
		log.Printf("Warning: failed to update bill timestamp: %v", err)
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Discount added successfully",
		"billId":  id,
	})
}

// RemoveDiscount removes a discount from a bill
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

	var req struct {
		PromotionCode string `json:"promotionCode" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": err.Error()})
		return
	}

	ctx := c.Request.Context()

	// Check if discount exists
	_, err = h.bills.GetDiscountByCode(ctx, id, req.PromotionCode)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "discount_not_found", "message": "Discount does not exist in this bill"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_discount"})
		return
	}

	// Remove discount
	if err := h.bills.RemoveDiscount(ctx, id, req.PromotionCode); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_remove_discount"})
		return
	}

	// Recalculate bill amounts
	if err := h.recalculateBillAmounts(ctx, id); err != nil {
		log.Printf("Warning: failed to recalculate bill amounts: %v", err)
	}

	// Get user for updated_by
	userVal, _ := c.Get("user")
	user, _ := userVal.(*repository.User)

	// Update bill updated_at and updated_by
	if err := h.bills.UpdateTimestamp(ctx, id, user.ID); err != nil {
		log.Printf("Warning: failed to update bill timestamp: %v", err)
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Discount removed successfully",
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


