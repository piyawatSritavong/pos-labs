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
	MinPrice    float64
	Image       string
	IsActive    bool
}

type ReportRepository interface {
	// Get bills by date (for items=0)
	GetBillsByDate(ctx context.Context, date time.Time) ([]Bill, error)

	// Get bills with items by date (for items=1)
	// Returns one row per bill-item combination
	GetBillsWithItemsByDate(ctx context.Context, date time.Time) ([]BillWithItems, error)

	// Date-range variants (dateStart inclusive, dateEnd exclusive) for
	// multi-day / multi-month exports.
	GetBillsByDateRange(ctx context.Context, dateStart, dateEnd time.Time) ([]Bill, error)
	GetBillsWithItemsByDateRange(ctx context.Context, dateStart, dateEnd time.Time) ([]BillWithItems, error)

	// Get all parts
	GetAllParts(ctx context.Context) ([]PartMaster, error)

	// Get all addresses (inventory)
	GetAllAddresses(ctx context.Context) ([]Address, error)

	GetIncomeReport(ctx context.Context, dateStart, dateEnd time.Time) (*IncomeReport, error)
}

type IncomeAccount struct {
	UserID       string
	Username     string
	Name         string
	Revenue      float64
	Returns      float64
	NetRevenue   float64
	SoldCost     float64
	ReturnedCost float64
	NetCost      float64
	GrossProfit  float64
	Expenses     float64
	NetProfit    float64
}

type IncomeExpenseDetail struct {
	ID                 string
	CloseDate          time.Time
	CreatedAt          time.Time
	UserID             string
	Username           string
	Name               string
	BranchID           string
	POSID              string
	FuelAmount         float64
	FoodAmount         float64
	TransferAmount     float64
	SpecialAmount      float64
	TailDiscountAmount float64
	FinalSummaryAmount float64
	Notes              string
	SpecialNote        string
	TotalExpense       float64
}

type IncomeSummary struct {
	Revenue      float64
	Returns      float64
	NetRevenue   float64
	SoldCost     float64
	ReturnedCost float64
	NetCost      float64
	GrossProfit  float64
	Expenses     float64
	NetProfit    float64
}

type IncomeReport struct {
	Summary        IncomeSummary
	Accounts       []IncomeAccount
	ExpenseDetails []IncomeExpenseDetail
}
