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
	TransferID   string
	PartCode     string
	RequestedQty int
	// ApprovedQty is what HQ decided to issue after checking the request
	// against the paper slip. Nil means it was not adjusted and RequestedQty
	// stands; zero means the line was reviewed down to nothing.
	ApprovedQty   *int
	Remarks       string
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

// RestockAdjustment is one line as HQ wants it to stand after review.
type RestockAdjustment struct {
	PartCode    string
	ApprovedQty int
	Remarks     string
}

type InventoryShortage struct {
	PartCode string
	// PartName so the person reading the failure knows which product it is
	// without going to look the code up.
	PartName     string
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
	// ReviewRestockItems records HQ's corrections to a restock waiting for
	// review: the quantity actually being issued, and the reason it differs.
	// The original request is left intact.
	ReviewRestockItems(ctx context.Context, transferID, actorID string, adjustments []RestockAdjustment) error
	// UpdateNotes replaces the document-level note.
	UpdateNotes(ctx context.Context, transferID, notes string) error
	SubmitPosRestock(ctx context.Context, transferID, userID string, timestamp time.Time) error
	UpdateStatus(ctx context.Context, id, status, userID string, timestamp time.Time) error
	UpdateItemsDispatched(ctx context.Context, transferID string, items []InventoryTransferItem) error
	UpdateItemsReceived(ctx context.Context, transferID string, items []InventoryTransferItem) error
	CompletePosRestock(ctx context.Context, transferID, userID string, timestamp time.Time) error
	ListCompletedRestocksByPOSDate(ctx context.Context, posID string, start, end time.Time) ([]InventoryTransfer, error)
	LogAudit(ctx context.Context, transferID, action, actorID, notes string) error
}
