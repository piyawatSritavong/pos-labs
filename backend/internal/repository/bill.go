package repository

import (
	"context"
	"time"
)

type Bill struct {
	ID            string
	Status        string // new, hold, completed, cancelled
	PaymentMethod string // cash, bank, credit, debit, other
	PurchaseAmount float64
	TotalDiscount  float64
	TotalAmount    float64
	VATAmount      float64
	XVATAmount     float64
	CreatedAt      time.Time
	UpdatedAt      time.Time
	CreatedBy      string
	UpdatedBy      string
}

type BillDetail struct {
	BillID      string
	PartCode    string
	AddressCode string
	UnitID      string
	UnitLabel   string
	UnitLabelTH string
	Name        string
	Cost        float64
	Price       float64
	Qty         int
}

type BillRepository interface {
	GenerateBillID(ctx context.Context) (string, error)
	Create(ctx context.Context, bill *Bill) error
	GetByID(ctx context.Context, id string) (*Bill, error)
	List(ctx context.Context, limit, offset int) ([]Bill, error)
}

