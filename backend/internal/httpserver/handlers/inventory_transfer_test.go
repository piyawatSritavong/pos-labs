package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type stubInventoryTransferRepository struct {
	transfer *repository.InventoryTransfer
	items    []repository.InventoryTransferItem
}

func (r *stubInventoryTransferRepository) GenerateTransferID(ctx context.Context) (string, error) {
	return "TRTEST000001", nil
}

func (r *stubInventoryTransferRepository) Create(ctx context.Context, transfer *repository.InventoryTransfer, items []repository.InventoryTransferItem) error {
	transferCopy := *transfer
	r.transfer = &transferCopy
	r.items = append([]repository.InventoryTransferItem(nil), items...)
	return nil
}

func (r *stubInventoryTransferRepository) GetByID(ctx context.Context, id string) (*repository.InventoryTransfer, []repository.InventoryTransferItem, error) {
	if r.transfer == nil || r.transfer.ID != id {
		return nil, nil, repository.ErrNotFound
	}
	items := append([]repository.InventoryTransferItem(nil), r.items...)
	return r.transfer, items, nil
}

func (r *stubInventoryTransferRepository) List(ctx context.Context, limit, offset int, status, fromBranchID, toBranchID *string) ([]repository.InventoryTransfer, error) {
	return nil, nil
}

func (r *stubInventoryTransferRepository) UpdateStatus(ctx context.Context, id, status, userID string, timestamp time.Time) error {
	return nil
}

func (r *stubInventoryTransferRepository) UpdateItemsDispatched(ctx context.Context, transferID string, items []repository.InventoryTransferItem) error {
	return nil
}

func (r *stubInventoryTransferRepository) UpdateItemsReceived(ctx context.Context, transferID string, items []repository.InventoryTransferItem) error {
	return nil
}

func TestInventoryTransferCreateAllowsSameBranch(t *testing.T) {
	t.Helper()
	gin.SetMode(gin.TestMode)

	repo := &stubInventoryTransferRepository{}
	handler := NewInventoryTransferHandler(repo, nil)

	body := `{
		"fromBranchId":"00000",
		"toBranchId":"00000",
		"notes":"same branch transfer",
		"items":[{"partCode":"P0005","requestedQty":10}]
	}`

	recorder := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(recorder)
	c.Request = httptest.NewRequest(http.MethodPost, "/transfers", strings.NewReader(body))
	c.Request.Header.Set("Content-Type", "application/json")
	c.Set("user", &repository.User{
		ID:     "user.hqmanager",
		RoleID: "role.hq_manager",
	})

	handler.Create(c)

	if recorder.Code != http.StatusCreated {
		t.Fatalf("expected status %d, got %d with body %s", http.StatusCreated, recorder.Code, recorder.Body.String())
	}
	if repo.transfer == nil {
		t.Fatal("expected transfer to be created")
	}
	if repo.transfer.FromBranchID != "00000" || repo.transfer.ToBranchID != "00000" {
		t.Fatalf("expected same-branch transfer to be persisted, got from=%q to=%q", repo.transfer.FromBranchID, repo.transfer.ToBranchID)
	}

	var response struct {
		Data struct {
			FromBranchID string `json:"fromBranchId"`
			ToBranchID   string `json:"toBranchId"`
		} `json:"data"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	if response.Data.FromBranchID != "00000" || response.Data.ToBranchID != "00000" {
		t.Fatalf("expected response to keep same branches, got from=%q to=%q", response.Data.FromBranchID, response.Data.ToBranchID)
	}
}
