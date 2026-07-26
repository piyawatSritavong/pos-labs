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
	audits   []string
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

func (r *stubInventoryTransferRepository) List(ctx context.Context, limit, offset int, status, fromBranchID, toBranchID, transferMode, createdBy *string) ([]repository.InventoryTransfer, error) {
	return nil, nil
}

func (r *stubInventoryTransferRepository) UpdateItems(ctx context.Context, transferID string, items []repository.InventoryTransferItem) error {
	r.items = append([]repository.InventoryTransferItem(nil), items...)
	return nil
}

func (r *stubInventoryTransferRepository) UpdateStatus(ctx context.Context, id, status, userID string, timestamp time.Time) error {
	if r.transfer != nil && r.transfer.ID == id {
		r.transfer.Status = status
		if status == "review" {
			r.transfer.SubmittedAt = &timestamp
			r.transfer.SubmittedBy = userID
		}
	}
	return nil
}

func (r *stubInventoryTransferRepository) UpdateItemsDispatched(ctx context.Context, transferID string, items []repository.InventoryTransferItem) error {
	return nil
}

func (r *stubInventoryTransferRepository) UpdateItemsReceived(ctx context.Context, transferID string, items []repository.InventoryTransferItem) error {
	return nil
}

func (r *stubInventoryTransferRepository) CompletePosRestock(ctx context.Context, transferID, userID string, timestamp time.Time) error {
	return nil
}

func (r *stubInventoryTransferRepository) LogAudit(ctx context.Context, transferID, action, actorID, notes string) error {
	r.audits = append(r.audits, action)
	return nil
}

type stubBranchRepository struct{}

func (r stubBranchRepository) GetByID(ctx context.Context, id string) (*repository.Branch, error) {
	return &repository.Branch{BranchID: id}, nil
}

func (r stubBranchRepository) List(ctx context.Context, limit, offset int) ([]repository.Branch, error) {
	return nil, nil
}

func (r stubBranchRepository) NextID(ctx context.Context) (string, error) {
	return "00003", nil
}

func (r stubBranchRepository) Create(ctx context.Context, branch *repository.Branch) error {
	if branch.BranchID == "" {
		branch.BranchID = "00003"
	}
	return nil
}

func (r stubBranchRepository) Update(ctx context.Context, branch *repository.Branch) error {
	return nil
}

func (r stubBranchRepository) Delete(ctx context.Context, id string) error {
	return nil
}

func (r stubBranchRepository) Count(ctx context.Context) (int, error) {
	return 0, nil
}

func (r stubBranchRepository) GetStoresByBranchID(ctx context.Context, branchID string) ([]repository.Store, error) {
	return []repository.Store{{ID: "main", BranchID: branchID, IsDefault: true}}, nil
}

type stubPOSRepository struct {
	pos *repository.POS
}

func (r stubPOSRepository) GetFirstActiveByBranch(ctx context.Context, branchID string) (*repository.POS, error) {
	if r.pos == nil || (branchID != "" && r.pos.BranchID != branchID) {
		return nil, repository.ErrNotFound
	}
	return r.pos, nil
}

func (r stubPOSRepository) GetByID(ctx context.Context, id string) (*repository.POS, error) {
	if r.pos == nil || r.pos.POSID != id {
		return nil, repository.ErrNotFound
	}
	return r.pos, nil
}

func (r stubPOSRepository) List(ctx context.Context, limit, offset int) ([]repository.POS, error) {
	return nil, nil
}

func (r stubPOSRepository) Create(ctx context.Context, pos *repository.POS) error {
	return nil
}

func (r stubPOSRepository) Delete(ctx context.Context, id string) error {
	return nil
}

func (r stubPOSRepository) GetSecret(ctx context.Context, id string) (string, error) {
	return "", nil
}

func (r stubPOSRepository) RefreshSecret(ctx context.Context, id string) (string, error) {
	return "", nil
}

func (r stubPOSRepository) ToggleActive(ctx context.Context, id string) error {
	return nil
}

func TestInventoryTransferCreateAllowsSameBranch(t *testing.T) {
	t.Helper()
	gin.SetMode(gin.TestMode)

	repo := &stubInventoryTransferRepository{}
	handler := NewInventoryTransferHandler(repo, nil, nil)

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

func TestCreatePosRestockCreatesDraft(t *testing.T) {
	gin.SetMode(gin.TestMode)

	repo := &stubInventoryTransferRepository{}
	handler := NewInventoryTransferHandler(
		repo,
		stubBranchRepository{},
		stubPOSRepository{pos: &repository.POS{
			POSID:          "POS001",
			BranchID:       "00000",
			VehicleStoreID: "vehicle_POS001",
			IsActive:       true,
		}},
	)

	body := `{
		"notes":"self pick",
		"items":[{"partCode":"P0001","requestedQty":2}]
	}`
	recorder := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(recorder)
	c.Request = httptest.NewRequest(http.MethodPost, "/transfers/pos-restock", strings.NewReader(body))
	c.Request.Header.Set("Content-Type", "application/json")
	c.Set("branch_id", "00000")
	c.Set("pos_id", "POS001")
	c.Set("user", &repository.User{ID: "user.pos1", RoleID: "role.cashier"})

	handler.CreatePosRestock(c)

	if recorder.Code != http.StatusCreated {
		t.Fatalf("expected status %d, got %d with body %s", http.StatusCreated, recorder.Code, recorder.Body.String())
	}
	if repo.transfer == nil {
		t.Fatal("expected transfer to be created")
	}
	if repo.transfer.TransferMode != "pos_restock" || repo.transfer.Status != "draft" {
		t.Fatalf("expected pos_restock draft, got mode=%q status=%q", repo.transfer.TransferMode, repo.transfer.Status)
	}
	if repo.transfer.FromStoreID != "main" || repo.transfer.ToStoreID != "vehicle_POS001" {
		t.Fatalf("unexpected stores from=%q to=%q", repo.transfer.FromStoreID, repo.transfer.ToStoreID)
	}
	if len(repo.items) != 1 || repo.items[0].PartCode != "P0001" || repo.items[0].RequestedQty != 2 {
		t.Fatalf("unexpected items: %#v", repo.items)
	}
}

func TestSubmitPosRestockMovesDraftToReview(t *testing.T) {
	gin.SetMode(gin.TestMode)

	now := time.Now().UTC()
	repo := &stubInventoryTransferRepository{
		transfer: &repository.InventoryTransfer{
			ID:           "TRTEST000001",
			FromBranchID: "00000",
			ToBranchID:   "00000",
			FromStoreID:  "main",
			ToStoreID:    "vehicle_POS001",
			TransferMode: "pos_restock",
			CreatedBy:    "user.pos1",
			Status:       "draft",
			CreatedAt:    now,
		},
		items: []repository.InventoryTransferItem{{
			TransferID:   "TRTEST000001",
			PartCode:     "P0001",
			RequestedQty: 1,
		}},
	}
	handler := NewInventoryTransferHandler(repo, nil, nil)

	recorder := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(recorder)
	c.Request = httptest.NewRequest(http.MethodPut, "/transfers/TRTEST000001/submit", nil)
	c.Params = gin.Params{{Key: "id", Value: "TRTEST000001"}}
	c.Set("user", &repository.User{ID: "user.pos1", RoleID: "role.cashier"})

	handler.Submit(c)

	if recorder.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d with body %s", http.StatusOK, recorder.Code, recorder.Body.String())
	}
	if repo.transfer.Status != "review" {
		t.Fatalf("expected status review, got %q", repo.transfer.Status)
	}
	if repo.transfer.SubmittedBy != "user.pos1" || repo.transfer.SubmittedAt == nil {
		t.Fatalf("expected submitted audit fields, got by=%q at=%v", repo.transfer.SubmittedBy, repo.transfer.SubmittedAt)
	}
}
