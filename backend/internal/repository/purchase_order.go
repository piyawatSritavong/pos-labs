package repository

import (
	"context"
	"time"
)

type PurchaseOrder struct {
	ID             string
	RequestID      string
	OrderDate      time.Time
	Notes          string
	CreatedBy      string
	CreatedAt      time.Time
	TotalCost      float64
	TotalSaleValue float64
}

type PurchaseOrderItem struct {
	LineNo        int
	PartCode      string
	PartName      string
	BarCode       string
	Qty           int
	Cost          float64
	Price         float64
	MinPrice      float64
	LineCost      float64
	LineSaleValue float64
}

type PurchaseOrderInputItem struct {
	PartCode string
	PartName string
	BarCode  string
	Qty      int
	Cost     float64
	Price    float64
	MinPrice float64
}

type PurchaseOrderRepository interface {
	Create(ctx context.Context, requestID string, orderDate time.Time, notes, userID string, items []PurchaseOrderInputItem) (*PurchaseOrder, []PurchaseOrderItem, bool, error)
	GetByID(ctx context.Context, id string) (*PurchaseOrder, []PurchaseOrderItem, error)
	List(ctx context.Context, limit, offset int) ([]PurchaseOrder, error)
	Delete(ctx context.Context, id string) error
}
