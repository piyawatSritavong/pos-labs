package repository

import (
	"context"
	"fmt"
	"time"
)

type InventoryTransfer struct {
	ID             string
	FromBranchID   string
	ToBranchID     string
	FromStoreID    string
	ToStoreID      string
	TransferMode   string
	TargetPOSID    string
	CreatedBy      string
	Status         string
	Notes          string
	CreatedAt      time.Time
	SubmittedAt    *time.Time
	SubmittedBy    string
	ApprovedAt     *time.Time
	ApprovedBy     string
	DispatchedAt   *time.Time
	DispatchedBy   string
	ReceivedAt     *time.Time
	ReceivedBy     string
	CompletedAt    *time.Time
	CompletedBy    string
	TotalSaleValue float64
}

type InventoryTransferItem struct {
	TransferID    string
	PartCode      string
	RequestedQty  int
	DispatchedQty *int
	ReceivedQty   *int
	SalePrice     float64
	LineTotal     float64
	// enriched fields (not stored)
	PartName   string
	PartNameTH string
	BarCode    string
	Unit       string
}

type InventoryShortage struct {
	PartCode     string
	RequestedQty int
	AvailableQty int
	MissingQty   int
}

type InsufficientStockError struct {
	Shortages []InventoryShortage
}

func (e *InsufficientStockError) Error() string {
	return fmt.Sprintf("insufficient stock for %d item(s)", len(e.Shortages))
}

type InventoryTransferRepository interface {
	GenerateTransferID(ctx context.Context) (string, error)
	Create(ctx context.Context, transfer *InventoryTransfer, items []InventoryTransferItem) error
	GetByID(ctx context.Context, id string) (*InventoryTransfer, []InventoryTransferItem, error)
	List(ctx context.Context, limit, offset int, status, fromBranchID, toBranchID, transferMode, createdBy *string) ([]InventoryTransfer, error)
	UpdateItems(ctx context.Context, transferID string, items []InventoryTransferItem) error
	SubmitPosRestock(ctx context.Context, transferID, userID string, timestamp time.Time) error
	UpdateStatus(ctx context.Context, id, status, userID string, timestamp time.Time) error
	UpdateItemsDispatched(ctx context.Context, transferID string, items []InventoryTransferItem) error
	UpdateItemsReceived(ctx context.Context, transferID string, items []InventoryTransferItem) error
	CompletePosRestock(ctx context.Context, transferID, userID string, timestamp time.Time) error
	ListCompletedRestocksByPOSDate(ctx context.Context, posID string, start, end time.Time) ([]InventoryTransfer, error)
	LogAudit(ctx context.Context, transferID, action, actorID, notes string) error
}
