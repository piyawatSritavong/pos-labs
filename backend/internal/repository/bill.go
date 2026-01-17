package repository

import (
	"context"
	"time"
)

type Bill struct {
	ID            string
	BranchID      string
	POSID         string
	Status        string // new, hold, completed, cancelled
	PaymentMethod string // cash, bank, credit, debit, other
	PaymentRef    string
	MemberID      string
	CustomerName  string
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

type BillDiscountDetail struct {
	BillID        string
	PromotionCode string
	Unit          string
	Amount        float64
}

type BillRepository interface {
	GenerateBillID(ctx context.Context) (string, error)
	Create(ctx context.Context, bill *Bill) error
	GetByID(ctx context.Context, id string) (*Bill, error)
	List(ctx context.Context, limit, offset int) ([]Bill, error)
	GetFullByID(ctx context.Context, id string) (*Bill, []BillDetail, []BillDiscountDetail, error)
	GetNewBillByPOS(ctx context.Context, posID string) (*Bill, error)
	UpdateStatus(ctx context.Context, billID, status, updatedBy string) error
	UpdateTimestamp(ctx context.Context, billID, updatedBy string) error
	GetItemByPartCode(ctx context.Context, billID, partCode, addressCode string) (*BillDetail, error)
	AddItem(ctx context.Context, detail *BillDetail) error
	UpdateItemQty(ctx context.Context, billID, partCode, addressCode string, qty int) error
	RemoveItem(ctx context.Context, billID, partCode, addressCode string) error
	AddDiscount(ctx context.Context, discount *BillDiscountDetail) error
	RemoveDiscount(ctx context.Context, billID, promotionCode string) error
	GetDiscountByCode(ctx context.Context, billID, promotionCode string) (*BillDiscountDetail, error)
	GetAllItems(ctx context.Context, billID string) ([]BillDetail, error)
	GetAllDiscounts(ctx context.Context, billID string) ([]BillDiscountDetail, error)
	UpdateAmounts(ctx context.Context, billID string, purchaseAmount, totalDiscount, totalAmount, vatAmount, xvatAmount float64) error
	UpdatePayment(ctx context.Context, billID, paymentMethod, paymentRef, updatedBy string) error
	Delete(ctx context.Context, billID string) error
}

