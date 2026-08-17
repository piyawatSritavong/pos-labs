package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type stubInventoryTransferRepository struct {
	transfer    *repository.InventoryTransfer
	items       []repository.InventoryTransferItem
	audits      []string
	adjustments []repository.RestockAdjustment
	notes       string
	reviewErr   error
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

func (r *stubInventoryTransferRepository) ListCompletedRestocksByPOSDate(ctx context.Context, posID string, dateFrom, dateTo time.Time) ([]repository.InventoryTransfer, error) {
	return nil, nil
}

func (r *stubInventoryTransferRepository) UpdateItems(ctx context.Context, transferID string, items []repository.InventoryTransferItem) error {
	r.items = append([]repository.InventoryTransferItem(nil), items...)
	return nil
}

func (r *stubInventoryTransferRepository) SubmitPosRestock(ctx context.Context, id, userID string, timestamp time.Time) error {
	if r.transfer != nil && r.transfer.ID == id {
		r.transfer.Status = "review"
		r.transfer.SubmittedAt = &timestamp
		r.transfer.SubmittedBy = userID
		r.transfer.TotalSaleValue = 0
		for index := range r.items {
			if r.items[index].SalePrice == 0 {
				r.items[index].SalePrice = 100
			}
			r.items[index].LineTotal = float64(r.items[index].RequestedQty) * r.items[index].SalePrice
			r.transfer.TotalSaleValue += r.items[index].LineTotal
		}
		r.audits = append(r.audits, "submitted_for_review")
	}
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

func (r *stubInventoryTransferRepository) ReviewRestockItems(ctx context.Context, transferID, actorID string, adjustments []repository.RestockAdjustment) error {
	r.adjustments = append([]repository.RestockAdjustment(nil), adjustments...)
	return r.reviewErr
}

func (r *stubInventoryTransferRepository) UpdateNotes(ctx context.Context, transferID, notes string) error {
	r.notes = notes
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

type stubRestockPartRepository struct {
	parts        []repository.PartDetail
	addresses    map[string][]repository.PartAddress
	query        string
	storeID      string
	saleableOnly bool
	limit        int
	offset       int
}

func (r *stubRestockPartRepository) SearchParts(_ context.Context, query string, _ *string, _ *bool, _, storeID *string, saleableOnly bool, limit, offset int) ([]repository.PartDetail, error) {
	r.query = query
	r.saleableOnly = saleableOnly
	r.limit = limit
	r.offset = offset
	if storeID != nil {
		r.storeID = *storeID
	}
	end := offset + limit
	if end > len(r.parts) {
		end = len(r.parts)
	}
	if offset >= len(r.parts) {
		return nil, nil
	}
	return r.parts[offset:end], nil
}

func (r *stubRestockPartRepository) CountParts(context.Context, string, *string, *bool, *string, *string, bool) (int, error) {
	return len(r.parts), nil
}

func (r *stubRestockPartRepository) GetAddressesByPartCodes(_ context.Context, codes []string, _ *string) (map[string][]repository.PartAddress, error) {
	out := make(map[string][]repository.PartAddress, len(codes))
	for _, code := range codes {
		out[code] = r.addresses[code]
	}
	return out, nil
}

func (*stubRestockPartRepository) GetPartDetail(context.Context, string, *string) (*repository.PartDetail, []repository.PartAddress, error) {
	return nil, nil, repository.ErrNotFound
}
func (*stubRestockPartRepository) ListParts(context.Context, int, int, *string) ([]repository.PartSummary, error) {
	return nil, nil
}
func (*stubRestockPartRepository) GetPartByBarcode(context.Context, string, string) (*repository.PartDetail, []repository.PartAddress, error) {
	return nil, nil, repository.ErrNotFound
}
func (*stubRestockPartRepository) CheckPartExistsInBranch(context.Context, string, string) (bool, error) {
	return false, nil
}
func (*stubRestockPartRepository) CreatePart(context.Context, repository.PartInput) error {
	return nil
}
func (*stubRestockPartRepository) UpdatePart(context.Context, string, repository.PartInput) error {
	return nil
}
func (*stubRestockPartRepository) DeletePart(context.Context, string) (string, error) {
	return "deleted", nil
}
func (*stubRestockPartRepository) GenerateNextPartCode(context.Context) (string, error) {
	return "P0001", nil
}
func (*stubRestockPartRepository) ImportParts(context.Context, []repository.PartImportRow, repository.PartImportBatch) (repository.PartImportResult, error) {
	return repository.PartImportResult{}, nil
}
func (*stubRestockPartRepository) FindImportsOfFile(context.Context, string) ([]repository.PartImportSummary, error) {
	return nil, nil
}
func (*stubRestockPartRepository) ListImportBatches(context.Context, int, int) ([]repository.PartImportSummary, int, error) {
	return nil, 0, nil
}
func (*stubRestockPartRepository) GetImportBatch(context.Context, string) (*repository.PartImportSummary, []repository.PartImportLine, error) {
	return nil, nil, repository.ErrNotFound
}

func TestRestockCatalogSupportsPaginationWithoutCostFields(t *testing.T) {
	gin.SetMode(gin.TestMode)
	parts := &stubRestockPartRepository{
		parts: []repository.PartDetail{
			{Code: "P0001", Name: "Cable A", NameTH: "สายไฟ A", BarCode: "111", Price: 10, Cost: 7, MinPrice: 9},
			{Code: "P0002", Name: "Cable B", NameTH: "สายไฟ B", BarCode: "222", Price: 20, Cost: 14, MinPrice: 18},
		},
		addresses: map[string][]repository.PartAddress{
			"P0002": {{PartCode: "P0002", StoreID: "main", Qty: 3}},
		},
	}
	handler := NewInventoryTransferHandler(nil, nil, nil, parts)
	recorder := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(recorder)
	c.Request = httptest.NewRequest(http.MethodGet, "/transfers/pos-restock/catalog?q=สาย&limit=1&offset=1", nil)

	handler.RestockCatalog(c)

	if recorder.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", recorder.Code, recorder.Body.String())
	}
	if parts.query != "สาย" || parts.storeID != "main" || !parts.saleableOnly || parts.limit != 1 || parts.offset != 1 {
		t.Fatalf("unexpected repository filters: %#v", parts)
	}
	var response map[string]any
	if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
		t.Fatal(err)
	}
	if response["total"] != float64(2) || response["limit"] != float64(1) || response["offset"] != float64(1) {
		t.Fatalf("unexpected pagination response: %s", recorder.Body.String())
	}
	items, _ := response["parts"].([]any)
	if len(items) != 1 {
		t.Fatalf("expected one item: %s", recorder.Body.String())
	}
	item := items[0].(map[string]any)
	if item["code"] != "P0002" || item["availableQty"] != float64(3) {
		t.Fatalf("unexpected item: %#v", item)
	}
	if _, exists := item["cost"]; exists {
		t.Fatal("employee catalog must not expose cost")
	}
	if _, exists := item["minPrice"]; exists {
		t.Fatal("employee catalog must not expose minimum price")
	}
}

func TestInventoryTransferCreateAllowsSameBranch(t *testing.T) {
	t.Helper()
	gin.SetMode(gin.TestMode)

	repo := &stubInventoryTransferRepository{}
	handler := NewInventoryTransferHandler(repo, nil, nil, nil)

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
		nil,
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
	if repo.transfer.TargetPOSID != "POS001" {
		t.Fatalf("expected target POS001, got %q", repo.transfer.TargetPOSID)
	}
	if len(repo.items) != 1 || repo.items[0].PartCode != "P0001" || repo.items[0].RequestedQty != 2 {
		t.Fatalf("unexpected items: %#v", repo.items)
	}
}

func TestCreatePosRestockRejectsNonVehiclePOS(t *testing.T) {
	gin.SetMode(gin.TestMode)

	repo := &stubInventoryTransferRepository{}
	handler := NewInventoryTransferHandler(
		repo,
		stubBranchRepository{},
		stubPOSRepository{pos: &repository.POS{
			POSID:          "POS003",
			BranchID:       "00000",
			VehicleStoreID: "main",
			IsActive:       true,
		}},
		nil,
	)

	body := `{"items":[{"partCode":"P0001","requestedQty":2}]}`
	recorder := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(recorder)
	c.Request = httptest.NewRequest(http.MethodPost, "/transfers/pos-restock", strings.NewReader(body))
	c.Request.Header.Set("Content-Type", "application/json")
	c.Set("branch_id", "00000")
	c.Set("pos_id", "POS003")
	c.Set("user", &repository.User{ID: "user.admin", RoleID: "role.admin"})

	handler.CreatePosRestock(c)

	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("expected status %d, got %d with body %s", http.StatusBadRequest, recorder.Code, recorder.Body.String())
	}
	if repo.transfer != nil {
		t.Fatal("expected no restock transfer to be created for main warehouse POS")
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
	handler := NewInventoryTransferHandler(repo, nil, nil, nil)

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
	if repo.items[0].SalePrice != 100 || repo.items[0].LineTotal != 100 || repo.transfer.TotalSaleValue != 100 {
		t.Fatalf("expected submit price snapshot, got item=%#v total=%v", repo.items[0], repo.transfer.TotalSaleValue)
	}
}

func TestBuildTransferOutputUsesItemSnapshotTotals(t *testing.T) {
	transfer := &repository.InventoryTransfer{
		ID:             "TRTEST000002",
		TransferMode:   "pos_restock",
		Status:         "review",
		TotalSaleValue: 0,
	}
	items := []repository.InventoryTransferItem{
		{TransferID: transfer.ID, PartCode: "P0001", RequestedQty: 2, SalePrice: 650, LineTotal: 1300},
		{TransferID: transfer.ID, PartCode: "P0002", RequestedQty: 1, SalePrice: 0, LineTotal: 0},
	}

	output := buildTransferOutput(transfer, items)
	if output["totalSaleValue"] != float64(1300) {
		t.Fatalf("expected item-derived total 1300, got %#v", output["totalSaleValue"])
	}
	rows, ok := output["items"].([]gin.H)
	if !ok || len(rows) != 2 {
		t.Fatalf("unexpected output rows: %#v", output["items"])
	}
	if rows[0]["salePrice"] != float64(650) || rows[0]["lineTotal"] != float64(1300) {
		t.Fatalf("unexpected price snapshot output: %#v", rows[0])
	}
	if rows[1]["salePrice"] != float64(0) || rows[1]["lineTotal"] != float64(0) {
		t.Fatalf("zero-price product must remain valid: %#v", rows[1])
	}
}

func reviewRequest(t *testing.T, repo *stubInventoryTransferRepository, body string) *httptest.ResponseRecorder {
	t.Helper()
	gin.SetMode(gin.TestMode)
	handler := NewInventoryTransferHandler(repo, nil, nil, nil)
	recorder := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(recorder)
	c.Params = gin.Params{{Key: "id", Value: "TR20260817000001"}}
	c.Request = httptest.NewRequest(http.MethodPut,
		"/transfers/TR20260817000001/review-items", strings.NewReader(body))
	c.Request.Header.Set("Content-Type", "application/json")
	c.Set("user", &repository.User{ID: "user.hqmanager", RoleID: "role.hq_manager"})
	handler.ReviewRestockItems(c)
	return recorder
}

func TestReviewRestockItemsRecordsCorrectedQuantitiesAndRemarks(t *testing.T) {
	repo := &stubInventoryTransferRepository{}
	recorder := reviewRequest(t, repo, `{
		"items":[
			{"partCode":"P0001","approvedQty":8,"remarks":"ใบเบิกกระดาษเขียน 8"},
			{"partCode":"P0002","approvedQty":5,"remarks":""}
		],
		"notes":"ตรวจกับใบเขียนมือแล้ว"
	}`)

	if recorder.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", recorder.Code, recorder.Body.String())
	}
	if len(repo.adjustments) != 2 {
		t.Fatalf("expected both lines to reach the repository, got %#v", repo.adjustments)
	}
	if repo.adjustments[0].PartCode != "P0001" || repo.adjustments[0].ApprovedQty != 8 {
		t.Fatalf("first adjustment wrong: %#v", repo.adjustments[0])
	}
	if repo.adjustments[0].Remarks != "ใบเบิกกระดาษเขียน 8" {
		t.Fatalf("remark not carried through: %#v", repo.adjustments[0])
	}
	if repo.notes != "ตรวจกับใบเขียนมือแล้ว" {
		t.Fatalf("document note not saved, got %q", repo.notes)
	}
}

func TestReviewRestockItemsAcceptsZeroButNotNegative(t *testing.T) {
	// Zero is a real decision — "none of this went out" — while a negative
	// quantity is always a mistake.
	repo := &stubInventoryTransferRepository{}
	if code := reviewRequest(t, repo, `{"items":[{"partCode":"P0001","approvedQty":0}]}`).Code; code != http.StatusOK {
		t.Fatalf("zero should be allowed, got %d", code)
	}
	if len(repo.adjustments) != 1 || repo.adjustments[0].ApprovedQty != 0 {
		t.Fatalf("zero not passed through: %#v", repo.adjustments)
	}

	repo = &stubInventoryTransferRepository{}
	if code := reviewRequest(t, repo, `{"items":[{"partCode":"P0001","approvedQty":-2}]}`).Code; code != http.StatusBadRequest {
		t.Fatalf("negative should be rejected, got %d", code)
	}
	if len(repo.adjustments) != 0 {
		t.Fatal("a rejected request must not reach the repository")
	}
}

func TestReviewRestockItemsRejectsRequestNotUnderReview(t *testing.T) {
	repo := &stubInventoryTransferRepository{reviewErr: errors.New("invalid_status")}
	recorder := reviewRequest(t, repo, `{"items":[{"partCode":"P0001","approvedQty":3}]}`)
	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d: %s", recorder.Code, recorder.Body.String())
	}
	if !strings.Contains(recorder.Body.String(), "invalid_status") {
		t.Fatalf("expected invalid_status, got %s", recorder.Body.String())
	}
}
