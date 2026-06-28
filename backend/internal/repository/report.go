package repository

import (
	"context"
	"time"
)

type BillWithItems struct {
	// Bill master fields
	ID             string
	BranchID       string
	POSID          string
	Status         string
	PaymentMethod  string
	PaymentRef     string
	MemberID       string
	CustomerName   string
	PurchaseAmount float64
	TotalDiscount  float64
	TotalAmount    float64
	VATAmount      float64
	XVATAmount     float64
	CreatedAt      time.Time
	UpdatedAt      time.Time
	CreatedBy      string
	UpdatedBy      string
	// Item detail fields (only when items=1)
	PartCode    string
	AddressCode string
	Name        string
	Price       float64
	Qty         int
}

// PartMaster represents a row from part_master table
type PartMaster struct {
	Code        string
	BarCode     string
	CategoryID  string
	UnitID      string
	Name        string
	NameTH      string
	ReceiptName string
	Details     string
	Cost        float64
	Price       float64
	Image       string
	IsActive    bool
}

type ReportRepository interface {
	// Get bills by date (for items=0)
	GetBillsByDate(ctx context.Context, date time.Time) ([]Bill, error)

	// Get bills with items by date (for items=1)
	// Returns one row per bill-item combination
	GetBillsWithItemsByDate(ctx context.Context, date time.Time) ([]BillWithItems, error)

	// Get all parts
	GetAllParts(ctx context.Context) ([]PartMaster, error)

	// Get all addresses (inventory)
	GetAllAddresses(ctx context.Context) ([]Address, error)
}
