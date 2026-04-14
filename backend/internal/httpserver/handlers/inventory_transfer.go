package handlers

import (
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
}

func NewInventoryTransferHandler(transfers repository.InventoryTransferRepository, branches repository.BranchRepository) *InventoryTransferHandler {
	return &InventoryTransferHandler{
		transfers: transfers,
		branches:  branches,
	}
}

func buildTransferOutput(transfer *repository.InventoryTransfer, items []repository.InventoryTransferItem) gin.H {
	itemOut := make([]gin.H, 0, len(items))
	for _, item := range items {
		row := gin.H{
			"transferId":   item.TransferID,
			"partCode":     item.PartCode,
			"requestedQty": item.RequestedQty,
			"partName":     item.PartName,
			"partNameTh":   item.PartNameTH,
			"unit":         item.Unit,
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
		"id":           transfer.ID,
		"fromBranchId": transfer.FromBranchID,
		"toBranchId":   transfer.ToBranchID,
		"createdBy":    transfer.CreatedBy,
		"status":       transfer.Status,
		"notes":        transfer.Notes,
		"createdAt":    transfer.CreatedAt.Format(time.RFC3339),
		"approvedBy":   transfer.ApprovedBy,
		"dispatchedBy": transfer.DispatchedBy,
		"receivedBy":   transfer.ReceivedBy,
		"items":        itemOut,
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

	var status, fromBranchID, toBranchID *string
	if raw := strings.TrimSpace(c.Query("status")); raw != "" {
		status = &raw
	}
	if raw := strings.TrimSpace(c.Query("fromBranchId")); raw != "" {
		fromBranchID = &raw
	}
	if raw := strings.TrimSpace(c.Query("toBranchId")); raw != "" {
		toBranchID = &raw
	}

	transfers, err := h.transfers.List(c.Request.Context(), limit, offset, status, fromBranchID, toBranchID)
	if err != nil {
		log.Printf("Error listing transfers: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_list_transfers"})
		return
	}

	out := make([]gin.H, 0, len(transfers))
	for _, t := range transfers {
		tc := t
		out = append(out, buildTransferOutput(&tc, nil))
	}

	c.JSON(http.StatusOK, gin.H{"data": out, "total": len(out)})
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

	c.JSON(http.StatusOK, gin.H{"data": buildTransferOutput(transfer, items)})
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

	if transfer.Status != "pending" && transfer.Status != "approved" && transfer.Status != "requested" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_status", "message": "Transfer must be in 'pending', 'approved', or 'requested' status to cancel"})
		return
	}

	// Van Staff can only cancel transfers they created
	if user.RoleID == "role.van_staff" && transfer.CreatedBy != user.ID {
		c.JSON(http.StatusForbidden, gin.H{"error": "forbidden", "message": "van staff can only cancel their own requests"})
		return
	}

	now := time.Now().UTC()
	if err := h.transfers.UpdateStatus(c.Request.Context(), id, "cancelled", user.ID, now); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_cancel_transfer"})
		return
	}

	transfer.Status = "cancelled"

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
