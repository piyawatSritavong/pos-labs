package repository

import (
	"context"
	"errors"
)

type PartDetail struct {
	Code            string
	BarCode         string
	CategoryID      string
	CategoryLabel   string
	CategoryLabelTH string
	UnitID          string
	UnitLabel       string
	UnitLabelTH     string
	Name            string
	NameTH          string
	ReceiptName     string
	Details         string
	Cost            float64
	Price           float64
	Image           string
	IsActive        bool
	TotalStock      int
}

type PartSummary struct {
	Code            string
	BarCode         string
	CategoryID      string
	CategoryLabel   string
	CategoryLabelTH string
	UnitID          string
	UnitLabel       string
	UnitLabelTH     string
	Name            string
	NameTH          string
	ReceiptName     string
	Price           float64
	IsActive        bool
	TotalStock      int
}
type PartAddress struct {
	Code         string
	PartCode     string
	StoreID      string
	StoreLabel   string
	StoreLabelTH string
	Shelf        string
	Qty          int
	Min          int
	Max          int
	Rop          int
	Remarks      string
	IsDefault    bool
}

type PartRepository interface {
	GetPartDetail(ctx context.Context, code string, branchID *string) (*PartDetail, []PartAddress, error)
	ListParts(ctx context.Context, limit, offset int, branchID *string) ([]PartSummary, error)
	GetPartByBarcode(ctx context.Context, barcode string, branchID string) (*PartDetail, []PartAddress, error)
	CheckPartExistsInBranch(ctx context.Context, partCode, branchID string) (bool, error)
	SearchParts(ctx context.Context, query string, categoryID *string, isActive *bool, branchID *string, limit, offset int) ([]PartDetail, error)
}

var ErrNotFound = errors.New("not found")

func IsNotFoundError(err error) bool {
	return errors.Is(err, ErrNotFound)
}
