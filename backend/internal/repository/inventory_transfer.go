package repository

import (
	"context"
	"time"
)

type InventoryTransfer struct {
	ID           string
	FromBranchID string
	ToBranchID   string
	CreatedBy    string
	Status       string
	Notes        string
	CreatedAt    time.Time
	ApprovedAt   *time.Time
	ApprovedBy   string
	DispatchedAt *time.Time
	DispatchedBy string
	ReceivedAt   *time.Time
	ReceivedBy   string
}

type InventoryTransferItem struct {
	TransferID    string
	PartCode      string
	RequestedQty  int
	DispatchedQty *int
	ReceivedQty   *int
	// enriched fields (not stored)
	PartName   string
	PartNameTH string
	Unit       string
}

type InventoryTransferRepository interface {
	GenerateTransferID(ctx context.Context) (string, error)
	Create(ctx context.Context, transfer *InventoryTransfer, items []InventoryTransferItem) error
	GetByID(ctx context.Context, id string) (*InventoryTransfer, []InventoryTransferItem, error)
	List(ctx context.Context, limit, offset int, status, fromBranchID, toBranchID *string) ([]InventoryTransfer, error)
	UpdateStatus(ctx context.Context, id, status, userID string, timestamp time.Time) error
	UpdateItemsDispatched(ctx context.Context, transferID string, items []InventoryTransferItem) error
	UpdateItemsReceived(ctx context.Context, transferID string, items []InventoryTransferItem) error
}
