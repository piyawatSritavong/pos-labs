package repository

import "context"

// StoreListItem is a store row enriched with its branch name, used by the
// canonical GET /stores list that both the Parts and Addresses pages consume so
// their store dropdowns always match.
type StoreListItem struct {
	ID           string
	BranchID     string
	BranchName   string
	BranchNameTH string
	Label        string
	LabelTH      string
	IsDefault    bool
}

// StoreInput is the writable shape for creating a store (the "เพิ่มคลังใหม่"
// button on the Addresses page).
type StoreInput struct {
	ID        string
	BranchID  string
	Label     string
	LabelTH   string
	IsDefault bool
}

type StoreRepository interface {
	// ListStores returns every store with its branch name, ordered by branch
	// then default-first.
	ListStores(ctx context.Context) ([]StoreListItem, error)
	// CreateStore inserts a store_master row and links it to its branch via
	// branch_store (both in one transaction).
	CreateStore(ctx context.Context, s StoreInput) error
}
