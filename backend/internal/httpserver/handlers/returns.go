package handlers

import (
	"encoding/json"
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

type ReturnNotesHandler struct {
	returns  repository.ReturnNoteRepository
	bills    repository.BillRepository
	members  repository.MemberRepository
	branches repository.BranchRepository
	pos      repository.POSRepository
}

func NewReturnNotesHandler(
	returns repository.ReturnNoteRepository,
	bills repository.BillRepository,
	members repository.MemberRepository,
	branches repository.BranchRepository,
	pos repository.POSRepository,
) *ReturnNotesHandler {
	return &ReturnNotesHandler{
		returns:  returns,
		bills:    bills,
		members:  members,
		branches: branches,
		pos:      pos,
	}
}

func (h *ReturnNotesHandler) buildMemberOutput(ctx *gin.Context, memberID string) interface{} {
	memberID = strings.TrimSpace(memberID)
	if memberID == "" {
		return nil
	}

	member, err := h.members.GetByID(ctx.Request.Context(), memberID)
	if err != nil {
		return nil
	}

	return gin.H{
		"id":   member.ID,
		"code": member.Code,
		"name": member.Name,
	}
}

func buildReturnNoteItemOutput(items []repository.ReturnNoteItem) []gin.H {
	out := make([]gin.H, 0, len(items))
	for _, item := range items {
		lineTotal := item.LineTotal
		if lineTotal <= 0 {
			lineTotal = item.Price * float64(item.Qty)
		}
		row := gin.H{
			"returnNoteId":    item.ReturnNoteID,
			"referenceBillId": item.ReferenceBillID,
			"partCode":        item.PartCode,
			"addressCode":     item.AddressCode,
			"unitId":          item.UnitID,
			"unitLabel":       item.UnitLabel,
			"unitLabelTh":     item.UnitLabelTH,
			"name":            item.Name,
			"price":           item.Price,
			"unitPrice":       item.Price,
			"qty":             item.Qty,
			"lineTotal":       lineTotal,
			"amount":          lineTotal,
			"total":           lineTotal,
		}
		if item.ReferenceLineQty > 0 {
			row["referenceQty"] = item.ReferenceLineQty
		}
		if item.ReturnedQty > 0 {
			row["returnedQty"] = item.ReturnedQty
		}
		if item.RemainingQty >= 0 {
			row["remainingQty"] = item.RemainingQty
		}
		out = append(out, row)
	}
	return out
}

func buildReturnNoteOutput(
	ctx *gin.Context,
	handler *ReturnNotesHandler,
	note *repository.ReturnNote,
	items []repository.ReturnNoteItem,
) gin.H {
	totalQty := 0
	for _, item := range items {
		totalQty += item.Qty
	}

	out := gin.H{
		"id":              note.ID,
		"referenceBillId": note.ReferenceBillID,
		"purchaseBillId":  note.PurchaseBillID,
		"branchId":        note.BranchID,
		"posId":           note.POSID,
		"status":          note.Status,
		"settlementMode":  note.SettlementMode,
		"memberId":        note.MemberID,
		"member":          handler.buildMemberOutput(ctx, note.MemberID),
		"customerName":    note.CustomerName,
		"purchaseAmount":  note.PurchaseAmount,
		"refundAmount":    note.RefundAmount,
		"netAmount":       note.NetAmount,
		"createdAt":       note.CreatedAt.Format(time.RFC3339),
		"updatedAt":       note.UpdatedAt.Format(time.RFC3339),
		"createdBy":       note.CreatedBy,
		"updatedBy":       note.UpdatedBy,
		"itemCount":       len(items),
		"totalQty":        totalQty,
		"details":         buildReturnNoteItemOutput(items),
		"items":           buildReturnNoteItemOutput(items),
	}
	attachPaymentOutput(out, note.PaymentMethod, note.PaymentRef)
	return out
}

func (h *ReturnNotesHandler) List(c *gin.Context) {
	branchIDVal, branchExists := c.Get("branch_id")
	posIDVal, posExists := c.Get("pos_id")

	var branchID, posID string
	if branchExists && branchIDVal != nil {
		if parsed, ok := branchIDVal.(string); ok {
			branchID = parsed
		}
	}
	if posExists && posIDVal != nil {
		if parsed, ok := posIDVal.(string); ok {
			posID = parsed
		}
	}

	limit := config.DefaultLimit
	offset := config.DefaultOffset
	if raw := c.Query("limit"); raw != "" {
		if parsed, err := strconv.Atoi(raw); err == nil && parsed > 0 && parsed <= config.MaxLimit {
			limit = parsed
		}
	}
	if raw := c.Query("offset"); raw != "" {
		if parsed, err := strconv.Atoi(raw); err == nil && parsed >= 0 {
			offset = parsed
		}
	}

	var dateFrom, dateTo *time.Time
	if dateStr := c.Query("date"); strings.TrimSpace(dateStr) != "" {
		date, err := parseDate(dateStr)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_date_format", "message": err.Error()})
			return
		}
		start := time.Date(date.Year(), date.Month(), date.Day(), 0, 0, 0, 0, time.UTC)
		end := start.Add(24 * time.Hour)
		dateFrom = &start
		dateTo = &end
	} else {
		if raw := c.Query("date_from"); strings.TrimSpace(raw) != "" {
			date, err := parseDate(raw)
			if err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_date_from_format", "message": err.Error()})
				return
			}
			start := time.Date(date.Year(), date.Month(), date.Day(), 0, 0, 0, 0, time.UTC)
			dateFrom = &start
		}
		if raw := c.Query("date_to"); strings.TrimSpace(raw) != "" {
			date, err := parseDate(raw)
			if err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_date_to_format", "message": err.Error()})
				return
			}
			end := time.Date(date.Year(), date.Month(), date.Day(), 0, 0, 0, 0, time.UTC).Add(24 * time.Hour)
			dateTo = &end
		}
	}

	if dateFrom == nil && dateTo == nil {
		utc7 := time.Now().UTC().Add(7 * time.Hour)
		year, month, day := utc7.Date()
		startUTC7 := time.Date(year, month, day, 0, 0, 0, 0, time.FixedZone("UTC+7", 7*3600))
		endUTC7 := startUTC7.Add(24 * time.Hour)
		startUTC := startUTC7.UTC()
		endUTC := endUTC7.UTC()
		dateFrom = &startUTC
		dateTo = &endUTC
	}

	scope := strings.ToLower(strings.TrimSpace(c.DefaultQuery("scope", "branch")))
	var branchFilter *string
	var posFilter *string
	switch scope {
	case "branch", "":
		if strings.TrimSpace(branchID) != "" {
			branchFilter = &branchID
		}
	case "pos":
		if strings.TrimSpace(branchID) != "" {
			branchFilter = &branchID
		}
		if strings.TrimSpace(posID) != "" {
			posFilter = &posID
		}
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_scope", "message": "scope must be 'pos' or 'branch'"})
		return
	}

	var referenceBillID *string
	if raw := strings.TrimSpace(c.Query("referenceBillId")); raw != "" {
		referenceBillID = &raw
	}

	includeDetails := parseBoolQuery(c.Query("includeDetails"))

	notes, err := h.returns.List(c.Request.Context(), limit, offset, dateFrom, dateTo, branchFilter, posFilter, referenceBillID)
	if err != nil {
		log.Printf("Error listing return notes: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_list_return_notes"})
		return
	}

	out := make([]gin.H, 0, len(notes))
	for _, note := range notes {
		items := make([]repository.ReturnNoteItem, 0)
		if includeDetails {
			items, err = h.returns.GetItems(c.Request.Context(), note.ID)
			if err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_return_note_items"})
				return
			}
		}
		entry := gin.H{
			"id":              note.ID,
			"referenceBillId": note.ReferenceBillID,
			"purchaseBillId":  note.PurchaseBillID,
			"branchId":        note.BranchID,
			"posId":           note.POSID,
			"status":          note.Status,
			"settlementMode":  note.SettlementMode,
			"memberId":        note.MemberID,
			"member":          h.buildMemberOutput(c, note.MemberID),
			"customerName":    note.CustomerName,
			"purchaseAmount":  note.PurchaseAmount,
			"refundAmount":    note.RefundAmount,
			"netAmount":       note.NetAmount,
			"createdAt":       note.CreatedAt.Format(time.RFC3339),
			"updatedAt":       note.UpdatedAt.Format(time.RFC3339),
			"createdBy":       note.CreatedBy,
			"updatedBy":       note.UpdatedBy,
			"itemCount":       len(items),
		}
		totalQty := 0
		for _, item := range items {
			totalQty += item.Qty
		}
		entry["totalQty"] = totalQty
		attachPaymentOutput(entry, note.PaymentMethod, note.PaymentRef)
		if includeDetails {
			itemOut := buildReturnNoteItemOutput(items)
			entry["details"] = itemOut
			entry["items"] = itemOut
		}
		out = append(out, entry)
	}

	c.JSON(http.StatusOK, gin.H{"returns": out})
}

func (h *ReturnNotesHandler) Get(c *gin.Context) {
	id := strings.TrimSpace(c.Param("id"))
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_return_note_id"})
		return
	}

	note, items, err := h.returns.GetByID(c.Request.Context(), id)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "return_note_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_return_note"})
		return
	}

	branchIDVal, branchExists := c.Get("branch_id")
	if branchExists && branchIDVal != nil {
		if branchID, ok := branchIDVal.(string); ok && strings.TrimSpace(branchID) != "" && note.BranchID != branchID {
			c.JSON(http.StatusForbidden, gin.H{"error": "return_note_access_denied"})
			return
		}
	}

	c.JSON(http.StatusOK, buildReturnNoteOutput(c, h, note, items))
}

func (h *ReturnNotesHandler) GetReferenceBill(c *gin.Context) {
	referenceBillID := strings.TrimSpace(c.Param("billId"))
	if referenceBillID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_reference_bill_id"})
		return
	}

	branchIDVal, branchExists := c.Get("branch_id")
	if !branchExists {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_branch_id"})
		return
	}
	branchID, _ := branchIDVal.(string)

	bill, details, discounts, err := h.bills.GetFullByID(c.Request.Context(), referenceBillID)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "bill_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_bill"})
		return
	}

	if strings.TrimSpace(branchID) != "" && bill.BranchID != branchID {
		c.JSON(http.StatusForbidden, gin.H{
			"error":   "bill_access_denied",
			"message": "Bill does not belong to your current branch",
		})
		return
	}
	if strings.ToLower(strings.TrimSpace(bill.Status)) != "completed" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "invalid_bill_status",
			"message": fmt.Sprintf("Bill status must be 'completed' to create a return. current status: '%s'", bill.Status),
		})
		return
	}

	returnedQtyByKey, err := h.returns.GetReturnedQtyByReferenceBill(c.Request.Context(), referenceBillID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_return_summary"})
		return
	}

	itemOut := make([]gin.H, 0, len(details))
	totalQty := 0
	itemCount := 0
	returnableCount := 0
	for _, detail := range details {
		key := detail.PartCode + "|" + detail.AddressCode
		returnedQty := returnedQtyByKey[key]
		remainingQty := detail.Qty - returnedQty
		if remainingQty < 0 {
			remainingQty = 0
		}
		totalQty += detail.Qty
		itemCount++
		if remainingQty > 0 {
			returnableCount++
		}
		lineTotal := detail.Price * float64(detail.Qty)
		itemOut = append(itemOut, gin.H{
			"billId":        detail.BillID,
			"partCode":      detail.PartCode,
			"addressCode":   detail.AddressCode,
			"unitId":        detail.UnitID,
			"unitLabel":     detail.UnitLabel,
			"unitLabelTh":   detail.UnitLabelTH,
			"name":          detail.Name,
			"partName":      detail.Name,
			"price":         detail.Price,
			"unitPrice":     detail.Price,
			"qty":           detail.Qty,
			"originalQty":   detail.Qty,
			"returnedQty":   returnedQty,
			"remainingQty":  remainingQty,
			"lineTotal":     lineTotal,
			"isReturnable":  remainingQty > 0,
			"returnableQty": remainingQty,
		})
	}

	response := gin.H{
		"id":              bill.ID,
		"referenceBillId": bill.ID,
		"branchId":        bill.BranchID,
		"posId":           bill.POSID,
		"status":          bill.Status,
		"memberId":        bill.MemberID,
		"member":          h.buildMemberOutput(c, bill.MemberID),
		"customerName":    bill.CustomerName,
		"purchaseAmount":  bill.PurchaseAmount,
		"totalDiscount":   bill.TotalDiscount,
		"amountAfterDiscount": maxFloat64(
			bill.PurchaseAmount-bill.TotalDiscount,
			0,
		),
		"totalAmount":     bill.TotalAmount,
		"vatAmount":       bill.VATAmount,
		"xvatAmount":      bill.XVATAmount,
		"createdAt":       bill.CreatedAt.Format(time.RFC3339),
		"updatedAt":       bill.UpdatedAt.Format(time.RFC3339),
		"itemCount":       itemCount,
		"totalQty":        totalQty,
		"returnableCount": returnableCount,
		"details":         itemOut,
		"items":           itemOut,
		"discounts":       buildBillDiscountOutput(discounts),
	}
	attachPaymentOutput(response, bill.PaymentMethod, bill.PaymentRef)

	c.JSON(http.StatusOK, response)
}

func normalizeReturnSettlementMode(raw string) string {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "cash", "cash_refund", "refund":
		return "cash_refund"
	case "credit", "customer_credit":
		return "customer_credit"
	case "exchange":
		return "exchange"
	default:
		return ""
	}
}

func (h *ReturnNotesHandler) Create(c *gin.Context) {
	branchIDVal, branchExists := c.Get("branch_id")
	posIDVal, posExists := c.Get("pos_id")
	if !branchExists || !posExists {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_branch_or_pos"})
		return
	}
	branchID, _ := branchIDVal.(string)
	posID, _ := posIDVal.(string)

	userVal, _ := c.Get("user")
	user, _ := userVal.(*repository.User)

	var req struct {
		ReferenceBillID string `json:"referenceBillId" binding:"required"`
		PurchaseBillID  string `json:"purchaseBillId"`
		SettlementMode  string `json:"settlementMode" binding:"required"`
		PaymentMethod   string `json:"paymentMethod"`
		PaymentRef      string `json:"paymentRef"`
		PaymentMeta     any    `json:"paymentMeta"`
		Lines           []struct {
			PartCode    string `json:"partCode" binding:"required"`
			AddressCode string `json:"addressCode" binding:"required"`
			Qty         int    `json:"qty" binding:"required,min=1"`
		} `json:"lines" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": err.Error()})
		return
	}

	settlementMode := normalizeReturnSettlementMode(req.SettlementMode)
	if settlementMode == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_settlement_mode"})
		return
	}
	if len(req.Lines) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_return_lines"})
		return
	}

	referenceBill, details, _, err := h.bills.GetFullByID(c.Request.Context(), strings.TrimSpace(req.ReferenceBillID))
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "bill_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_reference_bill"})
		return
	}
	if referenceBill.BranchID != branchID {
		c.JSON(http.StatusForbidden, gin.H{"error": "bill_access_denied"})
		return
	}
	if strings.ToLower(strings.TrimSpace(referenceBill.Status)) != "completed" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_bill_status", "message": "Reference bill must be completed"})
		return
	}

	var purchaseBill *repository.Bill
	if purchaseBillID := strings.TrimSpace(req.PurchaseBillID); purchaseBillID != "" {
		purchaseBill, err = h.bills.GetByID(c.Request.Context(), purchaseBillID)
		if err != nil {
			if repository.IsNotFoundError(err) {
				c.JSON(http.StatusNotFound, gin.H{"error": "purchase_bill_not_found"})
				return
			}
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_purchase_bill"})
			return
		}
		if purchaseBill.BranchID != branchID || strings.ToLower(strings.TrimSpace(purchaseBill.Status)) != "completed" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_purchase_bill"})
			return
		}
	}

	paymentRef := strings.TrimSpace(req.PaymentRef)
	if req.PaymentMeta != nil {
		raw, marshalErr := json.Marshal(req.PaymentMeta)
		if marshalErr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_payment_meta"})
			return
		}
		paymentRef = string(raw)
	}

	detailByKey := make(map[string]repository.BillDetail, len(details))
	for _, detail := range details {
		detailByKey[detail.PartCode+"|"+detail.AddressCode] = detail
	}

	returnedQtyByKey, err := h.returns.GetReturnedQtyByReferenceBill(c.Request.Context(), referenceBill.ID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_return_summary"})
		return
	}

	requestedQtyByKey := make(map[string]int)
	for _, line := range req.Lines {
		key := strings.TrimSpace(line.PartCode) + "|" + strings.TrimSpace(line.AddressCode)
		requestedQtyByKey[key] += line.Qty
	}

	items := make([]repository.ReturnNoteItem, 0, len(requestedQtyByKey))
	refundAmount := 0.0
	for key, qty := range requestedQtyByKey {
		detail, exists := detailByKey[key]
		if !exists {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_return_line", "message": fmt.Sprintf("Item %s was not found in reference bill", key)})
			return
		}
		remainingQty := detail.Qty - returnedQtyByKey[key]
		if qty <= 0 || qty > remainingQty {
			c.JSON(http.StatusBadRequest, gin.H{
				"error":   "invalid_return_qty",
				"message": fmt.Sprintf("Return qty for %s exceeds remaining qty (%d)", key, remainingQty),
			})
			return
		}
		lineTotal := detail.Price * float64(qty)
		refundAmount += lineTotal
		items = append(items, repository.ReturnNoteItem{
			ReferenceBillID:  referenceBill.ID,
			PartCode:         detail.PartCode,
			AddressCode:      detail.AddressCode,
			UnitID:           detail.UnitID,
			UnitLabel:        detail.UnitLabel,
			UnitLabelTH:      detail.UnitLabelTH,
			Name:             detail.Name,
			Price:            detail.Price,
			Qty:              qty,
			LineTotal:        lineTotal,
			ReferenceLineQty: detail.Qty,
			ReturnedQty:      returnedQtyByKey[key],
			RemainingQty:     remainingQty - qty,
		})
	}

	returnNoteID, err := h.returns.GenerateReturnNoteID(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_generate_return_note_id"})
		return
	}

	purchaseAmount := 0.0
	paymentMethod := strings.TrimSpace(req.PaymentMethod)
	if purchaseBill != nil {
		purchaseAmount = purchaseBill.TotalAmount
		if paymentMethod == "" {
			paymentMethod = purchaseBill.PaymentMethod
		}
		if paymentRef == "" {
			paymentRef = purchaseBill.PaymentRef
		}
	}
	netAmount := purchaseAmount - refundAmount

	note := &repository.ReturnNote{
		ID:              returnNoteID,
		ReferenceBillID: referenceBill.ID,
		PurchaseBillID:  strings.TrimSpace(req.PurchaseBillID),
		BranchID:        branchID,
		POSID:           posID,
		Status:          "completed",
		SettlementMode:  settlementMode,
		PaymentMethod:   paymentMethod,
		PaymentRef:      paymentRef,
		MemberID:        referenceBill.MemberID,
		CustomerName:    referenceBill.CustomerName,
		PurchaseAmount:  purchaseAmount,
		RefundAmount:    refundAmount,
		NetAmount:       netAmount,
		CreatedAt:       time.Now().UTC(),
		UpdatedAt:       time.Now().UTC(),
	}
	if user != nil {
		note.CreatedBy = user.ID
		note.UpdatedBy = user.ID
	}

	for i := range items {
		items[i].ReturnNoteID = returnNoteID
	}

	if err := h.returns.Create(c.Request.Context(), note, items); err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_return_address"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_create_return_note"})
		return
	}

	c.JSON(http.StatusCreated, buildReturnNoteOutput(c, h, note, items))
}
