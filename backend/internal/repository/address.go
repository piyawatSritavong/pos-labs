package repository

import (
	"context"
)

type Address struct {
	Code     string
	PartCode string
	StoreID  string
	Shelf    string
	Qty      int
	Min      int
	Max      int
	Rop      int
	Remarks  string
}

type AddressRepository interface {
	GetByCode(ctx context.Context, code string) (*Address, error)
	List(ctx context.Context, limit, offset int) ([]Address, error)
	Create(ctx context.Context, address *Address) error
	Update(ctx context.Context, address *Address) error
	Delete(ctx context.Context, code string) error
	DecreaseInventory(ctx context.Context, addressCode string, qty int) (bool, error)
	IncreaseInventory(ctx context.Context, addressCode string, qty int) error
}
