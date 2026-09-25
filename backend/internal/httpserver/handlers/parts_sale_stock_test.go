package handlers

import (
	"testing"

	"backend/internal/repository"
)

func TestPOSSearchSaleStockSkipsEmptyDefaultAddress(t *testing.T) {
	addresses := []repository.PartAddress{
		{Code: "DEFAULT-EMPTY", Qty: 0, IsDefault: true},
		{Code: "SELLABLE", Qty: 7},
	}

	code, qty := posSearchSaleStock(addresses)
	if code != "SELLABLE" || qty != 7 {
		t.Fatalf("posSearchSaleStock() = (%q, %d), want (%q, %d)", code, qty, "SELLABLE", 7)
	}
}

func TestPOSSearchSaleStockReturnsSoldOutWhenNoAddressHasStock(t *testing.T) {
	addresses := []repository.PartAddress{
		{Code: "DEFAULT-EMPTY", Qty: 0, IsDefault: true},
		{Code: "OTHER-EMPTY", Qty: 0},
	}

	code, qty := posSearchSaleStock(addresses)
	if code != "" || qty != 0 {
		t.Fatalf("posSearchSaleStock() = (%q, %d), want empty sold-out result", code, qty)
	}
}
