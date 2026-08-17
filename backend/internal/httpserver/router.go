package httpserver

import (
	"database/sql"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"backend/internal/config"
	"backend/internal/httpserver/handlers"
	"backend/internal/httpserver/middleware"
	"backend/internal/printer"
	"backend/internal/repository"

	"github.com/gin-gonic/gin"
)

func NewRouter(cfg config.Config, db *sql.DB) *gin.Engine {
	if cfg.Env == "production" {
		gin.SetMode(gin.ReleaseMode)
	}

	r := gin.New()
	r.Use(gin.Logger(), gin.Recovery())

	// Per-request timing log (greppable "[timing] ..." lines) for measuring
	// endpoint latency before/after performance work.
	r.Use(middleware.Timing())

	// CORS middleware (environment-aware)
	r.Use(middleware.CORS(cfg))

	userRepo := repository.NewUserRepository(db)
	rbacRepo := repository.NewRBACRepository(db)
	sessionRepo := repository.NewSessionRepository(db)

	authMw := middleware.NewAuthMiddleware(userRepo, rbacRepo, sessionRepo)

	// Health
	healthHandler := handlers.NewHealthHandler(db)
	r.GET("/health", healthHandler.Health)
	r.GET("/ready", healthHandler.Ready)
	r.GET("/health/db", healthHandler.Ready)

	// ---- Mock test endpoint ----
	r.GET("/test", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"message": "welcome",
		})
	})

	// Repositories needed for auth handler
	branchRepo := repository.NewBranchRepository(db)
	posRepo := repository.NewPOSRepository(db)
	userBranchRepo := repository.NewUserBranchRepository(db)

	// Auth
	authHandler := handlers.NewAuthHandler(userRepo, sessionRepo, userBranchRepo, branchRepo, posRepo, cfg.SessionDurationParsed())
	authGroup := r.Group("/auth")
	{
		authGroup.POST("/login", authHandler.Login)
		authGroup.POST("/verify-password", authHandler.VerifyPassword)
		authGroup.POST("/logout", authMw.RequireAuth(), authHandler.Logout)
		authGroup.GET("/me", authMw.RequireAuth(), authHandler.Me)
		authGroup.GET("/sessions", authMw.RequireAuth(), authHandler.Sessions)
		authGroup.POST("/sessions/revoke-others", authMw.RequireAuth(), authHandler.RevokeOtherSessions)
	}

	// QR Image (static file serving)
	staticDir := cfg.StaticFilesPath
	qrImageHandler := handlers.NewQRImageHandler(staticDir)
	qrImage := r.Group("/assets")
	qrImage.Use(authMw.RequirePermission("qr_image", "read"))
	{
		qrImage.GET("/qr-image", qrImageHandler.Get)
	}
	qrImageWrite := r.Group("/assets")
	qrImageWrite.Use(authMw.RequirePermission("qr_image", "write"))
	{
		qrImageWrite.PUT("/qr-image", qrImageHandler.Put)
	}

	// Protected resources examples
	partRepo := repository.NewPartRepository(db)
	memberRepo := repository.NewMemberRepository(db)
	addressRepo := repository.NewAddressRepository(db)
	partsHandler := handlers.NewPartsHandler(partRepo, addressRepo, posRepo)
	memberHandler := handlers.NewMemberHandler(memberRepo)
	parts := r.Group("/parts")
	parts.Use(authMw.RequirePermission("parts", "read"))
	{
		parts.GET("", partsHandler.List)
		parts.GET("/search", partsHandler.Search)
		parts.GET("/generate-code", partsHandler.GenerateCode)
		parts.GET("/:code", partsHandler.Get)
	}
	partsWrite := r.Group("/parts")
	partsWrite.Use(authMw.RequirePermission("parts", "write"))
	{
		partsWrite.POST("", partsHandler.Create)
		partsWrite.PUT("/:code", partsHandler.Update)
	}
	// Bulk create from a spreadsheet. The blank template carries no business
	// data, so it is served without auth — that is what lets the client offer
	// it as a plain download link.
	partsImportHandler := handlers.NewPartsImportHandler(partRepo)
	r.GET("/parts/import/template", partsImportHandler.Template)
	partsImport := r.Group("/parts/import")
	partsImport.Use(authMw.RequirePermission("parts", "write"))
	{
		partsImport.GET("/limits", partsImportHandler.Limits)
		partsImport.POST("", partsImportHandler.Import)
	}
	// Reading the import history only needs read access — it is a stock
	// document like any other.
	partsImportHistory := r.Group("/parts/import/history")
	partsImportHistory.Use(authMw.RequirePermission("parts", "read"))
	{
		partsImportHistory.GET("", partsImportHandler.History)
		partsImportHistory.GET("/:id", partsImportHandler.HistoryDetail)
	}
	partsDelete := r.Group("/parts")
	partsDelete.Use(authMw.RequirePermission("parts", "delete"))
	{
		partsDelete.DELETE("/:code", partsHandler.Delete)
	}
	members := r.Group("/members")
	members.Use(authMw.RequirePermission("members", "read"))
	{
		members.GET("", memberHandler.List)
		members.GET("/search", memberHandler.Search)
		members.GET("/:id", memberHandler.Get)
	}
	membersWrite := r.Group("/members")
	membersWrite.Use(authMw.RequirePermission("members", "write"))
	{
		membersWrite.POST("", memberHandler.Create)
		membersWrite.PUT("/:id", memberHandler.Update)
	}
	membersDelete := r.Group("/members")
	membersDelete.Use(authMw.RequirePermission("members", "delete"))
	{
		membersDelete.DELETE("/:id", memberHandler.Delete)
	}

	billRepo := repository.NewBillRepository(db)
	returnNoteRepo := repository.NewReturnNoteRepository(db)
	companyRepo := repository.NewCompanyRepository(db)
	promotionRepo := repository.NewPromotionRepository(db)
	drawerKickCommand, drawerKickHex, err := printer.ParseDrawerKickCommand(cfg.CashDrawerKickCommand)
	if err != nil {
		log.Printf("Invalid CASH_DRAWER_KICK_COMMAND=%q: %v; using default %s",
			cfg.CashDrawerKickCommand, err, printer.DefaultDrawerKickCommandHex)
		drawerKickCommand, drawerKickHex = printer.MustDrawerKickCommand(printer.DefaultDrawerKickCommandHex)
	}
	billsHandler := handlers.NewBillsHandler(billRepo, branchRepo, posRepo, partRepo, memberRepo, companyRepo, promotionRepo, addressRepo, userRepo)
	// Wire the 80mm receipt printer target — see config.ReceiptPrinter
	// (defaults to "LPT1"). Handler reports printer_not_configured if empty.
	billsHandler.PrinterTarget = cfg.ReceiptPrinter
	// Code page for Thai output (ESC t n). 21 covers most Thailand-market
	// printers; tune via RECEIPT_CHARSET if the device disagrees.
	if cfg.ReceiptCharset >= 0 && cfg.ReceiptCharset <= 255 {
		billsHandler.PrinterCharset = byte(cfg.ReceiptCharset)
	}
	billsHandler.PrinterMode = cfg.ReceiptPrintMode
	billsHandler.PrinterEnabled = cfg.ReceiptPrinterEnabled
	billsHandler.OpenCashDrawer = cfg.CashDrawerEnabled
	billsHandler.DrawerKick = drawerKickCommand
	returnNotesHandler := handlers.NewReturnNotesHandler(returnNoteRepo, billRepo, memberRepo, branchRepo, posRepo, companyRepo, userRepo)
	returnNotesHandler.PrinterTarget = cfg.ReceiptPrinter
	if cfg.ReceiptCharset >= 0 && cfg.ReceiptCharset <= 255 {
		returnNotesHandler.PrinterCharset = byte(cfg.ReceiptCharset)
	}
	returnNotesHandler.PrinterMode = cfg.ReceiptPrintMode
	returnNotesHandler.PrinterEnabled = cfg.ReceiptPrinterEnabled
	returnNotesHandler.OpenCashDrawer = cfg.CashDrawerEnabled
	returnNotesHandler.DrawerKick = drawerKickCommand
	bills := r.Group("/bills")
	bills.Use(authMw.RequirePermission("bills", "read"))
	// GET endpoints allow access without posId/branchId (for admin users)
	{
		bills.GET("", billsHandler.List)
		bills.GET("/:id", billsHandler.Get)
	}
	// Create bill requires write permission
	billsWrite := r.Group("/bills")
	billsWrite.Use(authMw.RequirePermission("bills", "write"))
	billsWrite.Use(middleware.RequirePOSBranch()) // Bills endpoints require POS session with branchId and posId
	{
		billsWrite.POST("", billsHandler.Create)
		billsWrite.PUT("/:id/add-item", billsHandler.AddItem)                     // add item to bill by part code
		billsWrite.PUT("/:id/add-item-by-barcode", billsHandler.AddItemByBarcode) // add item to bill by barcode
		billsWrite.PUT("/:id/remove-item", billsHandler.RemoveItem)               // remove item from bill
		billsWrite.PUT("/:id/update-item-price", billsHandler.UpdateItemPrice)    // update item line price in bill
		billsWrite.PUT("/:id/add-discount", billsHandler.AddDiscount)             // apply discount to bill
		billsWrite.PUT("/:id/remove-discount", billsHandler.RemoveDiscount)       // remove discount from bill
		billsWrite.PUT("/:id/add-member-by-phone", billsHandler.AddMemberByPhone) // assign member to bill by phone number
		billsWrite.PUT("/:id/remove-member", billsHandler.RemoveMember)           // remove member from bill
		billsWrite.PUT("/:id/hold", billsHandler.Hold)                            // hold bill
		billsWrite.PUT("/switch", billsHandler.SwitchBill)                        // switch bills: if currentBillId not provided, create new bill; otherwise hold current and resume target
		billsWrite.PUT("/:id/payment", billsHandler.Payment)                      // process payment
		billsWrite.POST("/print-test", billsHandler.PrintTestReceipt)             // print synthetic test receipt without a sale
		billsWrite.POST("/:id/print", billsHandler.PrintReceipt)                  // ESC-POS receipt → LPT1 (80mm)
		billsWrite.PUT("/:id/cancel", billsHandler.Cancel)                        // cancel bill
	}
	billsDelete := r.Group("/bills")
	billsDelete.Use(authMw.RequirePermission("bills", "delete"))
	billsDelete.Use(middleware.RequirePOSBranch()) // Bills endpoints require POS session with branchId and posId
	{
		billsDelete.DELETE("/:id", billsHandler.Delete) // delete bill permanently
	}

	returns := r.Group("/returns")
	returns.Use(authMw.RequirePermission("bills", "read"))
	{
		returns.GET("", returnNotesHandler.List)
		returns.GET("/reference/:billId", returnNotesHandler.GetReferenceBill)
		returns.GET("/:id", returnNotesHandler.Get)
	}
	returnsWrite := r.Group("/returns")
	returnsWrite.Use(authMw.RequirePermission("bills", "write"))
	returnsWrite.Use(middleware.RequirePOSBranch())
	{
		returnsWrite.POST("", returnNotesHandler.Create)
		returnsWrite.POST("/:id/print", returnNotesHandler.PrintReceipt)
	}

	// Reports (CSV exports)
	reportRepo := repository.NewReportRepository(db)
	reportsHandler := handlers.NewReportsHandler(reportRepo)
	reports := r.Group("/reports")
	{
		reports.GET("/bills", authMw.RequirePermission("reports_bill", "read"), reportsHandler.BillsReport)              // bills report with date filter
		reports.GET("/parts", authMw.RequirePermission("reports_parts", "read"), reportsHandler.PartsReport)             // all parts report
		reports.GET("/inventory", authMw.RequirePermission("reports_inventory", "read"), reportsHandler.InventoryReport) // all inventory report
		reports.GET("/income", authMw.RequirePermission("reports_bill", "read"), reportsHandler.IncomeReport)
	}

	// Company (read and update only)
	// companyRepo already created above for BillsHandler
	companyHandler := handlers.NewCompanyHandler(companyRepo)
	company := r.Group("/company")
	company.Use(authMw.RequirePermission("company", "read"))
	{
		company.GET("", companyHandler.Get)
	}
	companyWrite := r.Group("/company")
	companyWrite.Use(authMw.RequirePermission("company", "write"))
	{
		companyWrite.PUT("", companyHandler.Update)
	}

	// Branches (CRUD)
	branchHandler := handlers.NewBranchHandler(branchRepo)
	branches := r.Group("/branches")
	branches.Use(authMw.RequirePermission("branch", "read"))
	{
		branches.GET("", branchHandler.List)
		branches.GET("/next-id", branchHandler.NextID)
		branches.GET("/:id", branchHandler.Get)
	}
	branchesWrite := r.Group("/branches")
	branchesWrite.Use(authMw.RequirePermission("branch", "write"))
	{
		branchesWrite.POST("", branchHandler.Create)
		branchesWrite.PUT("/:id", branchHandler.Update)
	}
	branchesDelete := r.Group("/branches")
	branchesDelete.Use(authMw.RequirePermission("branch", "delete"))
	{
		branchesDelete.DELETE("/:id", branchHandler.Delete)
	}

	// POS (CRUD)
	posHandler := handlers.NewPOSHandler(posRepo)
	posHandler.PrinterEnabled = cfg.ReceiptPrinterEnabled
	posHandler.PrinterTarget = cfg.ReceiptPrinter
	if cfg.ReceiptCharset >= 0 && cfg.ReceiptCharset <= 255 {
		posHandler.PrinterCharset = byte(cfg.ReceiptCharset)
	}
	posHandler.PrinterMode = cfg.ReceiptPrintMode
	posHandler.CashDrawerEnabled = cfg.CashDrawerEnabled
	posHandler.DrawerKick = drawerKickCommand
	posHandler.DrawerKickCommandHex = drawerKickHex
	pos := r.Group("/pos")
	pos.Use(authMw.RequirePermission("pos", "read"))
	{
		pos.GET("", posHandler.List)
		pos.GET("/:id", posHandler.Get)
	}
	posWrite := r.Group("/pos")
	posWrite.Use(authMw.RequirePermission("pos", "write"))
	{
		posWrite.POST("", posHandler.Create)
		posWrite.PUT("/:id/toggle-activate", posHandler.ToggleActivate)
	}
	posPrinter := r.Group("/pos/printer")
	posPrinter.Use(authMw.RequirePermission("bills", "write"))
	posPrinter.Use(middleware.RequirePOSBranch())
	{
		posPrinter.POST("/open-drawer", posHandler.OpenDrawer)
		posPrinter.POST("/test-print", posHandler.TestPrint)
		posPrinter.POST("/test-receipt", posHandler.TestReceipt)
	}
	posSecret := r.Group("/pos")
	posSecret.Use(authMw.RequirePermission("pos", "secret")) // Special permission for retrieving and refreshing secret
	{
		posSecret.GET("/:id/secret", posHandler.GetSecret)
		posSecret.PUT("/:id/secret", posHandler.RefreshSecret) // Refresh/regenerate POS secret
	}
	posDelete := r.Group("/pos")
	posDelete.Use(authMw.RequirePermission("pos", "delete"))
	{
		posDelete.DELETE("/:id", posHandler.Delete)
	}

	// Promotions (CRUD)
	promotionHandler := handlers.NewPromotionHandler(promotionRepo)
	promotions := r.Group("/promotions")
	promotions.Use(authMw.RequirePermission("promotions", "read"))
	{
		promotions.GET("", promotionHandler.List)
		promotions.GET("/:code", promotionHandler.Get)
	}
	promotionsWrite := r.Group("/promotions")
	promotionsWrite.Use(authMw.RequirePermission("promotions", "write"))
	{
		promotionsWrite.POST("", promotionHandler.Create)
		promotionsWrite.PUT("/:code", promotionHandler.Update)
	}
	promotionsDelete := r.Group("/promotions")
	promotionsDelete.Use(authMw.RequirePermission("promotions", "delete"))
	{
		promotionsDelete.DELETE("/:code", promotionHandler.Delete)
	}

	// Addresses (CRUD)
	// addressRepo already created above for BillsHandler
	addressHandler := handlers.NewAddressHandler(addressRepo)
	addresses := r.Group("/addresses")
	addresses.Use(authMw.RequirePermission("addresses", "read"))
	{
		addresses.GET("", addressHandler.List)
		addresses.GET("/:code", addressHandler.Get)
	}
	addressesWrite := r.Group("/addresses")
	addressesWrite.Use(authMw.RequirePermission("addresses", "write"))
	{
		addressesWrite.POST("", addressHandler.Create)
		addressesWrite.PUT("/:code", addressHandler.Update)
	}
	addressesDelete := r.Group("/addresses")
	addressesDelete.Use(authMw.RequirePermission("addresses", "delete"))
	{
		addressesDelete.DELETE("/:code", addressHandler.Delete)
	}

	// Stores — canonical list shared by the Parts + Addresses store dropdowns,
	// plus create ("เพิ่มคลังใหม่"). Gated by the same addresses permissions.
	storeHandler := handlers.NewStoreHandler(repository.NewStoreRepository(db))
	storesRead := r.Group("/stores")
	storesRead.Use(authMw.RequirePermission("addresses", "read"))
	{
		storesRead.GET("", storeHandler.List)
	}

	purchaseOrderHandler := handlers.NewPurchaseOrderHandler(repository.NewPurchaseOrderRepository(db))
	purchaseOrdersRead := r.Group("/purchase-orders")
	purchaseOrdersRead.Use(authMw.RequirePermission("purchase_orders", "read"))
	{
		purchaseOrdersRead.GET("", purchaseOrderHandler.List)
		purchaseOrdersRead.GET("/:id", purchaseOrderHandler.GetByID)
	}
	purchaseOrdersWrite := r.Group("/purchase-orders")
	purchaseOrdersWrite.Use(authMw.RequirePermission("purchase_orders", "write"))
	{
		purchaseOrdersWrite.POST("", purchaseOrderHandler.Create)
		purchaseOrdersWrite.DELETE("/:id", purchaseOrderHandler.Delete)
	}
	// Users (CRUD)
	userHandler := handlers.NewUserHandler(userRepo)
	users := r.Group("/users")
	users.Use(authMw.RequirePermission("users", "read"))
	{
		users.GET("", userHandler.List)
		users.GET("/:id", userHandler.Get)
	}
	usersWrite := r.Group("/users")
	usersWrite.Use(authMw.RequirePermission("users", "write"))
	{
		usersWrite.POST("", userHandler.Create)
		usersWrite.PUT("/:id", userHandler.Update)
	}
	usersDelete := r.Group("/users")
	usersDelete.Use(authMw.RequirePermission("users", "delete"))
	{
		usersDelete.DELETE("/:id", userHandler.Delete)
	}

	// Roles: list + create custom roles (gated by the users permission, since
	// role management is part of user administration).
	rolesHandler := handlers.NewRolesHandler(rbacRepo)
	rolesRead := r.Group("/roles")
	rolesRead.Use(authMw.RequirePermission("users", "read"))
	{
		rolesRead.GET("", rolesHandler.List)
	}
	rolesWrite := r.Group("/roles")
	rolesWrite.Use(authMw.RequirePermission("users", "write"))
	{
		rolesWrite.POST("", rolesHandler.Create)
	}

	// User Branches (CRUD)
	userBranchHandler := handlers.NewUserBranchHandler(userBranchRepo)
	userBranches := r.Group("/user-branches")
	userBranches.Use(authMw.RequirePermission("user_branch", "read"))
	{
		userBranches.GET("/user/:user_id", userBranchHandler.ListByUser)
		userBranches.GET("/branch/:branch_id", userBranchHandler.ListByBranch)
		userBranches.GET("/:user_id/:branch_id", userBranchHandler.Get)
	}
	userBranchesWrite := r.Group("/user-branches")
	userBranchesWrite.Use(authMw.RequirePermission("user_branch", "write"))
	{
		userBranchesWrite.POST("", userBranchHandler.Create)
		userBranchesWrite.DELETE("/:user_id/:branch_id", userBranchHandler.Delete)
	}

	// Inventory Transfer
	transferRepo := repository.NewInventoryTransferRepository(db)
	stockCountRepo := repository.NewStockCountRepository(db)
	dailyCloseRepo := repository.NewDailyCloseRepository(db)
	cashReconRepo := repository.NewCashReconciliationRepository(db)

	transferHandler := handlers.NewInventoryTransferHandler(transferRepo, branchRepo, posRepo, partRepo)
	stockCountHandler := handlers.NewStockCountHandler(stockCountRepo, branchRepo)
	dailyCloseHandler := handlers.NewDailyCloseHandler(dailyCloseRepo, branchRepo)
	cashReconHandler := handlers.NewCashReconciliationHandler(cashReconRepo, dailyCloseRepo)
	stockVarianceHandler := handlers.NewStockVarianceHandler(stockCountRepo)
	vehicleInventoryHandler := handlers.NewVehicleInventoryHandler(repository.NewVehicleInventoryRepository(db), posRepo)

	transfersRead := r.Group("/transfers")
	transfersRead.Use(authMw.RequirePermission("transfers", "read"))
	{
		transfersRead.GET("", transferHandler.List)
		transfersRead.GET("/pos-restock/catalog", transferHandler.RestockCatalog)
		transfersRead.GET("/:id", transferHandler.GetByID)
	}
	transfersWrite := r.Group("/transfers")
	transfersWrite.Use(authMw.RequirePermission("transfers", "write"))
	{
		transfersWrite.POST("", transferHandler.Create)
		transfersWrite.POST("/pos-restock", transferHandler.CreatePosRestock)
		transfersWrite.PUT("/:id/items", transferHandler.UpdateItems)
		transfersWrite.PUT("/:id/submit", transferHandler.Submit)
		transfersWrite.PUT("/:id/receive", transferHandler.Receive)
		transfersWrite.PUT("/:id/cancel", transferHandler.Cancel) // van_staff can cancel own requests
	}
	transfersApprove := r.Group("/transfers")
	transfersApprove.Use(authMw.RequirePermission("transfers", "approve"))
	{
		transfersApprove.GET("/vehicle-daily-summary", transferHandler.VehicleDailySummary)
		transfersApprove.PUT("/:id/approve", transferHandler.Approve)
		transfersApprove.PUT("/:id/dispatch", transferHandler.Dispatch)
		transfersApprove.PUT("/:id/acknowledge", transferHandler.Acknowledge)
		transfersApprove.PUT("/:id/review-items", transferHandler.ReviewRestockItems)
		transfersApprove.PUT("/:id/approve-restock", transferHandler.ApproveRestock)
		transfersApprove.POST("/:id/print-log", transferHandler.PrintLog)
	}

	vehicleInventory := r.Group("/vehicle-inventory")
	vehicleInventory.Use(authMw.RequirePermission("transfers", "approve"))
	{
		vehicleInventory.GET("", vehicleInventoryHandler.List)
	}

	// Stock Count
	stockCountsRead := r.Group("/stock-counts")
	stockCountsRead.Use(authMw.RequirePermission("stock_count", "read"))
	{
		stockCountsRead.GET("", stockCountHandler.List)
		stockCountsRead.GET("/:id", stockCountHandler.GetByID)
	}
	stockCountsWrite := r.Group("/stock-counts")
	stockCountsWrite.Use(authMw.RequirePermission("stock_count", "write"))
	{
		stockCountsWrite.POST("", stockCountHandler.Create)
		stockCountsWrite.PUT("/:id/items", stockCountHandler.UpdateItems)
		stockCountsWrite.PUT("/:id/submit", stockCountHandler.Submit)
	}

	// Daily Close
	dailyClosesRead := r.Group("/daily-closes")
	dailyClosesRead.Use(authMw.RequirePermission("daily_close", "read"))
	{
		dailyClosesRead.GET("", dailyCloseHandler.List)
		dailyClosesRead.GET("/summary", dailyCloseHandler.GetSummary)
		dailyClosesRead.GET("/:id", dailyCloseHandler.GetByID)
	}
	dailyClosesWrite := r.Group("/daily-closes")
	dailyClosesWrite.Use(authMw.RequirePermission("daily_close", "write"))
	{
		dailyClosesWrite.POST("", dailyCloseHandler.Create)
	}

	// Cash Reconciliation
	cashReconsRead := r.Group("/cash-reconciliations")
	cashReconsRead.Use(authMw.RequirePermission("cash_reconciliation", "read"))
	{
		cashReconsRead.GET("", cashReconHandler.List)
		cashReconsRead.GET("/:id", cashReconHandler.GetByID)
	}
	cashReconsWrite := r.Group("/cash-reconciliations")
	cashReconsWrite.Use(authMw.RequirePermission("cash_reconciliation", "write"))
	{
		cashReconsWrite.POST("", cashReconHandler.Create)
	}

	// Stock Variance Report
	reports.GET("/stock-variance", authMw.RequirePermission("reports_variance", "read"), stockVarianceHandler.GetVariance)

	// POS Mirror WebSocket (no auth middleware — handler authenticates via ?token= query param)
	posMirrorHandler := handlers.NewPosMirrorHandler(sessionRepo, userRepo, posRepo, cfg)
	r.GET("/ws/pos-mirror", posMirrorHandler.HandleWS)
	r.GET("/ws/customer-display", posMirrorHandler.HandleCustomerDisplayWS)
	posMirrorWrite := r.Group("/pos-mirror")
	posMirrorWrite.Use(authMw.RequirePermission("bills", "write"))
	posMirrorWrite.Use(middleware.RequirePOSBranch())
	{
		posMirrorWrite.POST("/test-state", posMirrorHandler.TestState)
	}

	// ----------------------------------------------------------------------
	// Static Flutter Web + SPA fallback.
	//
	// Order of resolution for an unmatched route:
	//   1. Non-GET/HEAD → JSON 404 (API mistake, not a page request)
	//   2. Path matches a known API prefix → JSON 404 (preserve API semantics
	//      for typo'd endpoints; /assets is intentionally NOT in this list
	//      because Flutter Web serves its bundled assets under /assets/*)
	//   3. File exists under STATIC_FILES_PATH → serve the file
	//   4. index.html exists → serve it (SPA client-side routing)
	//   5. Otherwise → JSON 404
	//
	// STATIC_FILES_PATH defaults to "static" (see config.go). On the Windows
	// POS deployment this resolves to C:\POSApp\static which holds the
	// Flutter Web release build. Existing API routes (/auth, /parts, ...) are
	// registered ABOVE this handler so they are matched first by Gin.
	// ----------------------------------------------------------------------
	apiPrefixes := []string{
		"/health/", "/ready/", "/auth/", "/parts/", "/members/", "/bills/", "/returns/",
		"/reports/", "/company/", "/branches/", "/pos/", "/promotions/",
		"/addresses/", "/users/", "/user-branches/", "/transfers/",
		"/stock-counts/", "/daily-closes/", "/cash-reconciliations/",
		"/ws/", "/pos-mirror/",
	}
	exactAPIPaths := map[string]struct{}{
		"/health": {}, "/ready": {}, "/health/db": {}, "/test": {},
		"/auth": {}, "/parts": {}, "/members": {}, "/bills": {}, "/returns": {},
		"/reports": {}, "/company": {}, "/branches": {}, "/pos": {}, "/promotions": {},
		"/addresses": {}, "/users": {}, "/user-branches": {}, "/transfers": {},
		"/stock-counts": {}, "/daily-closes": {}, "/cash-reconciliations": {},
		"/pos-mirror": {},
	}

	// Reuse staticDir declared earlier for the /assets/qr-image handler.
	if staticDir == "" {
		staticDir = "static"
	}
	absStatic, _ := filepath.Abs(staticDir)
	if cfg.ServeStatic {
		if info, err := os.Stat(absStatic); err != nil || !info.IsDir() {
			log.Printf("Static serving enabled but STATIC_FILES_PATH=%q is not available; SPA fallback will return JSON 404 until files exist", staticDir)
		}
	}

	r.NoRoute(func(c *gin.Context) {
		method := c.Request.Method
		if method != http.MethodGet && method != http.MethodHead {
			c.JSON(http.StatusNotFound, gin.H{"error": "not_found"})
			return
		}

		reqPath := c.Request.URL.Path

		// Exact-match known API roots (e.g. /health typo'd path) → JSON 404
		if _, isAPI := exactAPIPaths[reqPath]; isAPI {
			c.JSON(http.StatusNotFound, gin.H{"error": "not_found"})
			return
		}
		for _, p := range apiPrefixes {
			if strings.HasPrefix(reqPath, p) {
				c.JSON(http.StatusNotFound, gin.H{"error": "not_found"})
				return
			}
		}

		if !cfg.ServeStatic {
			c.JSON(http.StatusNotFound, gin.H{"error": "not_found"})
			return
		}

		// Resolve target file inside staticDir, guarding against path traversal.
		// filepath.Rel returns "../..." when target escapes absStatic — reject
		// those cases. This is more robust than a string-prefix check (handles
		// case-insensitive filesystems and trailing-separator quirks).
		cleaned := filepath.Clean("/" + strings.TrimPrefix(reqPath, "/"))
		target := filepath.Join(absStatic, cleaned)
		rel, relErr := filepath.Rel(absStatic, target)
		if relErr != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
			c.JSON(http.StatusNotFound, gin.H{"error": "not_found"})
			return
		}

		if info, err := os.Stat(target); err == nil && !info.IsDir() {
			c.File(target)
			return
		}

		// SPA fallback: any unknown path (no extension match, not API) → index.html
		indexPath := filepath.Join(absStatic, "index.html")
		if info, err := os.Stat(indexPath); err == nil && !info.IsDir() {
			c.File(indexPath)
			return
		}

		c.JSON(http.StatusNotFound, gin.H{"error": "not_found"})
	})

	return r
}
