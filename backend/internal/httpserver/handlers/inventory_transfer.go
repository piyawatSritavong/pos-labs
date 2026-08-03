package handlers

import (
	"context"
	"errors"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type InventoryTransferHandler struct {
	transfers repository.InventoryTransferRepository
	branches  repository.BranchRepository
	pos       repository.POSRepository
	parts     repository.PartRepository
}

type restockItemRequest struct {
	PartCode     string `json:"partCode" binding:"required"`
	RequestedQty int    `json:"requestedQty" binding:"required,min=1"`
}

func NewInventoryTransferHandler(transfers repository.InventoryTransferRepository, branches repository.BranchRepository, pos repository.POSRepository, parts repository.PartRepository) *InventoryTransferHandler {
	return &InventoryTransferHandler{
		transfers: transfers,
		branches:  branches,
		pos:       pos,
		parts:     parts,
	}
}

func buildTransferOutput(transfer *repository.InventoryTransfer, items []repository.InventoryTransferItem) gin.H {
	itemOut := make([]gin.H, 0, len(items))
	for _, item := range items {
		row := gin.H{
			"transferId":   item.TransferID,
			"partCode":     item.PartCode,
			"barCode":      item.BarCode,
			"requestedQty": item.RequestedQty,
			"partName":     item.PartName,
			"partNameTh":   item.PartNameTH,
			"unit":         item.Unit,
			"salePrice":    item.SalePrice,
			"lineTotal":    item.LineTotal,
		}
		if item.DispatchedQty != nil {
			row["dispatchedQty"] = *item.DispatchedQty
		} else {
			row["dispatchedQty"] = nil
		}
		if item.ReceivedQty != nil {
			row["receivedQty"] = *item.ReceivedQty
		} else {
			row["receivedQty"] = nil
		}
		itemOut = append(itemOut, row)
	}

	out := gin.H{
		"id":             transfer.ID,
		"fromBranchId":   transfer.FromBranchID,
		"toBranchId":     transfer.ToBranchID,
		"fromStoreId":    transfer.FromStoreID,
		"toStoreId":      transfer.ToStoreID,
		"transferMode":   transfer.TransferMode,
		"targetPosId":    transfer.TargetPOSID,
		"createdBy":      transfer.CreatedBy,
		"status":         transfer.Status,
		"notes":          transfer.Notes,
		"createdAt":      transfer.CreatedAt.Format(time.RFC3339),
		"submittedBy":    transfer.SubmittedBy,
		"approvedBy":     transfer.ApprovedBy,
		"dispatchedBy":   transfer.DispatchedBy,
		"receivedBy":     transfer.ReceivedBy,
		"completedBy":    transfer.CompletedBy,
		"items":          itemOut,
		"totalSaleValue": transfer.TotalSaleValue,
	}

	if transfer.SubmittedAt != nil {
		out["submittedAt"] = transfer.SubmittedAt.Format(time.RFC3339)
	} else {
		out["submittedAt"] = nil
	}
	if transfer.ApprovedAt != nil {
		out["approvedAt"] = transfer.ApprovedAt.Format(time.RFC3339)
	} else {
		out["approvedAt"] = nil
	}
	if transfer.DispatchedAt != nil {
		out["dispatchedAt"] = transfer.DispatchedAt.Format(time.RFC3339)
	} else {
		out["dispatchedAt"] = nil
	}
	if transfer.ReceivedAt != nil {
		out["receivedAt"] = transfer.ReceivedAt.Format(time.RFC3339)
	} else {
		out["receivedAt"] = nil
	}
	if transfer.CompletedAt != nil {
		out["completedAt"] = transfer.CompletedAt.Format(time.RFC3339)
	} else {
		out["completedAt"] = nil
	}
	if stale, reason := transferStaleState(transfer, time.Now().UTC()); stale {
		out["isStale"] = true
		out["staleReason"] = reason
	} else {
		out["isStale"] = false
		out["staleReason"] = ""
	}

	return out
}

func (h *InventoryTransferHandler) List(c *gin.Context) {
	limit := 50
	offset := 0
	if raw := c.Query("limit"); raw != "" {
		if parsed, err := strconv.Atoi(raw); err == nil && parsed > 0 {
			limit = parsed
		}
	}
	if raw := c.Query("offset"); raw != "" {
		if parsed, err := strconv.Atoi(raw); err == nil && parsed >= 0 {
			offset = parsed
		}
	}

	var status, fromBranchID, toBranchID, transferMode, createdBy *string
	if raw := strings.TrimSpace(c.Query("status")); raw != "" {
		status = &raw
	}
	if raw := strings.TrimSpace(c.Query("fromBranchId")); raw != "" {
		fromBranchID = &raw
	}
	if raw := strings.TrimSpace(c.Query("toBranchId")); raw != "" {
		toBranchID = &raw
	}
	if raw := strings.TrimSpace(c.Query("transferMode")); raw != "" {
		transferMode = &raw
	}

	userVal, _ := c.Get("user")
	user, _ := userVal.(*repository.User)
	if user != nil && isPOSRole(user) {
		createdBy = &user.ID
	}

	transfers, err := h.transfers.List(c.Request.Context(), limit, offset, status, fromBranchID, toBranchID, transferMode, createdBy)
	if err != nil {
		log.Printf("Error listing transfers: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_list_transfers"})
		return
	}

	out := make([]gin.H, 0, len(transfers))
	for _, t := range transfers {
		tc := t
		if !canAccessTransfer(c, &tc) {
			continue
		}
		out = append(out, buildTransferOutput(&tc, nil))
	}

	c.JSON(http.StatusOK, gin.H{"data": out, "total": len(out)})
}

// RestockCatalog exposes the active main-warehouse catalog to POS operators.
// Cost and minimum price are intentionally omitted from this employee-facing
// response.
func (h *InventoryTransferHandler) RestockCatalog(c *gin.Context) {
	query := strings.TrimSpace(c.Query("q"))
	limit := 30
	if raw := c.Query("limit"); raw != "" {
		if parsed, err := strconv.Atoi(raw); err == nil && parsed > 0 && parsed <= 100 {
			limit = parsed
		}
	}
	active := true
	mainStore := "main"
	parts, err := h.parts.SearchParts(
		c.Request.Context(), query, nil, &active, nil, &mainStore, true, limit, 0,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_search_restock_catalog"})
		return
	}
	codes := make([]string, 0, len(parts))
	for _, part := range parts {
		codes = append(codes, part.Code)
	}
	addresses, err := h.parts.GetAddressesByPartCodes(c.Request.Context(), codes, nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_load_main_stock"})
		return
	}
	out := make([]gin.H, 0, len(parts))
	for _, part := range parts {
		available := 0
		for _, address := range addresses[part.Code] {
			if address.StoreID == "main" && address.Qty > 0 {
				available += address.Qty
			}
		}
		if available <= 0 {
			continue
		}
		out = append(out, gin.H{
			"code":         part.Code,
			"barCode":      part.BarCode,
			"name":         part.Name,
			"nameTh":       part.NameTH,
			"unit":         gin.H{"id": part.UnitID, "label": part.UnitLabel, "labelTh": part.UnitLabelTH},
			"price":        part.Price,
			"availableQty": available,
		})
	}
	c.JSON(http.StatusOK, gin.H{"parts": out, "total": len(out)})
}

func (h *InventoryTransferHandler) VehicleDailySummary(c *gin.Context) {
	if !canReadAllOperationalData(c) {
		c.JSON(http.StatusForbidden, gin.H{"error": "global_scope_forbidden"})
		return
	}
	posID := strings.TrimSpace(c.Query("posId"))
	dateText := strings.TrimSpace(c.Query("date"))
	if posID == "" || dateText == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_fields", "message": "posId and date are required"})
		return
	}
	location, err := time.LoadLocation("Asia/Bangkok")
	if err != nil {
		location = time.FixedZone("Asia/Bangkok", 7*60*60)
	}
	day, err := time.ParseInLocation("2006-01-02", dateText, location)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_date"})
		return
	}
	posSetting, err := h.pos.GetByID(c.Request.Context(), posID)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "pos_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_pos"})
		return
	}
	transfers, err := h.transfers.ListCompletedRestocksByPOSDate(
		c.Request.Context(), posID, day.UTC(), day.AddDate(0, 0, 1).UTC(),
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_build_daily_summary"})
		return
	}
	documents := make([]gin.H, 0, len(transfers))
	grandTotal := 0.0
	for i := range transfers {
		transfer, items, err := h.transfers.GetByID(c.Request.Context(), transfers[i].ID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_load_daily_summary_item"})
			return
		}
		document := buildTransferOutput(transfer, items)
		documents = append(documents, document)
		grandTotal += transfer.TotalSaleValue
	}
	c.JSON(http.StatusOK, gin.H{
		"date": dateText,
		"pos": gin.H{
			"posId": posSetting.POSID, "posName": posSetting.POSName, "branchId": posSetting.BranchID,
		},
		"documents":           documents,
		"documentCount":       len(documents),
		"grandTotalSaleValue": grandTotal,
	})
}

func (h *InventoryTransferHandler) Create(c *gin.Context) {
	userVal, _ := c.Get("user")
	user, _ := userVal.(*repository.User)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var req struct {
		FromBranchID string `json:"fromBranchId" binding:"required"`
		ToBranchID   string `json:"toBranchId" binding:"required"`
		Notes        string `json:"notes"`
		Items        []struct {
			PartCode     string `json:"partCode" binding:"required"`
			RequestedQty int    `json:"requestedQty" binding:"required,min=1"`
		} `json:"items" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": err.Error()})
		return
	}

	if len(req.Items) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_items", "message": "items must not be empty"})
		return
	}

	transferID, err := h.transfers.GenerateTransferID(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_generate_transfer_id"})
		return
	}

	items := make([]repository.InventoryTransferItem, 0, len(req.Items))
	for _, item := range req.Items {
		items = append(items, repository.InventoryTransferItem{
			TransferID:   transferID,
			PartCode:     strings.TrimSpace(item.PartCode),
			RequestedQty: item.RequestedQty,
		})
	}

	initialStatus := "pending"
	if user.RoleID == "role.van_staff" {
		initialStatus = "requested"
	}

	transfer := &repository.InventoryTransfer{
		ID:           transferID,
		FromBranchID: strings.TrimSpace(req.FromBranchID),
		ToBranchID:   strings.TrimSpace(req.ToBranchID),
		CreatedBy:    user.ID,
		Status:       initialStatus,
		Notes:        req.Notes,
		CreatedAt:    time.Now().UTC(),
	}

	if err := h.transfers.Create(c.Request.Context(), transfer, items); err != nil {
		log.Printf("Error creating transfer: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_create_transfer"})
		return
	}

	createdTransfer, createdItems, err := h.transfers.GetByID(c.Request.Context(), transferID)
	if err != nil {
		c.JSON(http.StatusCreated, buildTransferOutput(transfer, items))
		return
	}

	c.JSON(http.StatusCreated, gin.H{"data": buildTransferOutput(createdTransfer, createdItems)})
}

func (h *InventoryTransferHandler) CreatePosRestock(c *gin.Context) {
	userVal, _ := c.Get("user")
	user, _ := userVal.(*repository.User)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	branchID, posID, ok := branchAndPOSFromContext(c)
	if !ok {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_pos_context", "message": "branchId and posId are required"})
		return
	}

	var req struct {
		Notes string               `json:"notes"`
		Items []restockItemRequest `json:"items"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": err.Error()})
		return
	}

	sourceStoreID := "main"

	pos, err := h.pos.GetByID(c.Request.Context(), posID)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "pos_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_pos"})
		return
	}
	if pos.BranchID != branchID {
		c.JSON(http.StatusForbidden, gin.H{"error": "pos_branch_mismatch"})
		return
	}
	if strings.TrimSpace(pos.VehicleStoreID) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_vehicle_store", "message": "POS vehicle store is required"})
		return
	}
	if pos.VehicleStoreID == "main" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "pos_has_no_vehicle_stock", "message": "Only vehicle POS can create a restock request"})
		return
	}

	transferID, err := h.transfers.GenerateTransferID(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_generate_transfer_id"})
		return
	}

	items := normalizeRestockItems(transferID, req.Items)
	transfer := &repository.InventoryTransfer{
		ID:           transferID,
		FromBranchID: branchID,
		ToBranchID:   branchID,
		FromStoreID:  sourceStoreID,
		ToStoreID:    pos.VehicleStoreID,
		TransferMode: "pos_restock",
		TargetPOSID:  posID,
		CreatedBy:    user.ID,
		Status:       "draft",
		Notes:        req.Notes,
		CreatedAt:    time.Now().UTC(),
	}

	if err := h.transfers.Create(c.Request.Context(), transfer, items); err != nil {
		log.Printf("Error creating POS restock transfer: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_create_transfer"})
		return
	}
	_ = h.transfers.LogAudit(c.Request.Context(), transferID, "created_draft", user.ID, "")

	createdTransfer, createdItems, err := h.transfers.GetByID(c.Request.Context(), transferID)
	if err != nil {
		c.JSON(http.StatusCreated, gin.H{"data": buildTransferOutput(transfer, items)})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"data": buildTransferOutput(createdTransfer, createdItems)})
}

func (h *InventoryTransferHandler) GetByID(c *gin.Context) {
	id := strings.TrimSpace(c.Param("id"))
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_transfer_id"})
		return
	}

	transfer, items, err := h.transfers.GetByID(c.Request.Context(), id)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "transfer_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_transfer"})
		return
	}
	if !canAccessTransfer(c, transfer) {
		c.JSON(http.StatusForbidden, gin.H{"error": "forbidden"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": buildTransferOutput(transfer, items)})
}

func (h *InventoryTransferHandler) UpdateItems(c *gin.Context) {
	id := strings.TrimSpace(c.Param("id"))
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_transfer_id"})
		return
	}

	userVal, _ := c.Get("user")
	user, _ := userVal.(*repository.User)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var req struct {
		Items []restockItemRequest `json:"items"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": err.Error()})
		return
	}

	transfer, _, err := h.transfers.GetByID(c.Request.Context(), id)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "transfer_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_transfer"})
		return
	}
	if transfer.TransferMode != "pos_restock" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_transfer_mode"})
		return
	}
	if transfer.Status != "draft" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_status", "message": "Only draft restock requests can be edited"})
		return
	}
	if isPOSRole(user) && transfer.CreatedBy != user.ID {
		c.JSON(http.StatusForbidden, gin.H{"error": "forbidden"})
		return
	}

	items := normalizeRestockItems(id, req.Items)
	if err := h.transfers.UpdateItems(c.Request.Context(), id, items); err != nil {
		log.Printf("Error updating restock items: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_update_items"})
		return
	}
	_ = h.transfers.LogAudit(c.Request.Context(), id, "items_updated", user.ID, "")

	updatedTransfer, updatedItems, err := h.transfers.GetByID(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusOK, gin.H{"data": gin.H{"id": id}})
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": buildTransferOutput(updatedTransfer, updatedItems)})
}

func (h *InventoryTransferHandler) Submit(c *gin.Context) {
	id := strings.TrimSpace(c.Param("id"))
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_transfer_id"})
		return
	}

	userVal, _ := c.Get("user")
	user, _ := userVal.(*repository.User)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	transfer, items, err := h.transfers.GetByID(c.Request.Context(), id)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "transfer_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_transfer"})
		return
	}
	if transfer.TransferMode != "pos_restock" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_transfer_mode"})
		return
	}
	if transfer.Status != "draft" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_status", "message": "Only draft restock requests can be submitted"})
		return
	}
	if isPOSRole(user) && transfer.CreatedBy != user.ID {
		c.JSON(http.StatusForbidden, gin.H{"error": "forbidden"})
		return
	}
	if len(items) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_items", "message": "items must not be empty"})
		return
	}

	now := time.Now().UTC()
	if err := h.transfers.UpdateStatus(c.Request.Context(), id, "review", user.ID, now); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_submit_transfer"})
		return
	}
	_ = h.transfers.LogAudit(c.Request.Context(), id, "submitted_for_review", user.ID, "")

	updatedTransfer, updatedItems, err := h.transfers.GetByID(c.Request.Context(), id)
	if err != nil {
		transfer.Status = "review"
		transfer.SubmittedAt = &now
		transfer.SubmittedBy = user.ID
		c.JSON(http.StatusOK, gin.H{"data": buildTransferOutput(transfer, items)})
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": buildTransferOutput(updatedTransfer, updatedItems)})
}

func (h *InventoryTransferHandler) ApproveRestock(c *gin.Context) {
	id := strings.TrimSpace(c.Param("id"))
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_transfer_id"})
		return
	}

	userVal, _ := c.Get("user")
	user, _ := userVal.(*repository.User)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	now := time.Now().UTC()
	if err := h.transfers.CompletePosRestock(c.Request.Context(), id, user.ID, now); err != nil {
		var insufficient *repository.InsufficientStockError
		if errors.As(err, &insufficient) {
			shortages := make([]gin.H, 0, len(insufficient.Shortages))
			for _, s := range insufficient.Shortages {
				shortages = append(shortages, gin.H{
					"partCode":     s.PartCode,
					"requestedQty": s.RequestedQty,
					"availableQty": s.AvailableQty,
					"missingQty":   s.MissingQty,
				})
			}
			c.JSON(http.StatusConflict, gin.H{"error": "insufficient_stock", "shortages": shortages})
			return
		}
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "transfer_not_found"})
			return
		}
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	updatedTransfer, updatedItems, err := h.transfers.GetByID(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusOK, gin.H{"data": gin.H{"id": id, "status": "completed"}})
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": buildTransferOutput(updatedTransfer, updatedItems)})
}

func (h *InventoryTransferHandler) PrintLog(c *gin.Context) {
	id := strings.TrimSpace(c.Param("id"))
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_transfer_id"})
		return
	}

	userVal, _ := c.Get("user")
	user, _ := userVal.(*repository.User)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	transfer, _, err := h.transfers.GetByID(c.Request.Context(), id)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "transfer_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_transfer"})
		return
	}
	if !canAccessTransfer(c, transfer) {
		c.JSON(http.StatusForbidden, gin.H{"error": "transfer_access_denied"})
		return
	}
	if err := h.transfers.LogAudit(c.Request.Context(), id, "printed_pdf", user.ID, "browser_print"); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_log_print"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

func (h *InventoryTransferHandler) Approve(c *gin.Context) {
	id := strings.TrimSpace(c.Param("id"))
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_transfer_id"})
		return
	}

	userVal, _ := c.Get("user")
	user, _ := userVal.(*repository.User)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	transfer, items, err := h.transfers.GetByID(c.Request.Context(), id)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "transfer_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_transfer"})
		return
	}

	if transfer.Status != "pending" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_status", "message": "Transfer must be in 'pending' status to approve"})
		return
	}

	now := time.Now().UTC()
	if err := h.transfers.UpdateStatus(c.Request.Context(), id, "approved", user.ID, now); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_approve_transfer"})
		return
	}

	transfer.Status = "approved"
	transfer.ApprovedAt = &now
	transfer.ApprovedBy = user.ID

	c.JSON(http.StatusOK, gin.H{"data": buildTransferOutput(transfer, items)})
}

func (h *InventoryTransferHandler) Dispatch(c *gin.Context) {
	id := strings.TrimSpace(c.Param("id"))
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_transfer_id"})
		return
	}

	userVal, _ := c.Get("user")
	user, _ := userVal.(*repository.User)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var req struct {
		Items []struct {
			PartCode      string `json:"partCode" binding:"required"`
			DispatchedQty int    `json:"dispatchedQty" binding:"required,min=0"`
		} `json:"items" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": err.Error()})
		return
	}

	transfer, _, err := h.transfers.GetByID(c.Request.Context(), id)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "transfer_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_transfer"})
		return
	}

	if transfer.Status != "approved" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_status", "message": "Transfer must be in 'approved' status to dispatch"})
		return
	}

	dispatchItems := make([]repository.InventoryTransferItem, 0, len(req.Items))
	for _, item := range req.Items {
		qty := item.DispatchedQty
		dispatchItems = append(dispatchItems, repository.InventoryTransferItem{
			TransferID:    id,
			PartCode:      strings.TrimSpace(item.PartCode),
			DispatchedQty: &qty,
		})
	}

	if err := h.transfers.UpdateItemsDispatched(c.Request.Context(), id, dispatchItems); err != nil {
		log.Printf("Error dispatching transfer: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_dispatch_transfer"})
		return
	}

	now := time.Now().UTC()
	if err := h.transfers.UpdateStatus(c.Request.Context(), id, "dispatched", user.ID, now); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_update_transfer_status"})
		return
	}

	updatedTransfer, updatedItems, err := h.transfers.GetByID(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusOK, gin.H{"data": gin.H{"id": id, "status": "dispatched"}})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": buildTransferOutput(updatedTransfer, updatedItems)})
}

func (h *InventoryTransferHandler) Receive(c *gin.Context) {
	id := strings.TrimSpace(c.Param("id"))
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_transfer_id"})
		return
	}

	userVal, _ := c.Get("user")
	user, _ := userVal.(*repository.User)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var req struct {
		Items []struct {
			PartCode    string `json:"partCode" binding:"required"`
			ReceivedQty int    `json:"receivedQty" binding:"required,min=0"`
		} `json:"items" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": err.Error()})
		return
	}

	transfer, _, err := h.transfers.GetByID(c.Request.Context(), id)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "transfer_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_transfer"})
		return
	}

	if transfer.Status != "dispatched" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_status", "message": "Transfer must be in 'dispatched' status to receive"})
		return
	}

	receiveItems := make([]repository.InventoryTransferItem, 0, len(req.Items))
	for _, item := range req.Items {
		qty := item.ReceivedQty
		receiveItems = append(receiveItems, repository.InventoryTransferItem{
			TransferID:  id,
			PartCode:    strings.TrimSpace(item.PartCode),
			ReceivedQty: &qty,
		})
	}

	if err := h.transfers.UpdateItemsReceived(c.Request.Context(), id, receiveItems); err != nil {
		log.Printf("Error receiving transfer: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_receive_transfer"})
		return
	}

	now := time.Now().UTC()
	if err := h.transfers.UpdateStatus(c.Request.Context(), id, "received", user.ID, now); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_update_transfer_status"})
		return
	}

	updatedTransfer, updatedItems, err := h.transfers.GetByID(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusOK, gin.H{"data": gin.H{"id": id, "status": "received"}})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": buildTransferOutput(updatedTransfer, updatedItems)})
}

func (h *InventoryTransferHandler) Cancel(c *gin.Context) {
	id := strings.TrimSpace(c.Param("id"))
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_transfer_id"})
		return
	}

	userVal, _ := c.Get("user")
	user, _ := userVal.(*repository.User)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	transfer, items, err := h.transfers.GetByID(c.Request.Context(), id)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "transfer_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_transfer"})
		return
	}

	if transfer.TransferMode == "pos_restock" {
		if transfer.Status != "draft" && transfer.Status != "review" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_status", "message": "POS restock request must be in 'draft' or 'review' status to cancel"})
			return
		}
	} else if transfer.Status != "pending" && transfer.Status != "approved" && transfer.Status != "requested" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_status", "message": "Transfer must be in 'pending', 'approved', or 'requested' status to cancel"})
		return
	}

	// Van Staff can only cancel transfers they created
	if isPOSRole(user) && transfer.CreatedBy != user.ID {
		c.JSON(http.StatusForbidden, gin.H{"error": "forbidden", "message": "van staff can only cancel their own requests"})
		return
	}

	now := time.Now().UTC()
	if err := h.transfers.UpdateStatus(c.Request.Context(), id, "cancelled", user.ID, now); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_cancel_transfer"})
		return
	}

	transfer.Status = "cancelled"
	_ = h.transfers.LogAudit(c.Request.Context(), id, "cancelled", user.ID, "")

	c.JSON(http.StatusOK, gin.H{"data": buildTransferOutput(transfer, items)})
}

func (h *InventoryTransferHandler) Acknowledge(c *gin.Context) {
	id := strings.TrimSpace(c.Param("id"))
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_transfer_id"})
		return
	}

	userVal, _ := c.Get("user")
	user, _ := userVal.(*repository.User)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	transfer, items, err := h.transfers.GetByID(c.Request.Context(), id)
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "transfer_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_transfer"})
		return
	}

	if transfer.Status != "requested" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_status", "message": "Transfer must be in 'requested' status to acknowledge"})
		return
	}

	now := time.Now().UTC()
	if err := h.transfers.UpdateStatus(c.Request.Context(), id, "pending", user.ID, now); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_acknowledge_transfer"})
		return
	}

	transfer.Status = "pending"
	c.JSON(http.StatusOK, gin.H{"data": buildTransferOutput(transfer, items)})
}

func (h *InventoryTransferHandler) defaultStoreID(ctx context.Context, branchID string) (string, error) {
	if h.branches == nil {
		return "", repository.ErrNotFound
	}
	stores, err := h.branches.GetStoresByBranchID(ctx, branchID)
	if err != nil {
		return "", err
	}
	for _, store := range stores {
		if store.IsDefault {
			return store.ID, nil
		}
	}
	if len(stores) > 0 {
		return stores[0].ID, nil
	}
	return "", repository.ErrNotFound
}

func normalizeRestockItems(transferID string, raw []restockItemRequest) []repository.InventoryTransferItem {
	byPart := make(map[string]int)
	order := make([]string, 0, len(raw))
	for _, item := range raw {
		partCode := strings.TrimSpace(item.PartCode)
		if partCode == "" || item.RequestedQty <= 0 {
			continue
		}
		if _, exists := byPart[partCode]; !exists {
			order = append(order, partCode)
		}
		byPart[partCode] += item.RequestedQty
	}
	items := make([]repository.InventoryTransferItem, 0, len(order))
	for _, partCode := range order {
		items = append(items, repository.InventoryTransferItem{
			TransferID:   transferID,
			PartCode:     partCode,
			RequestedQty: byPart[partCode],
		})
	}
	return items
}

func branchAndPOSFromContext(c *gin.Context) (string, string, bool) {
	branchVal, branchOK := c.Get("branch_id")
	posVal, posOK := c.Get("pos_id")
	branchID, branchString := branchVal.(string)
	posID, posString := posVal.(string)
	return strings.TrimSpace(branchID), strings.TrimSpace(posID), branchOK && posOK && branchString && posString && strings.TrimSpace(branchID) != "" && strings.TrimSpace(posID) != ""
}

func isPOSRole(user *repository.User) bool {
	return user != nil && (user.RoleID == "role.cashier" || user.RoleID == "role.van_staff")
}

func canAccessTransfer(c *gin.Context, transfer *repository.InventoryTransfer) bool {
	userVal, _ := c.Get("user")
	user, _ := userVal.(*repository.User)
	if user == nil || transfer == nil {
		return false
	}
	if isPOSRole(user) {
		return transfer.CreatedBy == user.ID
	}
	if canReadAllOperationalData(c) {
		return true
	}
	branch, _, ok := branchAndPOSFromContext(c)
	return ok && (transfer.FromBranchID == branch || transfer.ToBranchID == branch)
}

func transferStaleState(transfer *repository.InventoryTransfer, now time.Time) (bool, string) {
	if transfer == nil || transfer.TransferMode != "pos_restock" {
		return false, ""
	}
	if transfer.Status == "draft" && now.Sub(transfer.CreatedAt) > 24*time.Hour {
		return true, "ค้างเกิน 1 วัน"
	}
	if transfer.Status == "review" && transfer.SubmittedAt != nil && now.Sub(*transfer.SubmittedAt) > 24*time.Hour {
		return true, "รออนุมัติเกิน 1 วัน"
	}
	return false, ""
}
