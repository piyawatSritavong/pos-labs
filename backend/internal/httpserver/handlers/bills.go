package handlers

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"backend/internal/config"
	"backend/internal/printer"
	"backend/internal/receiptname"
	"backend/internal/repository"

	"github.com/gin-gonic/gin"
)

const manualDiscountPromotionCode = "SYS_MANUAL_DISCOUNT"

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

func (h *BillsHandler) getVehicleStoreID(ctx context.Context, posID string) (string, error) {
	pos, err := h.pos.GetByID(ctx, posID)
	if err != nil {
		return "", err
	}
	storeID := strings.TrimSpace(pos.VehicleStoreID)
	if storeID == "" {
		return "", fmt.Errorf("pos_store_not_configured")
	}
	return storeID, nil
}

func salesAddressForPOS(addresses []repository.PartAddress, vehicleStoreID string) (repository.PartAddress, bool) {
	if strings.TrimSpace(vehicleStoreID) != "" {
		for _, addr := range addresses {
			if addr.StoreID == vehicleStoreID && addr.Qty > 0 {
				return addr, true
			}
		}
		for _, addr := range addresses {
			if addr.StoreID == vehicleStoreID {
				return addr, true
			}
		}
		return repository.PartAddress{}, false
	}
	// No vehicle restriction → prefer an address that actually has stock, then
	// the default address, then the first available.
	for _, addr := range addresses {
		if addr.Qty > 0 {
			return addr, true
		}
	}
	for _, addr := range addresses {
		if addr.IsDefault {
			return addr, true
		}
	}
	if len(addresses) > 0 {
		return addresses[0], true
	}
	return repository.PartAddress{}, false
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

// validateBillStatusNew validates that a bill has status "new"
func (h *BillsHandler) validateBillStatusNew(ctx context.Context, billID string) error {
	bill, err := h.bills.GetByID(ctx, billID)
	if err != nil {
		return err
	}
	if bill.Status != "new" {
		return fmt.Errorf("bill status must be 'new', current status: '%s'", bill.Status)
	}
	return nil
}

func parseBillStatuses(raw string) []string {
	if strings.TrimSpace(raw) == "" {
		return nil
	}

	seen := make(map[string]struct{})
	out := make([]string, 0)
	for _, part := range strings.Split(raw, ",") {
		status := strings.TrimSpace(strings.ToLower(part))
		if status == "" {
			continue
		}
		if _, exists := seen[status]; exists {
			continue
		}
		seen[status] = struct{}{}
		out = append(out, status)
	}
	return out
}

func allStatusesActive(statuses []string) bool {
	if len(statuses) == 0 {
		return false
	}
	for _, status := range statuses {
		switch strings.TrimSpace(strings.ToLower(status)) {
		case "new", "hold":
		default:
			return false
		}
	}
	return true
}

func parseBoolQuery(raw string) bool {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "1", "true", "yes", "y":
		return true
	default:
		return false
	}
}

func buildBillDetailOutput(details []repository.BillDetail) []gin.H {
	detailOut := make([]gin.H, 0, len(details))
	for _, d := range details {
		lineTotal := d.Price * float64(d.Qty)
		detailOut = append(detailOut, gin.H{
			"billId":      d.BillID,
			"partCode":    d.PartCode,
			"addressCode": d.AddressCode,
			"unitId":      d.UnitID,
			"unitLabel":   d.UnitLabel,
			"unitLabelTh": d.UnitLabelTH,
			"name":        d.Name,
			"partName":    d.Name,
			"receiptName": d.ReceiptName,
			"cost":        d.Cost,
			"price":       d.Price,
			"unitPrice":   d.Price,
			"qty":         d.Qty,
			"amount":      lineTotal,
			"total":       lineTotal,
			"lineTotal":   lineTotal,
			"totalStock":  d.TotalStock,
		})
	}
	return detailOut
}

func buildBillDiscountOutput(discounts []repository.BillDiscountDetail) []gin.H {
	discountOut := make([]gin.H, 0, len(discounts))
	for _, d := range discounts {
		discountOut = append(discountOut, gin.H{
			"billId":        d.BillID,
			"promotionCode": d.PromotionCode,
			"unit":          d.Unit,
			"amount":        d.Amount,
		})
	}
	return discountOut
}

func buildBillItemSummary(details []repository.BillDetail) (itemCount int, totalQty int) {
	itemCount = len(details)
	totalQty = 0
	for _, detail := range details {
		totalQty += detail.Qty
	}
	return itemCount, totalQty
}

func (h *BillsHandler) restoreInventoryAfterFailedAdd(ctx context.Context, addressCode string, qty int) {
	if qty <= 0 || strings.TrimSpace(addressCode) == "" {
		return
	}
	if err := h.addresses.IncreaseInventory(ctx, addressCode, qty); err != nil {
		log.Printf("critical: failed to restore inventory for address %s after add-item failure: %v", addressCode, err)
	}
}

func (h *BillsHandler) rollbackAddedBillItem(ctx context.Context, billID, partCode, addressCode string, addedQty int, hadExisting bool, previousQty int) {
	if hadExisting {
		if err := h.bills.UpdateItemQty(ctx, billID, partCode, addressCode, previousQty); err != nil {
			log.Printf("critical: failed to restore previous bill item qty for bill %s part %s address %s: %v", billID, partCode, addressCode, err)
		}
	} else {
		if err := h.bills.RemoveItem(ctx, billID, partCode, addressCode); err != nil {
			log.Printf("critical: failed to remove bill item during add-item rollback for bill %s part %s address %s: %v", billID, partCode, addressCode, err)
		}
	}
	h.restoreInventoryAfterFailedAdd(ctx, addressCode, addedQty)
}

func (h *BillsHandler) buildMemberOutput(ctx context.Context, memberID string) interface{} {
	if strings.TrimSpace(memberID) == "" {
		return nil
	}

	member, err := h.members.GetByID(ctx, memberID)
	if err != nil {
		return nil
	}

	return gin.H{
		"id":   member.ID,
		"code": member.Code,
		"name": member.Name,
	}
}

// batchMembers resolves the member object for every bill in a list using a
// single GetByIDs query (avoids the per-bill GetByID N+1). The result is keyed
// by member ID; bills with no/unknown member simply miss the map (→ JSON null).
func (h *BillsHandler) batchMembers(ctx context.Context, bills []repository.Bill) map[string]interface{} {
	ids := make([]string, 0, len(bills))
	seen := make(map[string]struct{})
	for _, b := range bills {
		id := strings.TrimSpace(b.MemberID)
		if id == "" {
			continue
		}
		if _, ok := seen[id]; ok {
			continue
		}
		seen[id] = struct{}{}
		ids = append(ids, id)
	}

	out := make(map[string]interface{}, len(ids))
	if len(ids) == 0 {
		return out
	}
	members, err := h.members.GetByIDs(ctx, ids)
	if err != nil {
		return out
	}
	for id, m := range members {
		out[id] = gin.H{
			"id":   m.ID,
			"code": m.Code,
			"name": m.Name,
		}
	}
	return out
}

// resolveUserNames maps user ids → display name (name, else username, else the
// id) in a single query, so created_by/updated_by show e.g. "Administrator"
// instead of a raw id. Missing/unknown ids fall back to the id.
func (h *BillsHandler) resolveUserNames(ctx context.Context, ids ...string) map[string]string {
	out := make(map[string]string)
	uniq := make([]string, 0, len(ids))
	seen := make(map[string]struct{})
	for _, id := range ids {
		id = strings.TrimSpace(id)
		if id == "" {
			continue
		}
		if _, ok := seen[id]; ok {
			continue
		}
		seen[id] = struct{}{}
		uniq = append(uniq, id)
	}
	if len(uniq) == 0 || h.users == nil {
		return out
	}
	users, err := h.users.GetByIDs(ctx, uniq)
	if err != nil {
		return out
	}
	for id, u := range users {
		name := strings.TrimSpace(u.Name)
		if name == "" {
			name = strings.TrimSpace(u.Username)
		}
		if name == "" {
			name = id
		}
		out[id] = name
	}
	return out
}

// userDisplayName returns the resolved name for id, or the id itself if unknown.
func userDisplayName(names map[string]string, id string) string {
	if n, ok := names[id]; ok && n != "" {
		return n
	}
	return id
}

func normalizeDiscountUnit(raw string) (string, bool) {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "thb", "baht", "amount":
		return "THB", true
	case "%", "percent", "percentage":
		return "percentage", true
	default:
		return "", false
	}
}

func maxFloat64(a, b float64) float64 {
	if a > b {
		return a
	}
	return b
}

func (h *BillsHandler) ensureManualDiscountPromotion(ctx context.Context) error {
	_, err := h.promotions.GetByCode(ctx, manualDiscountPromotionCode)
	if err == nil {
		return nil
	}
	if !repository.IsNotFoundError(err) {
		return err
	}

	createErr := h.promotions.Create(ctx, &repository.Promotion{
		Code:    manualDiscountPromotionCode,
		Details: "System manual discount placeholder",
		Unit:    "THB",
		Amount:  0,
	})
	if createErr == nil {
		return nil
	}

	_, retryErr := h.promotions.GetByCode(ctx, manualDiscountPromotionCode)
	if retryErr == nil {
		return nil
	}
	return createErr
}

// insufficientInventory reports a failed stock check with the quantity that is
// actually on the vehicle. Telling a cashier only that the request failed
// leaves them guessing at the number; the number is the whole answer.
func (h *BillsHandler) insufficientInventory(c *gin.Context, addressCode string, requested int) {
	available := 0
	if address, err := h.addresses.GetByCode(c.Request.Context(), addressCode); err == nil {
		available = address.Qty
	}
	c.JSON(http.StatusBadRequest, gin.H{
		"error":        "not_enough_inventory",
		"message":      fmt.Sprintf("สต๊อกไม่พอ ขอ %d ชิ้น เหลือในคลังของ POS นี้ %d ชิ้น", requested, available),
		"requestedQty": requested,
		"availableQty": available,
		"addressCode":  addressCode,
	})
}

func (h *BillsHandler) respondWithFullBill(c *gin.Context, billID string) {
	start := time.Now()
	bill, details, discounts, err := h.bills.GetFullByID(c.Request.Context(), billID)
	logSlowTiming("bills.respond.get_full", start, "bill_id", billID, "ok", err == nil)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "bill_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_bill"})
		return
	}

	detailOut := buildBillDetailOutput(details)
	discountOut := buildBillDiscountOutput(discounts)
	itemCount, totalQty := buildBillItemSummary(details)
	userNames := h.resolveUserNames(
		c.Request.Context(),
		bill.CreatedBy,
		bill.UpdatedBy,
	)

	response := gin.H{
		"id":                  bill.ID,
		"branchId":            bill.BranchID,
		"posId":               bill.POSID,
		"status":              bill.Status,
		"memberId":            bill.MemberID,
		"member":              h.buildMemberOutput(c.Request.Context(), bill.MemberID),
		"customerName":        bill.CustomerName,
		"purchaseAmount":      bill.PurchaseAmount,
		"totalDiscount":       bill.TotalDiscount,
		"memberDiscount":      bill.MemberDiscount,
		"manualDiscount":      maxFloat64(bill.TotalDiscount-bill.MemberDiscount, 0),
		"roundingAmount":      bill.RoundingAmount,
		"amountAfterDiscount": maxFloat64(bill.PurchaseAmount-bill.TotalDiscount, 0),
		"totalAmount":         bill.TotalAmount,
		"cashReceived":        bill.CashReceived,
		"changeAmount":        bill.ChangeAmount,
		"vatAmount":           bill.VATAmount,
		"xvatAmount":          bill.XVATAmount,
		"dateTime":            bill.CreatedAt.Format(time.RFC3339),
		"createdAt":           bill.CreatedAt.Format(time.RFC3339),
		"updatedAt":           bill.UpdatedAt.Format(time.RFC3339),
		"createdBy":           bill.CreatedBy,
		"updatedBy":           bill.UpdatedBy,
		"createdByName":       userDisplayName(userNames, bill.CreatedBy),
		"updatedByName":       userDisplayName(userNames, bill.UpdatedBy),
		"itemCount":           itemCount,
		"totalQty":            totalQty,
		"details":             detailOut,
		"items":               detailOut,
		"discounts":           discountOut,
	}
	attachPaymentOutput(response, bill.PaymentMethod, bill.PaymentRef)
	c.JSON(http.StatusOK, response)
}

type BillsHandler struct {
	bills      repository.BillRepository
	branches   repository.BranchRepository
	pos        repository.POSRepository
	parts      repository.PartRepository
	members    repository.MemberRepository
	company    repository.CompanyRepository
	promotions repository.PromotionRepository
	addresses  repository.AddressRepository
	users      repository.UserRepository
	// PrinterTarget is the resolved RECEIPT_PRINTER_TARGET (port name or share name).
	// Empty disables PrintReceipt; the handler reports a clear error in that case.
	PrinterTarget  string
	PrinterEnabled bool
	// PrinterCharset is the ESC t code page number sent before any text.
	// 0 leaves the BuildReceipt default (21 = Thai CP874).
	PrinterCharset byte
	PrinterMode    string
	OpenCashDrawer bool
	DrawerKick     []byte
	printMu        sync.Mutex
	recentPrints   map[string]time.Time
}

func NewBillsHandler(bills repository.BillRepository, branches repository.BranchRepository, pos repository.POSRepository, parts repository.PartRepository, members repository.MemberRepository, company repository.CompanyRepository, promotions repository.PromotionRepository, addresses repository.AddressRepository, users repository.UserRepository) *BillsHandler {
	return &BillsHandler{
		bills:          bills,
		branches:       branches,
		pos:            pos,
		parts:          parts,
		members:        members,
		company:        company,
		promotions:     promotions,
		addresses:      addresses,
		users:          users,
		PrinterEnabled: true,
		PrinterMode:    printer.ModeASCII,
		recentPrints:   make(map[string]time.Time),
	}
}

func (h *BillsHandler) beginPrint(idempotencyKey string) bool {
	key := strings.TrimSpace(idempotencyKey)
	if key == "" {
		return true
	}

	h.printMu.Lock()
	defer h.printMu.Unlock()

	if h.recentPrints == nil {
		h.recentPrints = make(map[string]time.Time)
	}
	now := time.Now()
	for k, t := range h.recentPrints {
		if now.Sub(t) > 15*time.Minute {
			delete(h.recentPrints, k)
		}
	}
	if _, exists := h.recentPrints[key]; exists {
		return false
	}
	h.recentPrints[key] = now
	return true
}

func (h *BillsHandler) completePrint(idempotencyKey string, success bool) {
	key := strings.TrimSpace(idempotencyKey)
	if key == "" || success {
		return
	}
	h.printMu.Lock()
	defer h.printMu.Unlock()
	delete(h.recentPrints, key)
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
			"error":          "pos_has_active_bill",
			"message":        "POS already has a bill with status 'new'. Please hold the existing bill before creating a new one.",
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
		ID:             billID,
		BranchID:       branchID,
		POSID:          posID,
		Status:         "new",
		PaymentMethod:  "", // empty initially
		PaymentRef:     "",
		MemberID:       "",
		CustomerName:   "ทั่วไป", // default customer name
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
			"error":   "failed_to_create_bill",
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
	branchID, posID, err := h.getBranchAndPOSFromContext(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

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

	// Parse date filtering parameters
	var dateFrom, dateTo *time.Time

	// Support both "date" (single day) and "date_from"/"date_to" (range)
	if dateStr := c.Query("date"); dateStr != "" {
		date, err := parseDate(dateStr)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{
				"error":   "invalid_date_format",
				"message": err.Error(),
			})
			return
		}
		// For single date, set both from and to to the same day
		dateStart := time.Date(date.Year(), date.Month(), date.Day(), 0, 0, 0, 0, time.UTC)
		dateEnd := dateStart.Add(24 * time.Hour)
		dateFrom = &dateStart
		dateTo = &dateEnd
	} else {
		// Support date range with date_from and date_to
		if dateFromStr := c.Query("date_from"); dateFromStr != "" {
			date, err := parseDate(dateFromStr)
			if err != nil {
				c.JSON(http.StatusBadRequest, gin.H{
					"error":   "invalid_date_from_format",
					"message": err.Error(),
				})
				return
			}
			dateStart := time.Date(date.Year(), date.Month(), date.Day(), 0, 0, 0, 0, time.UTC)
			dateFrom = &dateStart
		}
		if dateToStr := c.Query("date_to"); dateToStr != "" {
			date, err := parseDate(dateToStr)
			if err != nil {
				c.JSON(http.StatusBadRequest, gin.H{
					"error":   "invalid_date_to_format",
					"message": err.Error(),
				})
				return
			}
			dateEnd := time.Date(date.Year(), date.Month(), date.Day(), 0, 0, 0, 0, time.UTC).Add(24 * time.Hour)
			dateTo = &dateEnd
		}
	}

	statuses := parseBillStatuses(c.Query("statuses"))

	// If no date parameters provided, default to current date in UTC+7.
	// Active POS work queues must not be date-scoped; otherwise an old "new"
	// bill can block POST /bills while GET /bills?statuses=new returns empty.
	if dateFrom == nil && dateTo == nil && !allStatusesActive(statuses) {
		// Get current time in UTC+7 (Thailand timezone)
		utc := time.Now().UTC()
		utc7 := utc.Add(7 * time.Hour)

		// Get date components in UTC+7
		year, month, day := utc7.Date()

		// Start of day: 00:00 UTC+7 converted to UTC
		// 00:00 UTC+7 = 17:00 previous day UTC
		dateStartUTC7 := time.Date(year, month, day, 0, 0, 0, 0, time.FixedZone("UTC+7", 7*3600))
		dateStartUTC := dateStartUTC7.UTC()

		// End of day: start of next day in UTC+7, converted to UTC
		// This gives us 00:00 next day UTC+7 = 17:00 same day UTC (exclusive comparison)
		dateEndUTC7 := time.Date(year, month, day, 0, 0, 0, 0, time.FixedZone("UTC+7", 7*3600)).Add(24 * time.Hour)
		dateEndUTC := dateEndUTC7.UTC()

		dateFrom = &dateStartUTC
		dateTo = &dateEndUTC
	}

	var memberID *string
	if memberIDStr := strings.TrimSpace(c.Query("memberId")); memberIDStr != "" {
		memberID = &memberIDStr
	}

	scope := strings.ToLower(strings.TrimSpace(c.DefaultQuery("scope", "pos")))
	var branchFilter *string
	var posFilter *string
	switch scope {
	case "all":
		if !canReadAllOperationalData(c) {
			c.JSON(http.StatusForbidden, gin.H{
				"error":   "scope_access_denied",
				"message": "scope=all is restricted to administrators",
			})
			return
		}
	case "branch":
		if isPOSRole(currentRequestUser(c)) {
			c.JSON(http.StatusForbidden, gin.H{"error": "scope_access_denied", "message": "POS operators are restricted to scope=pos"})
			return
		}
		branchFilter = &branchID
	case "pos", "":
		branchFilter = &branchID
		posFilter = &posID
	default:
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "invalid_scope",
			"message": "scope must be 'pos', 'branch', or 'all'",
		})
		return
	}

	includeDetails := parseBoolQuery(c.Query("includeDetails"))

	bills, err := h.bills.List(
		c.Request.Context(),
		limit,
		offset,
		dateFrom,
		dateTo,
		memberID,
		branchFilter,
		posFilter,
		statuses,
	)
	if err != nil {
		log.Printf("Error listing bills: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "failed_to_list_bills",
			"message": err.Error(),
		})
		return
	}

	// Enrich the list without N+1: batch-load members and (optionally) details
	// for the whole page in a couple of queries instead of per bill.
	memberByID := h.batchMembers(c.Request.Context(), bills)
	// Resolve creator/updater ids → display names (e.g. "Administrator").
	creatorIDs := make([]string, 0, len(bills)*2)
	for _, b := range bills {
		creatorIDs = append(creatorIDs, b.CreatedBy, b.UpdatedBy)
	}
	userNames := h.resolveUserNames(c.Request.Context(), creatorIDs...)
	var detailsByBill map[string][]repository.BillDetail
	var discountsByBill map[string][]repository.BillDiscountDetail
	if includeDetails {
		billIDs := make([]string, 0, len(bills))
		for _, b := range bills {
			billIDs = append(billIDs, b.ID)
		}
		var dErr, gErr error
		detailsByBill, dErr = h.bills.GetDetailsByBillIDs(c.Request.Context(), billIDs)
		discountsByBill, gErr = h.bills.GetDiscountsByBillIDs(c.Request.Context(), billIDs)
		if dErr != nil || gErr != nil {
			err := dErr
			if err == nil {
				err = gErr
			}
			log.Printf("Error loading bill details for list: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{
				"error":   "failed_to_get_bill_details",
				"message": err.Error(),
			})
			return
		}
	}

	out := make([]gin.H, 0, len(bills))
	for _, b := range bills {
		memberObj := memberByID[b.MemberID]
		var detailOut []gin.H
		var discountOut []gin.H
		itemCount := 0
		totalQty := 0

		if includeDetails {
			details := detailsByBill[b.ID]
			discounts := discountsByBill[b.ID]
			detailOut = buildBillDetailOutput(details)
			discountOut = buildBillDiscountOutput(discounts)
			itemCount, totalQty = buildBillItemSummary(details)
		}

		billOut := gin.H{
			"id":             b.ID,
			"branchId":       b.BranchID,
			"posId":          b.POSID,
			"status":         b.Status,
			"memberId":       b.MemberID,
			"member":         memberObj,
			"customerName":   b.CustomerName,
			"purchaseAmount": b.PurchaseAmount,
			"totalDiscount":  b.TotalDiscount,
			"amountAfterDiscount": maxFloat64(
				b.PurchaseAmount-b.TotalDiscount,
				0,
			),
			"totalAmount":   b.TotalAmount,
			"vatAmount":     b.VATAmount,
			"xvatAmount":    b.XVATAmount,
			"dateTime":      b.CreatedAt.Format(time.RFC3339),
			"createdAt":     b.CreatedAt.Format(time.RFC3339),
			"updatedAt":     b.UpdatedAt.Format(time.RFC3339),
			"createdBy":     b.CreatedBy,
			"updatedBy":     b.UpdatedBy,
			"createdByName": userDisplayName(userNames, b.CreatedBy),
			"updatedByName": userDisplayName(userNames, b.UpdatedBy),
			"itemCount":     itemCount,
			"totalQty":      totalQty,
		}
		if includeDetails {
			billOut["details"] = detailOut
			billOut["items"] = detailOut
			billOut["discounts"] = discountOut
		}
		attachPaymentOutput(billOut, b.PaymentMethod, b.PaymentRef)
		out = append(out, billOut)
	}

	c.JSON(http.StatusOK, gin.H{
		"bills": out,
	})
}

// Get returns a full bill with its details and discounts.
// For users with branchId/posId: validates bill belongs to their branch/POS
// For admin users without branchId/posId: allows viewing any bill
// Response format:
//
//	{
//	  ...bill_master_fields,
//	  "details":   [ { ...bill_item_detail } ],
//	  "discounts": [ { ...bill_discount_detail } ]
//	}
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

	// Only validate branch/POS access if user has branchId/posId in session
	// Admin users without POS session can view any bill
	if !canReadOperationalRecord(c, b.BranchID, b.POSID) {
		c.JSON(http.StatusForbidden, gin.H{
			"error":   "bill_access_denied",
			"message": "Bill does not belong to your permitted scope",
		})
		return
	}

	detailOut := buildBillDetailOutput(details)
	discountOut := buildBillDiscountOutput(discounts)
	itemCount, totalQty := buildBillItemSummary(details)
	userNames := h.resolveUserNames(c.Request.Context(), b.CreatedBy, b.UpdatedBy)

	response := gin.H{
		"id":             b.ID,
		"branchId":       b.BranchID,
		"posId":          b.POSID,
		"status":         b.Status,
		"memberId":       b.MemberID,
		"member":         h.buildMemberOutput(c.Request.Context(), b.MemberID),
		"customerName":   b.CustomerName,
		"purchaseAmount": b.PurchaseAmount,
		"totalDiscount":  b.TotalDiscount,
		"amountAfterDiscount": maxFloat64(
			b.PurchaseAmount-b.TotalDiscount,
			0,
		),
		"memberDiscount": b.MemberDiscount,
		"manualDiscount": maxFloat64(b.TotalDiscount-b.MemberDiscount, 0),
		"roundingAmount": b.RoundingAmount,
		"totalAmount":    b.TotalAmount,
		"cashReceived":   b.CashReceived,
		"changeAmount":   b.ChangeAmount,
		"vatAmount":      b.VATAmount,
		"xvatAmount":     b.XVATAmount,
		"dateTime":       b.CreatedAt.Format(time.RFC3339),
		"createdAt":      b.CreatedAt.Format(time.RFC3339),
		"updatedAt":      b.UpdatedAt.Format(time.RFC3339),
		"createdBy":      b.CreatedBy,
		"updatedBy":      b.UpdatedBy,
		"createdByName":  userDisplayName(userNames, b.CreatedBy),
		"updatedByName":  userDisplayName(userNames, b.UpdatedBy),
		"itemCount":      itemCount,
		"totalQty":       totalQty,
		"details":        detailOut,
		"items":          detailOut,
		"discounts":      discountOut,
	}
	attachPaymentOutput(response, b.PaymentMethod, b.PaymentRef)
	c.JSON(http.StatusOK, response)
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

	ctx := c.Request.Context()
	stepStart := time.Now()
	bill, err := h.bills.GetByID(ctx, id)
	logSlowTiming("bills.add_by_barcode.bill_lookup", stepStart, "bill_id", id, "ok", err == nil)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "bill_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_bill"})
		return
	}
	if bill.BranchID != branchID || bill.POSID != posID {
		c.JSON(http.StatusForbidden, gin.H{
			"error":   "bill_access_denied",
			"message": "Bill does not belong to your current branch and POS",
		})
		return
	}
	if bill.Status != "new" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "invalid_bill_status",
			"message": fmt.Sprintf("Bill status must be 'new' to add items. current status: %s", bill.Status),
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

	ctx = c.Request.Context()

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
	vehicleStoreID, err := h.getVehicleStoreID(ctx, posID)
	if err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "pos_store_not_configured"})
		return
	}
	if selectedAddress.StoreID != vehicleStoreID {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_address_code", "message": "Part must be sold from this POS vehicle store"})
		return
	}

	// Check and reduce inventory before adding to bill
	decreased, err := h.addresses.DecreaseInventory(ctx, req.AddressCode, req.Qty)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_check_inventory"})
		return
	}
	if !decreased {
		h.insufficientInventory(c, req.AddressCode, req.Qty)
		return
	}

	// Check if item already exists in bill
	existingItem, err := h.bills.GetItemByPartCode(ctx, id, req.PartCode, req.AddressCode)
	if err != nil && !repository.IsNotFoundError(err) {
		h.restoreInventoryAfterFailedAdd(ctx, req.AddressCode, req.Qty)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_check_existing_item"})
		return
	}

	// Get user for updated_by
	userVal, _ := c.Get("user")
	user, _ := userVal.(*repository.User)

	hadExisting := existingItem != nil
	previousQty := 0
	if existingItem != nil {
		previousQty = existingItem.Qty
		// Update quantity (add to existing)
		newQty := existingItem.Qty + req.Qty
		if err := h.bills.UpdateItemQty(ctx, id, req.PartCode, req.AddressCode, newQty); err != nil {
			h.restoreInventoryAfterFailedAdd(ctx, req.AddressCode, req.Qty)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_update_item"})
			return
		}
	} else {
		// Insert new item
		detail := &repository.BillDetail{
			BillID:      id,
			PartCode:    req.PartCode,
			AddressCode: req.AddressCode,
			UnitID:      partDetail.UnitID,
			UnitLabel:   partDetail.UnitLabel,
			UnitLabelTH: partDetail.UnitLabelTH,
			Name:        firstNonEmpty(partDetail.NameTH, partDetail.Name),
			ReceiptName: receiptname.SafeProductName(receiptname.Product{
				Code:        partDetail.Code,
				ReceiptName: partDetail.ReceiptName,
				Name:        partDetail.Name,
				NameTH:      partDetail.NameTH,
			}),
			Cost:  partDetail.Cost,
			Price: partDetail.Price,
			Qty:   req.Qty,
		}
		if err := h.bills.AddItem(ctx, detail); err != nil {
			h.restoreInventoryAfterFailedAdd(ctx, req.AddressCode, req.Qty)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_add_item"})
			return
		}
	}

	// Recalculate bill amounts
	if err := h.recalculateBillAmounts(ctx, id); err != nil {
		log.Printf("Error: failed to recalculate bill amounts after add-item: %v", err)
		h.rollbackAddedBillItem(ctx, id, req.PartCode, req.AddressCode, req.Qty, hadExisting, previousQty)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_recalculate_bill"})
		return
	}

	// Update bill updated_at and updated_by
	if err := h.bills.UpdateTimestamp(ctx, id, user.ID); err != nil {
		// Log error but don't fail the request
		log.Printf("Warning: failed to update bill timestamp: %v", err)
	}

	h.respondWithFullBill(c, id)
}

// AddItemByBarcode adds an item to a bill by barcode
func (h *BillsHandler) AddItemByBarcode(c *gin.Context) {
	handlerStart := time.Now()
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

	ctx := c.Request.Context()
	stepStart := time.Now()
	bill, err := h.bills.GetByID(ctx, id)
	logSlowTiming("bills.add_by_barcode.bill_lookup", stepStart, "bill_id", id, "ok", err == nil)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "bill_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_bill"})
		return
	}
	if bill.BranchID != branchID || bill.POSID != posID {
		c.JSON(http.StatusForbidden, gin.H{
			"error":   "bill_access_denied",
			"message": "Bill does not belong to your current branch and POS",
		})
		return
	}
	if bill.Status != "new" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "invalid_bill_status",
			"message": fmt.Sprintf("Bill status must be 'new' to add items. current status: %s", bill.Status),
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

	// Get part by barcode (filtered by branch)
	stepStart = time.Now()
	partDetail, addresses, err := h.parts.GetPartByBarcode(ctx, req.Barcode, branchID)
	logSlowTiming("bills.add_by_barcode.part_lookup", stepStart, "bill_id", id, "barcode", req.Barcode, "ok", err == nil)
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

	vehicleStoreID, err := h.getVehicleStoreID(ctx, posID)
	if err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "pos_store_not_configured"})
		return
	}
	stepStart = time.Now()
	selectedAddress, hasSalesAddress := salesAddressForPOS(addresses, vehicleStoreID)
	logSlowTiming("bills.add_by_barcode.address_select", stepStart, "bill_id", id, "vehicle_store_id", vehicleStoreID, "ok", hasSalesAddress)
	if !hasSalesAddress {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "no_vehicle_stock",
			"message": "Part does not exist in this POS vehicle store.",
		})
		return
	}

	// Check and reduce inventory before adding to bill
	stepStart = time.Now()
	decreased, err := h.addresses.DecreaseInventory(ctx, selectedAddress.Code, req.Qty)
	logSlowTiming("bills.add_by_barcode.inventory_decrease", stepStart, "bill_id", id, "address_code", selectedAddress.Code, "ok", err == nil && decreased)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_check_inventory"})
		return
	}
	if !decreased {
		h.insufficientInventory(c, selectedAddress.Code, req.Qty)
		return
	}

	// Get user for updated_by
	userVal, _ := c.Get("user")
	user, _ := userVal.(*repository.User)

	detail := &repository.BillDetail{
		BillID:      id,
		PartCode:    partDetail.Code,
		AddressCode: selectedAddress.Code,
		UnitID:      partDetail.UnitID,
		UnitLabel:   partDetail.UnitLabel,
		UnitLabelTH: partDetail.UnitLabelTH,
		Name:        firstNonEmpty(partDetail.NameTH, partDetail.Name),
		ReceiptName: receiptname.SafeProductName(receiptname.Product{
			Code:        partDetail.Code,
			ReceiptName: partDetail.ReceiptName,
			Name:        partDetail.Name,
			NameTH:      partDetail.NameTH,
		}),
		Cost:  partDetail.Cost,
		Price: partDetail.Price,
		Qty:   req.Qty,
	}
	stepStart = time.Now()
	previousQty, _, err := h.bills.AddItemReturningQty(ctx, detail)
	logSlowTiming("bills.add_by_barcode.item_upsert", stepStart, "bill_id", id, "part_code", partDetail.Code, "had_existing", previousQty > 0, "ok", err == nil)
	if err != nil {
		h.restoreInventoryAfterFailedAdd(ctx, selectedAddress.Code, req.Qty)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_add_item"})
		return
	}

	// Recalculate bill amounts and touch updated_at in one database round trip.
	stepStart = time.Now()
	if err := h.bills.RecalculateAmountsAndTimestamp(ctx, id, user.ID); err != nil {
		logSlowTiming("bills.add_by_barcode.recalculate_touch", stepStart, "bill_id", id, "ok", false)
		log.Printf("Error: failed to recalculate bill amounts after add-item-by-barcode: %v", err)
		h.rollbackAddedBillItem(ctx, id, partDetail.Code, selectedAddress.Code, req.Qty, previousQty > 0, previousQty)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_recalculate_bill"})
		return
	}
	logSlowTiming("bills.add_by_barcode.recalculate_touch", stepStart, "bill_id", id, "ok", true)

	defer logSlowTiming("bills.add_by_barcode.total", handlerStart, "bill_id", id, "barcode", req.Barcode)
	h.respondWithFullBill(c, id)
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
			"error":   "bill_access_denied",
			"message": "Bill does not belong to your current branch and POS",
		})
		return
	}

	// Validate bill status is "new"
	ctx := c.Request.Context()
	if err := h.validateBillStatusNew(ctx, id); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "invalid_bill_status",
			"message": fmt.Sprintf("Bill status must be 'new' to remove items. %s", err.Error()),
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

	ctx = c.Request.Context()

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

	// Calculate quantity to return to inventory
	returnQty := existingItem.Qty
	if !req.IsRemoveAll && existingItem.Qty > removeQty {
		returnQty = removeQty
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

	// Return inventory to address
	if err := h.addresses.IncreaseInventory(ctx, req.AddressCode, returnQty); err != nil {
		// Log error but don't fail the request (inventory return is important but shouldn't block removal)
		log.Printf("Warning: failed to return inventory to address %s: %v", req.AddressCode, err)
	}

	// Recalculate bill amounts
	if err := h.recalculateBillAmounts(ctx, id); err != nil {
		log.Printf("Warning: failed to recalculate bill amounts: %v", err)
	}

	// Update bill updated_at and updated_by
	if err := h.bills.UpdateTimestamp(ctx, id, user.ID); err != nil {
		log.Printf("Warning: failed to update bill timestamp: %v", err)
	}

	h.respondWithFullBill(c, id)
}

// UpdateItemPrice updates the line total price of an item in a bill.
// Validation rule: the edited line total must not be lower than 90% of
// the catalog line total (catalog unit price * qty currently in bill).
func (h *BillsHandler) UpdateItemPrice(c *gin.Context) {
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

	if err := h.validateBillAccess(c.Request.Context(), id, branchID, posID); err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "bill_not_found"})
			return
		}
		c.JSON(http.StatusForbidden, gin.H{
			"error":   "bill_access_denied",
			"message": "Bill does not belong to your current branch and POS",
		})
		return
	}

	ctx := c.Request.Context()
	if err := h.validateBillStatusNew(ctx, id); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "invalid_bill_status",
			"message": fmt.Sprintf("Bill status must be 'new' to update item price. %s", err.Error()),
		})
		return
	}

	var req struct {
		PartCode    string  `json:"partCode" binding:"required"`
		AddressCode string  `json:"addressCode" binding:"required"`
		LineTotal   float64 `json:"lineTotal" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": err.Error()})
		return
	}

	existingItem, err := h.bills.GetItemByPartCode(ctx, id, req.PartCode, req.AddressCode)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "item_not_found", "message": "Item does not exist in this bill"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_item"})
		return
	}

	if existingItem.Qty <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_item_qty"})
		return
	}
	if req.LineTotal <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "invalid_line_total",
			"message": "Line total must be greater than zero",
		})
		return
	}

	// The part still has to exist and belong to this branch, even though its
	// catalog prices no longer constrain what it sells for.
	if _, _, err := h.parts.GetPartDetail(ctx, req.PartCode, &branchID); err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "part_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_part"})
		return
	}

	// The cashier sets the price. See pricing_validation.go for why there is
	// no floor or ceiling here.
	newUnitPrice := req.LineTotal / float64(existingItem.Qty)
	if err := h.bills.UpdateItemPrice(ctx, id, req.PartCode, req.AddressCode, newUnitPrice); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_update_item_price"})
		return
	}

	if err := h.recalculateBillAmounts(ctx, id); err != nil {
		log.Printf("Warning: failed to recalculate bill amounts: %v", err)
	}

	userVal, _ := c.Get("user")
	user, _ := userVal.(*repository.User)
	if err := h.bills.UpdateTimestamp(ctx, id, user.ID); err != nil {
		log.Printf("Warning: failed to update bill timestamp: %v", err)
	}

	h.respondWithFullBill(c, id)
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

func (h *BillsHandler) minimumAllowedBillTotal(ctx context.Context, items []repository.BillDetail, branchID string) (float64, error) {
	minimum := 0.0
	for _, item := range items {
		part, _, err := h.parts.GetPartDetail(ctx, item.PartCode, &branchID)
		if err != nil {
			return 0, err
		}
		minimum += part.MinPrice * float64(item.Qty)
	}
	return minimum, nil
}

func discountValue(purchaseAmount float64, discount repository.BillDiscountDetail) float64 {
	if discount.Unit == "THB" {
		return discount.Amount
	}
	if discount.Unit == "percentage" {
		return purchaseAmount * (discount.Amount / 100.0)
	}
	return 0
}

func (h *BillsHandler) validateDiscountFloor(
	ctx context.Context,
	billID, branchID string,
	candidate *repository.BillDiscountDetail,
) (float64, error) {
	items, err := h.bills.GetAllItems(ctx, billID)
	if err != nil {
		return 0, err
	}
	purchaseAmount := 0.0
	for _, item := range items {
		purchaseAmount += item.Price * float64(item.Qty)
	}
	minimum, err := h.minimumAllowedBillTotal(ctx, items, branchID)
	if err != nil {
		return 0, err
	}
	discounts, err := h.bills.GetAllDiscounts(ctx, billID)
	if err != nil {
		return 0, err
	}
	totalDiscount := 0.0
	for _, discount := range discounts {
		if candidate != nil && discount.PromotionCode == candidate.PromotionCode {
			continue
		}
		totalDiscount += discountValue(purchaseAmount, discount)
	}
	if candidate != nil {
		totalDiscount += discountValue(purchaseAmount, *candidate)
	}
	if purchaseAmount-totalDiscount+0.0001 < minimum {
		return minimum, fmt.Errorf("discount_below_minimum")
	}
	return minimum, nil
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
			"error":   "bill_access_denied",
			"message": "Bill does not belong to your current branch and POS",
		})
		return
	}

	// Validate bill status is "new"
	ctx := c.Request.Context()
	if err := h.validateBillStatusNew(ctx, id); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "invalid_bill_status",
			"message": fmt.Sprintf("Bill status must be 'new' to modify discounts. %s", err.Error()),
		})
		return
	}

	var req struct {
		PromotionCode string   `json:"promotionCode"`
		Unit          string   `json:"unit"`
		Amount        *float64 `json:"amount"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": err.Error()})
		return
	}

	ctx = c.Request.Context()

	req.PromotionCode = strings.TrimSpace(req.PromotionCode)

	var discount *repository.BillDiscountDetail
	if req.PromotionCode != "" {
		promotion, err := h.promotions.GetByCode(ctx, req.PromotionCode)
		if err != nil {
			if repository.IsNotFoundError(err) {
				c.JSON(http.StatusNotFound, gin.H{"error": "promotion_not_found"})
				return
			}
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_promotion"})
			return
		}
		discount = &repository.BillDiscountDetail{
			BillID:        id,
			PromotionCode: promotion.Code,
			Unit:          promotion.Unit,
			Amount:        promotion.Amount,
		}
	} else {
		unit, ok := normalizeDiscountUnit(req.Unit)
		if !ok || req.Amount == nil {
			c.JSON(http.StatusBadRequest, gin.H{
				"error":   "invalid_request",
				"message": "Either promotionCode or unit+amount is required",
			})
			return
		}
		if *req.Amount <= 0 {
			c.JSON(http.StatusBadRequest, gin.H{
				"error":   "invalid_discount_amount",
				"message": "Discount amount must be greater than zero",
			})
			return
		}
		if err := h.ensureManualDiscountPromotion(ctx); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_prepare_manual_discount"})
			return
		}
		discount = &repository.BillDiscountDetail{
			BillID:        id,
			PromotionCode: manualDiscountPromotionCode,
			Unit:          unit,
			Amount:        *req.Amount,
		}
	}

	// A bill-level discount is not floored either — same reason as the line
	// price. The discount is still clamped to the bill total by the client, so
	// a bill cannot go negative.
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

	h.respondWithFullBill(c, id)
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
			"error":   "bill_access_denied",
			"message": "Bill does not belong to your current branch and POS",
		})
		return
	}

	// Validate bill status is "new"
	ctx := c.Request.Context()
	if err := h.validateBillStatusNew(ctx, id); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "invalid_bill_status",
			"message": fmt.Sprintf("Bill status must be 'new' to modify discounts. %s", err.Error()),
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

	h.respondWithFullBill(c, id)
}

// AddMemberByPhone assigns a member to a bill by member phone number.
func (h *BillsHandler) AddMemberByPhone(c *gin.Context) {
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

	if err := h.validateBillAccess(c.Request.Context(), id, branchID, posID); err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "bill_not_found"})
			return
		}
		c.JSON(http.StatusForbidden, gin.H{
			"error":   "bill_access_denied",
			"message": "Bill does not belong to your current branch and POS",
		})
		return
	}

	ctx := c.Request.Context()
	if err := h.validateBillStatusNew(ctx, id); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "invalid_bill_status",
			"message": fmt.Sprintf("Bill status must be 'new' to add member. %s", err.Error()),
		})
		return
	}

	var req struct {
		Phone string `json:"phone" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": err.Error()})
		return
	}

	member, err := h.members.GetByPhone(ctx, req.Phone)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "member_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_member"})
		return
	}

	if err := h.bills.UpdateMember(ctx, id, member.ID, user.ID); err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "bill_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_add_member"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Member added successfully",
		"billId":  id,
		"member": gin.H{
			"id":    member.ID,
			"code":  member.Code,
			"name":  member.Name,
			"phone": member.Phone,
		},
	})
}

// RemoveMember clears the member assignment from a bill.
func (h *BillsHandler) RemoveMember(c *gin.Context) {
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

	if err := h.validateBillAccess(c.Request.Context(), id, branchID, posID); err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "bill_not_found"})
			return
		}
		c.JSON(http.StatusForbidden, gin.H{
			"error":   "bill_access_denied",
			"message": "Bill does not belong to your current branch and POS",
		})
		return
	}

	ctx := c.Request.Context()
	if err := h.validateBillStatusNew(ctx, id); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "invalid_bill_status",
			"message": fmt.Sprintf("Bill status must be 'new' to remove member. %s", err.Error()),
		})
		return
	}

	if err := h.bills.RemoveMember(ctx, id, user.ID); err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "bill_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_remove_member"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Member removed successfully",
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
			"error":   "bill_access_denied",
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
			"error":         "invalid_bill_status",
			"message":       "Only bills with status 'new' can be held",
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
				if rollbackErr := h.bills.UpdateStatus(ctx, heldBillID, "new", user.ID); rollbackErr != nil {
					log.Printf("critical: failed to rollback bill status for ID %s: %v", heldBillID, rollbackErr)
				}
			}
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_generate_bill_id"})
			return
		}

		now := time.Now().UTC()

		// Create new bill (using branchId and posId from session)
		bill := &repository.Bill{
			ID:             billID,
			BranchID:       branchID,
			POSID:          posID,
			Status:         "new",
			PaymentMethod:  "",
			PaymentRef:     "",
			MemberID:       "",
			CustomerName:   "ทั่วไป",
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
				if rollbackErr := h.bills.UpdateStatus(ctx, heldBillID, "new", user.ID); rollbackErr != nil {
					log.Printf("critical: failed to rollback bill status for ID %s: %v", heldBillID, rollbackErr)
				}
			}
			c.JSON(http.StatusInternalServerError, gin.H{
				"error":   "failed_to_create_bill",
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
				"receiptName": d.ReceiptName,
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
			"customerName":   newBill.CustomerName,
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
				"receiptName": d.ReceiptName,
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
			"customerName":   bill.CustomerName,
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
			"error":         "invalid_target_bill_status",
			"message":       "Target bill must have status 'hold' or 'new'",
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

	var heldBillID string
	if err == nil && currentBill != nil {
		if err := h.bills.UpdateStatus(ctx, currentBill.ID, "hold", user.ID); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_hold_current_bill"})
			return
		}
		heldBillID = currentBill.ID
	}

	// Resume target bill
	if err := h.bills.UpdateStatus(ctx, req.TargetBillID, "new", user.ID); err != nil {
		// Rollback: resume the held bill if we just held it
		if heldBillID != "" {
			if rollbackErr := h.bills.UpdateStatus(ctx, heldBillID, "new", user.ID); rollbackErr != nil {
				log.Printf("critical: failed to resume held bill ID %s during rollback: %v", heldBillID, rollbackErr)
			}
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
			"receiptName": d.ReceiptName,
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
		"customerName":   resumedBill.CustomerName,
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

// Cancel cancels a bill
func (h *BillsHandler) Cancel(c *gin.Context) {
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
	ctx := c.Request.Context()
	if err := h.validateBillAccess(ctx, id, branchID, posID); err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "bill_not_found"})
			return
		}
		c.JSON(http.StatusForbidden, gin.H{
			"error":   "bill_access_denied",
			"message": "Bill does not belong to your current branch and POS",
		})
		return
	}

	// Get bill to check current status
	bill, err := h.bills.GetByID(ctx, id)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "bill_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_bill"})
		return
	}

	// Validate bill status is "new" or "hold" (can't cancel completed bills)
	if bill.Status != "new" && bill.Status != "hold" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "invalid_bill_status",
			"message": fmt.Sprintf("Can only cancel bills with status 'new' or 'hold'. Current status: '%s'", bill.Status),
		})
		return
	}

	// Get user for updated_by
	userVal, _ := c.Get("user")
	user, _ := userVal.(*repository.User)

	// Get all items before cancelling to return inventory
	items, err := h.bills.GetAllItems(ctx, id)
	if err != nil {
		// Log error but continue with cancellation
		log.Printf("Warning: failed to get items for inventory return: %v", err)
	} else {
		// Return inventory for each item
		for _, item := range items {
			if err := h.addresses.IncreaseInventory(ctx, item.AddressCode, item.Qty); err != nil {
				// Log error but continue with other items
				log.Printf("Warning: failed to return inventory for address %s: %v", item.AddressCode, err)
			}
		}
	}

	// Update status to "cancelled"
	if err := h.bills.UpdateStatus(ctx, id, "cancelled", user.ID); err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "bill_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_cancel_bill"})
		return
	}

	// Get updated bill with full details
	updatedBill, details, discounts, err := h.bills.GetFullByID(ctx, id)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "bill_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_bill"})
		return
	}

	// Format response
	detailOut := make([]gin.H, 0, len(details))
	for _, d := range details {
		detailOut = append(detailOut, gin.H{
			"partCode":    d.PartCode,
			"addressCode": d.AddressCode,
			"unit": gin.H{
				"id":      d.UnitID,
				"label":   d.UnitLabel,
				"labelTh": d.UnitLabelTH,
			},
			"name":        d.Name,
			"receiptName": d.ReceiptName,
			"cost":        d.Cost,
			"price":       d.Price,
			"qty":         d.Qty,
		})
	}

	discountOut := make([]gin.H, 0, len(discounts))
	for _, d := range discounts {
		discountOut = append(discountOut, gin.H{
			"promotionCode": d.PromotionCode,
			"unit":          d.Unit,
			"amount":        d.Amount,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"billId":         updatedBill.ID,
		"branchId":       updatedBill.BranchID,
		"posId":          updatedBill.POSID,
		"status":         updatedBill.Status,
		"paymentMethod":  updatedBill.PaymentMethod,
		"paymentRef":     updatedBill.PaymentRef,
		"memberId":       updatedBill.MemberID,
		"customerName":   updatedBill.CustomerName,
		"purchaseAmount": updatedBill.PurchaseAmount,
		"totalDiscount":  updatedBill.TotalDiscount,
		"totalAmount":    updatedBill.TotalAmount,
		"vatAmount":      updatedBill.VATAmount,
		"xvatAmount":     updatedBill.XVATAmount,
		"createdAt":      updatedBill.CreatedAt.Format(time.RFC3339),
		"updatedAt":      updatedBill.UpdatedAt.Format(time.RFC3339),
		"createdBy":      updatedBill.CreatedBy,
		"updatedBy":      updatedBill.UpdatedBy,
		"details":        detailOut,
		"discounts":      discountOut,
	})
}

// Delete permanently deletes a bill
func (h *BillsHandler) Delete(c *gin.Context) {
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
	ctx := c.Request.Context()
	if err := h.validateBillAccess(ctx, id, branchID, posID); err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "bill_not_found"})
			return
		}
		c.JSON(http.StatusForbidden, gin.H{
			"error":   "bill_access_denied",
			"message": "Bill does not belong to your current branch and POS",
		})
		return
	}

	// Get bill to check status
	bill, err := h.bills.GetByID(ctx, id)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "bill_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_bill"})
		return
	}

	// Prevent deletion of completed bills
	if bill.Status == "completed" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "cannot_delete_completed_bill",
			"message": "Cannot delete bills with status 'completed'. Completed bills must be kept for records.",
		})
		return
	}

	// Get all items to return inventory before deletion
	items, err := h.bills.GetAllItems(ctx, id)
	if err != nil {
		// Log error but continue with deletion
		log.Printf("Warning: failed to get items for inventory return: %v", err)
	} else {
		// Return inventory for each item
		for _, item := range items {
			if err := h.addresses.IncreaseInventory(ctx, item.AddressCode, item.Qty); err != nil {
				// Log error but continue with other items
				log.Printf("Warning: failed to return inventory for address %s: %v", item.AddressCode, err)
			}
		}
	}

	// Delete bill (cascade deletes related records)
	if err := h.bills.Delete(ctx, id); err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "bill_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_delete_bill"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "bill_deleted",
		"billId":  id,
	})
}

// Payment processes payment for a bill
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
	ctx := c.Request.Context()
	if err := h.validateBillAccess(ctx, id, branchID, posID); err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "bill_not_found"})
			return
		}
		c.JSON(http.StatusForbidden, gin.H{
			"error":   "bill_access_denied",
			"message": "Bill does not belong to your current branch and POS",
		})
		return
	}

	// Validate bill status is "new"
	if err := h.validateBillStatusNew(ctx, id); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "invalid_bill_status",
			"message": fmt.Sprintf("Bill status must be 'new' to process payment. %s", err.Error()),
		})
		return
	}

	var req struct {
		PaymentMethod string `json:"paymentMethod"`
		PaymentRef    string `json:"paymentRef"`
		PaymentMeta   any    `json:"paymentMeta"`
		// What the customer handed over, for a cash sale. Optional: a till
		// that does not count it out still completes the sale.
		CashReceived *float64 `json:"cashReceived"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": err.Error()})
		return
	}

	billBeforePayment, err := h.bills.GetByID(ctx, id)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "bill_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_bill"})
		return
	}

	items, err := h.bills.GetAllItems(ctx, id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_bill_items"})
		return
	}
	if len(items) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "empty_bill",
			"message": "Bill must have at least one item before payment",
		})
		return
	}
	normalizedMethod, normalizedRef, err := validateAndSerializePayment(
		req.PaymentMethod,
		req.PaymentRef,
		req.PaymentMeta,
		billBeforePayment.TotalAmount,
	)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "invalid_payment_payload",
			"message": err.Error(),
		})
		return
	}

	// Get user for updated_by
	userVal, _ := c.Get("user")
	user, _ := userVal.(*repository.User)

	// Change is derived here rather than trusted from the client: it is the
	// number the customer counts, and the till it has to reconcile against.
	var cash *repository.CashTendered
	if normalizedMethod == "cash" && req.CashReceived != nil {
		received := *req.CashReceived
		if received+0.0001 < billBeforePayment.TotalAmount {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "cash_below_total",
				"message": fmt.Sprintf("รับเงินมา %.2f น้อยกว่ายอดที่ต้องชำระ %.2f",
					received, billBeforePayment.TotalAmount),
			})
			return
		}
		cash = &repository.CashTendered{
			Received: received,
			Change:   received - billBeforePayment.TotalAmount,
		}
	}

	// Update payment info and set status to "completed"
	if err := h.bills.UpdatePayment(ctx, id, normalizedMethod, normalizedRef, user.ID, cash); err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "bill_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_process_payment"})
		return
	}

	h.respondWithFullBill(c, id)
}

// PrintReceipt sends the receipt for completed bill :id straight to the
// configured 80mm thermal printer via raw ESC-POS. The checkout flow calls this
// after payment succeeds. idempotencyKey suppresses duplicate browser clicks.
func (h *BillsHandler) PrintReceipt(c *gin.Context) {
	id := c.Param("id")
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_bill_id"})
		return
	}

	var req struct {
		IdempotencyKey string `json:"idempotencyKey"`
	}
	if c.Request.ContentLength > 0 {
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": err.Error()})
			return
		}
	}

	if !h.beginPrint(req.IdempotencyKey) {
		c.JSON(http.StatusOK, gin.H{
			"ok":        true,
			"printed":   false,
			"duplicate": true,
			"billId":    id,
			"target":    h.PrinterTarget,
			"mode":      printer.NormalizePrintMode(h.PrinterMode),
		})
		return
	}

	if !h.PrinterEnabled {
		h.completePrint(req.IdempotencyKey, false)
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"error":   "printer_disabled",
			"message": "set RECEIPT_PRINTER_ENABLED=true in .env",
		})
		return
	}

	if strings.TrimSpace(h.PrinterTarget) == "" {
		h.completePrint(req.IdempotencyKey, false)
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"error":   "printer_not_configured",
			"message": "set RECEIPT_PRINTER_PORT=LPT1 in .env",
		})
		return
	}

	ctx := c.Request.Context()

	branchID, posID, err := h.getBranchAndPOSFromContext(c)
	if err != nil {
		h.completePrint(req.IdempotencyKey, false)
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	bill, details, discounts, err := h.bills.GetFullByID(ctx, id)
	if err != nil {
		h.completePrint(req.IdempotencyKey, false)
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "bill_not_found"})
			return
		}
		log.Printf("PrintReceipt: GetFullByID failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_bill"})
		return
	}
	if bill.BranchID != branchID || bill.POSID != posID {
		h.completePrint(req.IdempotencyKey, false)
		c.JSON(http.StatusForbidden, gin.H{
			"error":   "bill_access_denied",
			"message": "Bill does not belong to your current branch and POS",
		})
		return
	}
	if bill.Status != "completed" {
		h.completePrint(req.IdempotencyKey, false)
		c.JSON(http.StatusBadRequest, gin.H{
			"error":         "bill_not_completed",
			"message":       "Receipt can only be printed after payment is completed.",
			"currentStatus": bill.Status,
		})
		return
	}

	company, err := h.company.Get(ctx)
	if err != nil {
		h.completePrint(req.IdempotencyKey, false)
		log.Printf("PrintReceipt: company.Get failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_company"})
		return
	}

	params := h.buildReceiptParams(bill, details, discounts, company)
	data := printer.BuildReceipt(params)

	if err := printer.PrintRaw(h.PrinterTarget, data); err != nil {
		h.completePrint(req.IdempotencyKey, false)
		log.Printf("PrintReceipt: printer.PrintRaw target=%q drawer=%t drawerCommand=%s failed: %v",
			h.PrinterTarget, h.OpenCashDrawer, printer.HexCommand(h.DrawerKick), err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "failed_to_print",
			"message": err.Error(),
			"target":  h.PrinterTarget,
		})
		return
	}

	drawerSent := false
	drawerMethod := ""
	drawerBinPath := ""
	drawerOutput := ""

	// In Windows POS production, the cash drawer must be opened explicitly by
	// sending the ESC/POS drawer kick command after the receipt is printed.
	// Some older builds populated DrawerKick from CASH_DRAWER_COMMAND but did not
	// correctly map CASH_DRAWER_ENABLED into OpenCashDrawer, causing logs like:
	// drawer=false drawerCommand=1B700019FA. Treat a configured DrawerKick command
	// as an explicit request to open the drawer for the real receipt print flow.
	drawerEnabled := h.OpenCashDrawer || len(h.DrawerKick) > 0
	if drawerEnabled {
		log.Printf("PrintReceipt: drawer enabled bill=%s openCashDrawer=%t drawerKickConfigured=%t target=%q command=%s",
			bill.ID, h.OpenCashDrawer, len(h.DrawerKick) > 0, h.PrinterTarget, printer.HexCommand(h.DrawerKick))
		result, err := printer.KickCashDrawer(h.PrinterTarget, h.DrawerKick)
		drawerMethod = result.Method
		drawerBinPath = result.BinPath
		drawerOutput = result.Output
		if err != nil {
			h.completePrint(req.IdempotencyKey, false)
			log.Printf("PrintReceipt: drawer kick target=%q command=%s method=%s binPath=%q failed after receipt print: %v",
				h.PrinterTarget, printer.HexCommand(h.DrawerKick), result.Method, result.BinPath, err)
			c.JSON(http.StatusInternalServerError, gin.H{
				"error":             "failed_to_open_drawer",
				"message":           err.Error(),
				"printed":           true,
				"drawerCommand":     printer.HexCommand(h.DrawerKick),
				"drawerCommandSent": false,
				"drawerMethod":      result.Method,
				"drawerBinPath":     result.BinPath,
				"drawerOutput":      result.Output,
				"target":            h.PrinterTarget,
				"bytes":             len(data),
				"retryWarning":      "Receipt was printed before the drawer error. Retrying may print another receipt.",
			})
			return
		}
		drawerSent = true
		log.Printf("PrintReceipt: drawer kick target=%q command=%s method=%s binPath=%q bytes=%d ok=true visualConfirmationRequired=true",
			result.Target, printer.HexCommand(h.DrawerKick), result.Method, result.BinPath, result.Bytes)
	}

	h.completePrint(req.IdempotencyKey, true)
	mode := printer.NormalizePrintMode(h.PrinterMode)
	log.Printf("PrintReceipt: bill=%s target=%q mode=%s bytes=%d drawer=%t drawerEnabled=%t openCashDrawer=%t drawerKickConfigured=%t drawerCommand=%s drawerMethod=%s",
		bill.ID, h.PrinterTarget, mode, len(data), drawerSent, drawerEnabled, h.OpenCashDrawer, len(h.DrawerKick) > 0, printer.HexCommand(h.DrawerKick), drawerMethod)
	c.JSON(http.StatusOK, gin.H{
		"ok":                    true,
		"printed":               true,
		"duplicate":             false,
		"billId":                bill.ID,
		"bytes":                 len(data),
		"target":                h.PrinterTarget,
		"mode":                  mode,
		"drawerCommand":         printer.HexCommand(h.DrawerKick),
		"drawerCommandSent":     drawerSent,
		"drawerEnabled":         drawerEnabled,
		"openCashDrawer":        h.OpenCashDrawer,
		"drawerKickConfigured":  len(h.DrawerKick) > 0,
		"drawerMethod":          drawerMethod,
		"drawerBinPath":         drawerBinPath,
		"drawerOutput":          drawerOutput,
		"drawerOpenedConfirmed": false,
	})
}

// PrintTestReceipt prints a synthetic receipt so operators can verify the
// physical printer, encoding mode, cutter, and drawer without creating a sale.
func (h *BillsHandler) PrintTestReceipt(c *gin.Context) {
	if !h.PrinterEnabled {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"error":   "printer_disabled",
			"message": "set RECEIPT_PRINTER_ENABLED=true in .env",
		})
		return
	}
	if strings.TrimSpace(h.PrinterTarget) == "" {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"error":   "printer_not_configured",
			"message": "set RECEIPT_PRINTER_PORT=LPT1 in .env",
		})
		return
	}

	now := time.Now()
	params := printer.ReceiptParams{
		CompanyNameTh: "POS Printer Test",
		CompanyAddrTh: "Windows 10 POS / LPT1",
		TaxID:         "0000000000000",
		Phone:         "TEST",
		ReceiptFooter: "Thai CP874 mode is enabled. If Thai is wrong, tune RECEIPT_CHARSET or use ascii fallback.",
		BillID:        "TEST-" + now.Format("20060102-150405"),
		CashierName:   "Printer Test",
		PaymentMethod: paymentLabelForMode("cash", h.PrinterMode),
		Items: []printer.ReceiptItem{
			{Code: "TEST001", Name: "Receipt test item", Qty: 1, UnitPrice: 10, LineTotal: 10},
			{Code: "TEST002", Name: "Second line item", Qty: 2, UnitPrice: 5, LineTotal: 10},
		},
		Subtotal:        20,
		Discount:        0,
		AmountAfterDisc: 20,
		TaxRatePercent:  7,
		Tax:             1.31,
		Total:           20,
		ReceivedAmount:  20,
		ChangeAmount:    0,
		HasReceived:     true,
		HasChange:       true,
		CodeTable:       h.PrinterCharset,
		PrintMode:       h.PrinterMode,
		OpenDrawer:      false,
		DrawerKick:      h.DrawerKick,
	}

	data := printer.BuildReceipt(params)
	if err := printer.PrintRaw(h.PrinterTarget, data); err != nil {
		log.Printf("PrintTestReceipt: printer.PrintRaw target=%q drawer=%t drawerCommand=%s failed: %v",
			h.PrinterTarget, h.OpenCashDrawer, printer.HexCommand(h.DrawerKick), err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "failed_to_print",
			"message": err.Error(),
			"target":  h.PrinterTarget,
		})
		return
	}

	drawerSent := false
	drawerMethod := ""
	drawerBinPath := ""
	drawerOutput := ""
	if h.OpenCashDrawer {
		result, err := printer.KickCashDrawer(h.PrinterTarget, h.DrawerKick)
		drawerMethod = result.Method
		drawerBinPath = result.BinPath
		drawerOutput = result.Output
		if err != nil {
			log.Printf("PrintTestReceipt: drawer kick target=%q command=%s method=%s binPath=%q failed after receipt print: %v",
				h.PrinterTarget, printer.HexCommand(h.DrawerKick), result.Method, result.BinPath, err)
			c.JSON(http.StatusInternalServerError, gin.H{
				"error":             "failed_to_open_drawer",
				"message":           err.Error(),
				"printed":           true,
				"drawerCommand":     printer.HexCommand(h.DrawerKick),
				"drawerCommandSent": false,
				"drawerMethod":      result.Method,
				"drawerBinPath":     result.BinPath,
				"drawerOutput":      result.Output,
				"target":            h.PrinterTarget,
				"bytes":             len(data),
			})
			return
		}
		drawerSent = true
	}

	mode := printer.NormalizePrintMode(h.PrinterMode)
	log.Printf("PrintTestReceipt: target=%q mode=%s bytes=%d drawer=%t drawerCommand=%s drawerMethod=%s",
		h.PrinterTarget, mode, len(data), drawerSent, printer.HexCommand(h.DrawerKick), drawerMethod)
	c.JSON(http.StatusOK, gin.H{
		"ok":                    true,
		"printed":               true,
		"duplicate":             false,
		"billId":                params.BillID,
		"bytes":                 len(data),
		"target":                h.PrinterTarget,
		"mode":                  mode,
		"drawerCommand":         printer.HexCommand(h.DrawerKick),
		"drawerCommandSent":     drawerSent,
		"drawerMethod":          drawerMethod,
		"drawerBinPath":         drawerBinPath,
		"drawerOutput":          drawerOutput,
		"drawerOpenedConfirmed": false,
	})
}

func (h *BillsHandler) buildReceiptParams(
	bill *repository.Bill,
	details []repository.BillDetail,
	discounts []repository.BillDiscountDetail,
	company *repository.Company,
) printer.ReceiptParams {
	var totalDiscount float64
	for _, d := range discounts {
		totalDiscount += d.Amount
	}

	items := make([]printer.ReceiptItem, 0, len(details))
	for _, d := range details {
		itemName, itemNameSource := receiptname.SafeProductNameWithSource(receiptname.Product{
			Code:        d.PartCode,
			ReceiptName: d.ReceiptName,
			Name:        d.Name,
		})
		if itemNameSource != "receipt_name" {
			log.Printf("BuildReceipt: bill=%s part=%s receiptNameSource=%s selected=%q",
				bill.ID, d.PartCode, itemNameSource, itemName)
		}
		items = append(items, printer.ReceiptItem{
			Code:      d.PartCode,
			Name:      itemName,
			Qty:       d.Qty,
			UnitPrice: d.Price,
			LineTotal: d.Price * float64(d.Qty),
		})
	}

	cashier := bill.UpdatedBy
	if cashier == "" {
		cashier = bill.CreatedBy
	}

	taxPercent := 7
	if bill.TotalAmount > 0 && bill.VATAmount > 0 {
		taxPercent = int((bill.VATAmount / (bill.TotalAmount - bill.VATAmount)) * 100.0)
		if taxPercent < 0 || taxPercent > 50 {
			taxPercent = 7
		}
	}

	companyPhone := ""
	if company.Phone != "" {
		companyPhone = company.Phone
	}
	companyWebsite := ""
	if company.Website != nil {
		companyWebsite = *company.Website
	}
	received, change, hasReceived, hasChange := receiptPaymentAmounts(parsePaymentMeta(bill.PaymentRef))
	// Cash counted out at the till is the authority; the payment meta is only
	// a fallback for bills taken before it was recorded.
	if bill.CashReceived != nil {
		received, hasReceived = *bill.CashReceived, true
	}
	if bill.ChangeAmount != nil {
		change, hasChange = *bill.ChangeAmount, true
	}
	// The membership line is shown separately, so the "ส่วนลด" line must not
	// include it or the receipt would count the same money twice.
	manualDiscount := totalDiscount
	if manualDiscount <= 0 {
		manualDiscount = maxFloat64(bill.TotalDiscount-bill.MemberDiscount, 0)
	}

	return printer.ReceiptParams{
		CompanyNameTh:   firstNonEmpty(company.CompanyNameTH, company.CompanyName),
		CompanyAddrTh:   firstNonEmpty(company.CompanyAddressTH, company.CompanyAddress),
		BusinessHours:   company.BusinessHours,
		TaxID:           company.TaxID,
		Phone:           companyPhone,
		Website:         companyWebsite,
		ReceiptFooter:   company.ReceiptFooter,
		BillID:          bill.ID,
		POSID:           bill.POSID,
		CustomerName:    bill.CustomerName,
		CashierName:     cashier,
		IssuedAt:        bill.UpdatedAt,
		PaymentMethod:   paymentLabelForMode(bill.PaymentMethod, h.PrinterMode),
		Items:           items,
		Subtotal:        bill.PurchaseAmount,
		MemberDiscount:  bill.MemberDiscount,
		Discount:        manualDiscount,
		Rounding:        bill.RoundingAmount,
		AmountAfterDisc: bill.PurchaseAmount - bill.TotalDiscount,
		TaxRatePercent:  taxPercent,
		Tax:             bill.VATAmount,
		Total:           bill.TotalAmount,
		ReceivedAmount:  received,
		ChangeAmount:    change,
		HasReceived:     hasReceived,
		HasChange:       hasChange,
		CodeTable:       h.PrinterCharset,
		PrintMode:       h.PrinterMode,
		OpenDrawer:      false,
		DrawerKick:      h.DrawerKick,
	}
}

func firstNonEmpty(a, b string) string {
	if strings.TrimSpace(a) != "" {
		return a
	}
	return b
}

func receiptPaymentAmounts(meta interface{}) (received, change float64, hasReceived, hasChange bool) {
	metaMap, ok := meta.(map[string]interface{})
	if !ok {
		return 0, 0, false, false
	}
	for _, key := range []string{"receivedAmount", "received", "paidAmount", "cashReceived"} {
		if v, ok := toFloat64(metaMap[key]); ok {
			received = v
			hasReceived = true
			break
		}
	}
	for _, key := range []string{"changeAmount", "change", "cashChange"} {
		if v, ok := toFloat64(metaMap[key]); ok {
			change = v
			hasChange = true
			break
		}
	}
	return received, change, hasReceived, hasChange
}

func paymentLabelForMode(method, mode string) string {
	if printer.NormalizePrintMode(mode) == printer.ModeThaiCP874 {
		return paymentLabelTH(method)
	}
	switch strings.ToLower(strings.TrimSpace(method)) {
	case "cash":
		return "Cash"
	case "bank", "transfer":
		return "Bank transfer"
	case "credit", "credit_term":
		return "Credit term"
	case "cheque", "check":
		return "Cheque"
	case "debit":
		return "Debit card"
	case "exchange":
		return "Exchange"
	case "":
		return ""
	default:
		return method
	}
}

// paymentLabelTH maps the bill.PaymentMethod enum value into a Thai label that
// reads naturally on the printed receipt.
func paymentLabelTH(method string) string {
	switch strings.ToLower(strings.TrimSpace(method)) {
	case "cash":
		return "เงินสด"
	case "bank", "transfer":
		return "โอน"
	case "credit", "credit_term":
		return "เงินเซ็น"
	case "cheque", "check":
		return "เช็ค"
	case "debit":
		return "บัตรเดบิต"
	case "exchange":
		return "แลกเปลี่ยน"
	case "":
		return ""
	default:
		return method
	}
}
