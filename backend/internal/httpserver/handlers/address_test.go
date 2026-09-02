package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
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

// The stock page now reads every store so an admin can see what is on the vans.
// Writing is a different matter: van stock moves through a transfer or a stock
// count, and this gate is what lets the read side be widened safely.
func TestAddressUpdateStillRefusesAnyStoreButTheWarehouse(t *testing.T) {
	gin.SetMode(gin.TestMode)
	handler := NewAddressHandler(&stubAddressRepository{})

	update := func(storeID string) *httptest.ResponseRecorder {
		recorder := httptest.NewRecorder()
		c, _ := gin.CreateTestContext(recorder)
		body := `{"partCode":"P0557","storeId":"` + storeID + `","qty":12,"rop":0}`
		c.Request = httptest.NewRequest(http.MethodPut, "/addresses/ADDR-1", strings.NewReader(body))
		c.Request.Header.Set("Content-Type", "application/json")
		c.Params = gin.Params{{Key: "code", Value: "ADDR-1"}}
		c.Set("user", &repository.User{RoleID: "role.admin"})
		handler.Update(c)
		return recorder
	}

	for _, store := range []string{"vehicle_POS001", "store_00001"} {
		recorder := update(store)
		if recorder.Code != http.StatusBadRequest {
			t.Fatalf("%s: expected 400, got %d: %s", store, recorder.Code, recorder.Body.String())
		}
		var response struct {
			Error string `json:"error"`
		}
		_ = json.Unmarshal(recorder.Body.Bytes(), &response)
		if response.Error != "invalid_warehouse" {
			t.Fatalf("%s: expected invalid_warehouse, got %q", store, response.Error)
		}
	}

	if recorder := update("main"); recorder.Code != http.StatusOK {
		t.Fatalf("the warehouse must stay editable, got %d: %s", recorder.Code, recorder.Body.String())
	}
}
