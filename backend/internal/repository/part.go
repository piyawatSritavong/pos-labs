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
	MinPrice        float64
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
	Cost            float64
	Price           float64
	MinPrice        float64
	IsActive        bool
	TotalStock      int
	// ReorderPoint is summed across the part's addresses. Used for
	// the per-product low-stock alert (low when TotalStock <= ReorderPoint).
	ReorderPoint int
}
type PartAddress struct {
	Code         string
	PartCode     string
	StoreID      string
	StoreLabel   string
	StoreLabelTH string
	Shelf        string
	Qty          int
	Rop          int
	Remarks      string
	IsDefault    bool
}

type PartRepository interface {
	GetPartDetail(ctx context.Context, code string, branchID *string) (*PartDetail, []PartAddress, error)
	ListParts(ctx context.Context, limit, offset int, branchID *string) ([]PartSummary, error)
	GetPartByBarcode(ctx context.Context, barcode string, branchID string) (*PartDetail, []PartAddress, error)
	CheckPartExistsInBranch(ctx context.Context, partCode, branchID string) (bool, error)
	SearchParts(ctx context.Context, query string, categoryID *string, isActive *bool, branchID, storeID *string, saleableOnly bool, limit, offset int) ([]PartDetail, error)
	// CountParts returns the total number of parts matching the same filters as
	// SearchParts (ignoring limit/offset) — used for page-jump pagination.
	CountParts(ctx context.Context, query string, categoryID *string, isActive *bool, branchID, storeID *string, saleableOnly bool) (int, error)
	// GetAddressesByPartCodes loads addresses for many parts in a single query
	// (avoids N+1 when building search/list responses). Result is keyed by part code.
	GetAddressesByPartCodes(ctx context.Context, codes []string, branchID *string) (map[string][]PartAddress, error)
	CreatePart(ctx context.Context, p PartInput) error
	UpdatePart(ctx context.Context, code string, p PartInput) error
	// DeletePart physically deletes an unreferenced part. Parts used by bills,
	// transfers, or stock counts are archived so historical documents remain
	// readable. The returned mode is "deleted" or "archived".
	DeletePart(ctx context.Context, code string) (string, error)
	// GenerateNextPartCode returns the next free running code in the "P%04d"
	// convention (P0001, P0002, …). The same value doubles as the default
	// barcode (Code128 renders the code directly — see migration 0012).
	GenerateNextPartCode(ctx context.Context) (string, error)
	// ImportParts creates many products and their warehouse rows in one
	// transaction. Rows whose code or name is already taken are reported as
	// conflicts and nothing is written — a half-applied spreadsheet is worse
	// than a rejected one.
	ImportParts(ctx context.Context, rows []PartImportRow) (PartImportResult, error)
}

// PartImportRow is one product from an uploaded spreadsheet. SheetRow travels
// with it so conflicts can be reported against the row the user sees. An empty
// Code means "assign the next running code".
type PartImportRow struct {
	SheetRow int
	Code     string
	Name     string
	BarCode  string
	UnitID   string
	Shelf    string
	Details  string
	Price    float64
	Cost     float64
	MinPrice float64
	Qty      int
}

// PartImportConflict is a row that collides with the existing catalog.
type PartImportConflict struct {
	SheetRow int    `json:"row"`
	Column   string `json:"column,omitempty"`
	Message  string `json:"message"`
}

// PartImportResult reports what an import did. When Conflicts is non-empty
// nothing was written and Created is zero.
type PartImportResult struct {
	Created   int
	Codes     []string
	Conflicts []PartImportConflict
}

// PartInput is the writable shape for creating/updating a part. UnitID and
// CategoryID are matched against the master tables and stored as NULL when they
// don't reference an existing row (keeps the FK happy for free-text input).
type PartInput struct {
	Code       string
	Name       string
	NameTH     string
	BarCode    string
	UnitID     string
	CategoryID string
	Price      float64
	Cost       float64
	MinPrice   float64
	Details    string
	IsActive   bool
}

var ErrNotFound = errors.New("not found")

func IsNotFoundError(err error) bool {
	return errors.Is(err, ErrNotFound)
}
