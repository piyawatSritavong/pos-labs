package repository

import (
	"context"
	"time"
)

type DailyClose struct {
	ID                 string
	BranchID           string
	PosID              string
	ClosedBy           string
	CloseDate          time.Time
	TotalSales         float64
	TotalCash          float64
	TotalTransfer      float64
	TotalCreditTerm    float64
	TotalBills         int
	TotalReturns       float64
	NetAmount          float64
	Status             string // "pending_reconciliation", "reconciled"
	Notes              string
	FuelAmount         *float64
	FoodAmount         *float64
	TransferAmount     *float64
	SpecialAmount      *float64
	TailDiscountAmount *float64
	FinalSummaryAmount *float64
	SpecialNote        string
	CreatedAt          time.Time
}

type DailySummary struct {
	TotalSales      float64
	TotalCash       float64
	TotalTransfer   float64
	TotalCreditTerm float64
	TotalBills      int
	TotalReturns    float64
	NetAmount       float64
}

type DailyCloseRepository interface {
	GenerateDailyCloseID(ctx context.Context) (string, error)
	GetSummary(ctx context.Context, branchID, posID string, closeDate time.Time) (*DailySummary, error)
	Create(ctx context.Context, dc *DailyClose) error
	GetByID(ctx context.Context, id string) (*DailyClose, error)
	List(ctx context.Context, limit, offset int, branchID *string, dateFrom, dateTo *time.Time) ([]DailyClose, error)
	UpdateStatus(ctx context.Context, id, status string) error
	ExistsByBranchPosDate(ctx context.Context, branchID, posID string, closeDate time.Time) (bool, error)
}
