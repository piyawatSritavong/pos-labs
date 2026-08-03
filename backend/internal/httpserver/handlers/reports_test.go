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

type stubReportRepository struct {
	addresses []repository.Address
}

func (r stubReportRepository) GetBillsByDate(context.Context, time.Time) ([]repository.Bill, error) {
	return nil, nil
}

func (r stubReportRepository) GetBillsWithItemsByDate(context.Context, time.Time) ([]repository.BillWithItems, error) {
	return nil, nil
}

func (r stubReportRepository) GetBillsByDateRange(context.Context, time.Time, time.Time) ([]repository.Bill, error) {
	return nil, nil
}

func (r stubReportRepository) GetBillsWithItemsByDateRange(context.Context, time.Time, time.Time) ([]repository.BillWithItems, error) {
	return nil, nil
}

func (r stubReportRepository) GetAllParts(context.Context) ([]repository.PartMaster, error) {
	return nil, nil
}

func (r stubReportRepository) GetAllAddresses(context.Context) ([]repository.Address, error) {
	return r.addresses, nil
}

func (r stubReportRepository) GetIncomeReport(context.Context, time.Time, time.Time) (*repository.IncomeReport, error) {
	return &repository.IncomeReport{}, nil
}

func TestInventoryCSVExposesOnlyROPThreshold(t *testing.T) {
	gin.SetMode(gin.TestMode)
	handler := NewReportsHandler(stubReportRepository{addresses: []repository.Address{{
		Code:     "ADDR1",
		PartCode: "P0001",
		StoreID:  "main",
		Qty:      12,
		Rop:      4,
	}}})
	recorder := httptest.NewRecorder()
	ctx, _ := gin.CreateTestContext(recorder)
	ctx.Request = httptest.NewRequest(http.MethodGet, "/reports/inventory", nil)

	handler.InventoryReport(ctx)

	if recorder.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", recorder.Code, recorder.Body.String())
	}
	body := strings.TrimPrefix(recorder.Body.String(), "\ufeff")
	header := strings.SplitN(body, "\n", 2)[0]
	if strings.TrimSuffix(header, "\r") != "code,part_code,store_id,branch_id,shelf,qty,rop,remarks,cost,price,min_price" {
		t.Fatalf("unexpected inventory header %q", header)
	}
	if strings.Contains(header, "min_stock") || strings.Contains(header, ",min,") || strings.Contains(header, ",max,") {
		t.Fatalf("inventory CSV must not expose removed min/max thresholds: %q", header)
	}
}
