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

type stubPurchaseOrderRepository struct {
	called    bool
	items     []repository.PurchaseOrderInputItem
	deletedID string
	deleteErr error
}

func (s *stubPurchaseOrderRepository) Create(_ context.Context, requestID string, orderDate time.Time, notes, userID string, items []repository.PurchaseOrderInputItem) (*repository.PurchaseOrder, []repository.PurchaseOrderItem, bool, error) {
	s.called = true
	s.items = append([]repository.PurchaseOrderInputItem(nil), items...)
	order := &repository.PurchaseOrder{
		ID: "PO20260804000001", RequestID: requestID, OrderDate: orderDate,
		Notes: notes, CreatedBy: userID, CreatedAt: time.Now().UTC(),
	}
	return order, nil, true, nil
}

func (s *stubPurchaseOrderRepository) GetByID(context.Context, string) (*repository.PurchaseOrder, []repository.PurchaseOrderItem, error) {
	return nil, nil, repository.ErrNotFound
}

func (s *stubPurchaseOrderRepository) List(context.Context, int, int) ([]repository.PurchaseOrder, error) {
	return nil, nil
}

func (s *stubPurchaseOrderRepository) Delete(_ context.Context, id string) error {
	s.deletedID = id
	return s.deleteErr
}

func TestPurchaseOrderRejectsPriceFloorAboveSalePrice(t *testing.T) {
	gin.SetMode(gin.TestMode)
	repo := &stubPurchaseOrderRepository{}
	handler := NewPurchaseOrderHandler(repo)
	recorder := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(recorder)
	c.Request = httptest.NewRequest(http.MethodPost, "/purchase-orders", strings.NewReader(`{
		"requestId":"REQ-1","orderDate":"2026-08-04","items":[
			{"partName":"ทดสอบ","qty":1,"cost":60,"price":100,"minPrice":101}
		]
	}`))
	c.Request.Header.Set("Content-Type", "application/json")
	c.Set("user", &repository.User{ID: "admin", RoleID: "role.admin", IsSuperuser: true})

	handler.Create(c)

	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d: %s", recorder.Code, recorder.Body.String())
	}
	if repo.called {
		t.Fatal("repository must not be called for an invalid line")
	}
}

func TestPurchaseOrderCreateIsAdminOnly(t *testing.T) {
	gin.SetMode(gin.TestMode)
	repo := &stubPurchaseOrderRepository{}
	handler := NewPurchaseOrderHandler(repo)
	recorder := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(recorder)
	c.Request = httptest.NewRequest(http.MethodPost, "/purchase-orders", strings.NewReader(`{"requestId":"REQ-2","items":[]}`))
	c.Request.Header.Set("Content-Type", "application/json")
	c.Set("user", &repository.User{ID: "pos1", RoleID: "role.cashier"})

	handler.Create(c)

	if recorder.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d: %s", recorder.Code, recorder.Body.String())
	}
}

func TestPurchaseOrderDeleteIsAdminOnly(t *testing.T) {
	gin.SetMode(gin.TestMode)
	repo := &stubPurchaseOrderRepository{}
	handler := NewPurchaseOrderHandler(repo)
	recorder := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(recorder)
	c.Request = httptest.NewRequest(http.MethodDelete, "/purchase-orders/PO1", nil)
	c.Params = gin.Params{{Key: "id", Value: "PO1"}}
	c.Set("user", &repository.User{ID: "pos1", RoleID: "role.cashier"})

	handler.Delete(c)

	if recorder.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d: %s", recorder.Code, recorder.Body.String())
	}
	if repo.deletedID != "" {
		t.Fatal("repository must not be called by cashier")
	}
}

func TestPurchaseOrderDeleteRemovesDocumentOnly(t *testing.T) {
	gin.SetMode(gin.TestMode)
	repo := &stubPurchaseOrderRepository{}
	handler := NewPurchaseOrderHandler(repo)
	recorder := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(recorder)
	c.Request = httptest.NewRequest(http.MethodDelete, "/purchase-orders/PO1", nil)
	c.Params = gin.Params{{Key: "id", Value: "PO1"}}
	c.Set("user", &repository.User{ID: "admin", RoleID: "role.admin", IsSuperuser: true})

	handler.Delete(c)

	if recorder.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", recorder.Code, recorder.Body.String())
	}
	if repo.deletedID != "PO1" {
		t.Fatalf("expected PO1 to be deleted, got %q", repo.deletedID)
	}
	if !strings.Contains(recorder.Body.String(), `"mode":"document_only"`) {
		t.Fatalf("expected document-only response, got %s", recorder.Body.String())
	}
}

func TestPurchaseOrderDeleteMissingReturns404(t *testing.T) {
	gin.SetMode(gin.TestMode)
	repo := &stubPurchaseOrderRepository{deleteErr: repository.ErrNotFound}
	handler := NewPurchaseOrderHandler(repo)
	recorder := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(recorder)
	c.Request = httptest.NewRequest(http.MethodDelete, "/purchase-orders/missing", nil)
	c.Params = gin.Params{{Key: "id", Value: "missing"}}
	c.Set("user", &repository.User{ID: "admin", RoleID: "role.admin", IsSuperuser: true})

	handler.Delete(c)

	if recorder.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d: %s", recorder.Code, recorder.Body.String())
	}
}
