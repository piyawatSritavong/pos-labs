package repository

import (
	"context"
	"time"
)

type ReturnNote struct {
	ID              string
	ReferenceBillID string
	PurchaseBillID  string
	BranchID        string
	POSID           string
	Status          string
	SettlementMode  string
	PaymentMethod   string
	PaymentRef      string
	MemberID        string
	CustomerName    string
	PurchaseAmount  float64
	RefundAmount    float64
	NetAmount       float64
	CreatedAt       time.Time
	UpdatedAt       time.Time
	CreatedBy       string
	UpdatedBy       string
}

type ReturnNoteItem struct {
	ReturnNoteID     string
	ReferenceBillID  string
	PartCode         string
	AddressCode      string
	UnitID           string
	UnitLabel        string
	UnitLabelTH      string
	Name             string
	ReceiptName      string
	Price            float64
	Qty              int
	LineTotal        float64
	ReferenceLineQty int
	ReturnedQty      int
	RemainingQty     int
}

type ReturnNoteRepository interface {
	GenerateReturnNoteID(ctx context.Context) (string, error)
	Create(ctx context.Context, note *ReturnNote, items []ReturnNoteItem) error
	GetByID(ctx context.Context, id string) (*ReturnNote, []ReturnNoteItem, error)
	List(ctx context.Context, limit, offset int, dateFrom, dateTo *time.Time, branchID, posID, referenceBillID *string) ([]ReturnNote, error)
	GetItems(ctx context.Context, returnNoteID string) ([]ReturnNoteItem, error)
	GetReturnedQtyByReferenceBill(ctx context.Context, referenceBillID string) (map[string]int, error)
}
