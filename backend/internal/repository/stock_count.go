package repository

import (
	"context"
	"errors"
	"time"
)

type StockCount struct {
	ID          string
	BranchID    string
	StoreID     string
	CountedBy   string
	Status      string // "draft", "submitted"
	Notes       string
	CreatedAt   time.Time
	SubmittedAt *time.Time
}

type StockCountItem struct {
	CountID    string
	PartCode   string
	SystemQty  int
	CountedQty int
	// enriched (not stored)
	PartName   string
	PartNameTH string
	Variance   int // CountedQty - SystemQty
}

type StockCountRepository interface {
	GenerateStockCountID(ctx context.Context) (string, error)
	Create(ctx context.Context, count *StockCount) error // snapshots system_qty from address_master
	GetByID(ctx context.Context, id string) (*StockCount, []StockCountItem, error)
	List(ctx context.Context, limit, offset int, branchID, status *string) ([]StockCount, error)
	UpdateItemCounts(ctx context.Context, countID string, items []StockCountItem) error
	Submit(ctx context.Context, countID string, items []StockCountItem) error
}

var (
	ErrInvalidStockCountItems = errors.New("invalid stock count items")
	ErrInvalidStockCountState = errors.New("invalid stock count state")
)
