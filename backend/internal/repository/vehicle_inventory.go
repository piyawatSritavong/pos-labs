package repository

import (
	"context"
	"time"
)

type VehicleInventoryItem struct {
	PartCode         string
	PartName         string
	PartNameTH       string
	BarCode          string
	CurrentQty       int
	ReceivedQty      int
	NetSoldQty       int
	Price            float64
	CurrentSaleValue float64
}

type VehicleInventoryRepository interface {
	List(ctx context.Context, posID string, start, end time.Time) ([]VehicleInventoryItem, error)
}
