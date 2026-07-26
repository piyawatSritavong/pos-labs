package handlers

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"backend/internal/repository"

	"github.com/gin-gonic/gin"
)

func TestPaymentMethodRejectsUnsupportedValue(t *testing.T) {
	if _, _, err := validateAndSerializePayment("bitcoin", "", nil, 100); err == nil || err.Error() != "unsupported_payment_method" {
		t.Fatalf("expected unsupported_payment_method, got %v", err)
	}
	method, _, err := validateAndSerializePayment("qr", "", nil, 100)
	if err != nil || method != "bank" {
		t.Fatalf("expected qr to normalize to bank, got method=%q err=%v", method, err)
	}
}

func TestValidateLinePriceBoundaries(t *testing.T) {
	tests := []struct {
		total   float64
		wantErr string
	}{
		{89.99, "price_below_minimum"},
		{90, ""},
		{100, ""},
		{100.01, "price_above_catalog"},
	}
	for _, tt := range tests {
		_, _, got := validateLinePrice(tt.total, 1, 90, 100)
		if got != tt.wantErr {
			t.Errorf("total %.2f: got %q, want %q", tt.total, got, tt.wantErr)
		}
	}
}

func TestOperationalAccessMatrix(t *testing.T) {
	gin.SetMode(gin.TestMode)
	makeContext := func(user *repository.User, branch, pos string) *gin.Context {
		c, _ := gin.CreateTestContext(httptest.NewRecorder())
		c.Set("user", user)
		c.Set("branch_id", branch)
		c.Set("pos_id", pos)
		return c
	}
	admin := makeContext(&repository.User{RoleID: "role.admin"}, "00000", "POS003")
	if !canReadOperationalRecord(admin, "00002", "POS002") {
		t.Fatal("admin must read every operational record")
	}
	pos1 := makeContext(&repository.User{ID: "pos1", RoleID: "role.cashier"}, "00001", "POS001")
	if !canReadOperationalRecord(pos1, "00001", "POS001") {
		t.Fatal("pos1 must read its own record")
	}
	if canReadOperationalRecord(pos1, "00002", "POS002") {
		t.Fatal("pos1 must not read pos2 record")
	}
	hq := makeContext(&repository.User{RoleID: "role.hq_manager"}, "00001", "POS001")
	if !canReadOperationalRecord(hq, "00001", "POS999") {
		t.Fatal("HQ must read records in its current branch")
	}
	if canReadOperationalRecord(hq, "00002", "POS002") {
		t.Fatal("HQ must not read an unassigned branch")
	}
}

type memoryStockCountRepository struct {
	count *repository.StockCount
	items []repository.StockCountItem
}

func (r *memoryStockCountRepository) GenerateStockCountID(context.Context) (string, error) {
	return "SCTEST001", nil
}
func (r *memoryStockCountRepository) Create(_ context.Context, count *repository.StockCount) error {
	copyCount := *count
	r.count = &copyCount
	r.items = []repository.StockCountItem{{CountID: count.ID, PartCode: "P0001", SystemQty: 5}}
	return nil
}
func (r *memoryStockCountRepository) GetByID(_ context.Context, id string) (*repository.StockCount, []repository.StockCountItem, error) {
	if r.count == nil || r.count.ID != id {
		return nil, nil, repository.ErrNotFound
	}
	return r.count, append([]repository.StockCountItem(nil), r.items...), nil
}
func (r *memoryStockCountRepository) List(context.Context, int, int, *string, *string) ([]repository.StockCount, error) {
	if r.count == nil {
		return nil, nil
	}
	return []repository.StockCount{*r.count}, nil
}
func (r *memoryStockCountRepository) UpdateItemCounts(_ context.Context, id string, items []repository.StockCountItem) error {
	r.items = append([]repository.StockCountItem(nil), items...)
	return nil
}
func (r *memoryStockCountRepository) Submit(_ context.Context, id string) error {
	r.count.Status = "submitted"
	now := time.Now().UTC()
	r.count.SubmittedAt = &now
	return nil
}

func stockTestContext(method, target, body string) (*gin.Context, *httptest.ResponseRecorder) {
	recorder := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(recorder)
	c.Request = httptest.NewRequest(method, target, strings.NewReader(body))
	c.Request.Header.Set("Content-Type", "application/json")
	c.Set("user", &repository.User{ID: "pos1", RoleID: "role.cashier"})
	c.Set("branch_id", "00001")
	c.Set("pos_id", "POS001")
	return c, recorder
}

func TestCashierStockCountHappyPath(t *testing.T) {
	gin.SetMode(gin.TestMode)
	repo := &memoryStockCountRepository{}
	handler := NewStockCountHandler(repo, stubBranchRepository{})

	createCtx, createRecorder := stockTestContext(http.MethodPost, "/stock-counts", `{"branchId":"00001","storeId":"main","notes":"SMOKE"}`)
	handler.Create(createCtx)
	if createRecorder.Code != http.StatusCreated {
		t.Fatalf("create got %d: %s", createRecorder.Code, createRecorder.Body.String())
	}

	updateCtx, updateRecorder := stockTestContext(http.MethodPut, "/stock-counts/SCTEST001/items", `{"items":[{"partCode":"P0001","countedQty":5}]}`)
	updateCtx.Params = gin.Params{{Key: "id", Value: "SCTEST001"}}
	handler.UpdateItems(updateCtx)
	if updateRecorder.Code != http.StatusOK {
		t.Fatalf("update got %d: %s", updateRecorder.Code, updateRecorder.Body.String())
	}

	submitCtx, submitRecorder := stockTestContext(http.MethodPut, "/stock-counts/SCTEST001/submit", `{}`)
	submitCtx.Params = gin.Params{{Key: "id", Value: "SCTEST001"}}
	handler.Submit(submitCtx)
	if submitRecorder.Code != http.StatusOK || repo.count.Status != "submitted" {
		t.Fatalf("submit got %d status=%q: %s", submitRecorder.Code, repo.count.Status, submitRecorder.Body.String())
	}
}

func TestProfitResult(t *testing.T) {
	if profitResult(-0.01) != "loss" || profitResult(0) != "profit" || profitResult(1) != "profit" {
		t.Fatal("profit/loss classification is incorrect")
	}
}
