package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type stubAddressRepository struct {
	items []repository.Address
}

func (r *stubAddressRepository) GetByCode(context.Context, string) (*repository.Address, error) {
	if len(r.items) == 0 {
		return nil, repository.ErrNotFound
	}
	item := r.items[0]
	return &item, nil
}
func (r *stubAddressRepository) List(context.Context, int, int) ([]repository.Address, error) {
	return r.items, nil
}
func (r *stubAddressRepository) Search(context.Context, string, string, *string, int, int) ([]repository.Address, error) {
	return r.items, nil
}
func (r *stubAddressRepository) Count(context.Context, string, string, *string) (int, error) {
	return len(r.items), nil
}
func (*stubAddressRepository) Create(context.Context, *repository.Address) error { return nil }
func (*stubAddressRepository) Update(context.Context, *repository.Address) error { return nil }
func (*stubAddressRepository) Delete(context.Context, string) error              { return nil }
func (*stubAddressRepository) DecreaseInventory(context.Context, string, int) (bool, error) {
	return true, nil
}
func (*stubAddressRepository) IncreaseInventory(context.Context, string, int) error { return nil }

func TestAddressListExposesROPWithoutRemovedMinMax(t *testing.T) {
	gin.SetMode(gin.TestMode)
	handler := NewAddressHandler(&stubAddressRepository{items: []repository.Address{{
		Code: "ADDR-P1-main", PartCode: "P1", StoreID: "main", BranchID: "00000",
		Qty: 12, Rop: 5, PartName: "สินค้า", StoreName: "คลังหลัก",
	}}})
	recorder := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(recorder)
	c.Request = httptest.NewRequest(http.MethodGet, "/addresses", nil)
	c.Set("user", &repository.User{RoleID: "role.admin"})

	handler.List(c)

	if recorder.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", recorder.Code, recorder.Body.String())
	}
	var response struct {
		Addresses []map[string]any `json:"addresses"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
		t.Fatal(err)
	}
	if len(response.Addresses) != 1 || response.Addresses[0]["rop"] != float64(5) {
		t.Fatalf("unexpected response: %s", recorder.Body.String())
	}
	if _, exists := response.Addresses[0]["min"]; exists {
		t.Fatal("address response must not expose min")
	}
	if _, exists := response.Addresses[0]["max"]; exists {
		t.Fatal("address response must not expose max")
	}
}
