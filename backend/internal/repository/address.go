package repository

import (
	"context"
)

type Address struct {
	Code     string
	PartCode string
	StoreID  string
	BranchID string
	Shelf    string
	Qty      int
	Min      int
	Max      int
	Rop      int
	Remarks  string
	// Populated by the List query via LEFT JOIN. Empty string when not joined
	// (Create/Update/Get-by-code use a non-joined query and leave these blank).
	PartName  string
	StoreName string
	Cost      float64
	Price     float64
	MinPrice  float64
}

type AddressRepository interface {
	GetByCode(ctx context.Context, code string) (*Address, error)
	List(ctx context.Context, limit, offset int) ([]Address, error)
	// Search lists addresses with optional q (part code/name, store name) and
	// storeID filters plus paging — used by the Addresses page for server-side
	// search instead of fetching the whole catalog.
	Search(ctx context.Context, q, storeID string, branchID *string, limit, offset int) ([]Address, error)
	// Count returns the number of addresses matching the same q/storeID filters
	// as Search — used for page-jump pagination on the Addresses page.
	Count(ctx context.Context, q, storeID string, branchID *string) (int, error)
	Create(ctx context.Context, address *Address) error
	Update(ctx context.Context, address *Address) error
	Delete(ctx context.Context, code string) error
	DecreaseInventory(ctx context.Context, addressCode string, qty int) (bool, error)
	IncreaseInventory(ctx context.Context, addressCode string, qty int) error
}
