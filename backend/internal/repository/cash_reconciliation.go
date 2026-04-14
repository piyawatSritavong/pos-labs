package repository

import (
	"context"
	"time"
)

type CashReconciliation struct {
	ID             string
	DailyCloseID   string
	ConfirmedBy    string
	ExpectedAmount float64
	ActualAmount   float64
	Difference     float64
	Notes          string
	CreatedAt      time.Time
	// enriched
	BranchID  string
	PosID     string
	CloseDate time.Time
}

type CashReconciliationRepository interface {
	GenerateCashReconciliationID(ctx context.Context) (string, error)
	Create(ctx context.Context, cr *CashReconciliation) error
	GetByID(ctx context.Context, id string) (*CashReconciliation, error)
	List(ctx context.Context, limit, offset int, branchID *string) ([]CashReconciliation, error)
}
