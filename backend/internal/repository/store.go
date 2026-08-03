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
	LocationType string
}

type StoreRepository interface {
	// ListStores returns user-facing warehouse locations only. Vehicle stock
	// locations are deliberately exposed through the vehicle inventory API.
	ListStores(ctx context.Context) ([]StoreListItem, error)
}
