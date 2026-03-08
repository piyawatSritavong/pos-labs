package httpserver

import (
	"database/sql"
	"net/http"
	"time"

	"backend/internal/config"
	"backend/internal/httpserver/handlers"
	"backend/internal/httpserver/middleware"
	"backend/internal/repository"

	"github.com/gin-gonic/gin"
    "github.com/gin-contrib/cors"
)

func NewRouter(cfg config.Config, db *sql.DB) *gin.Engine {
	if cfg.Env == "production" {
		gin.SetMode(gin.ReleaseMode)
	}

	r := gin.New()
	// Add CORS middleware to correctly handle browser preflight OPTIONS requests
	r.Use(cors.New(cors.Config{
		AllowOrigins:     []string{"*"},
		AllowMethods:     []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Origin", "Content-Length", "Content-Type", "Authorization"},
		ExposeHeaders:    []string{"Content-Length"},
		AllowCredentials: false,
		MaxAge: 12 * time.Hour,
	}))
	r.Use(gin.Logger(), gin.Recovery())

	// CORS middleware (environment-aware)
	r.Use(middleware.CORS(cfg))

	userRepo := repository.NewUserRepository(db)
	rbacRepo := repository.NewRBACRepository(db)
	sessionRepo := repository.NewSessionRepository(db)

	authMw := middleware.NewAuthMiddleware(userRepo, rbacRepo, sessionRepo)

	// Health
	healthHandler := handlers.NewHealthHandler(db)
	r.GET("/health", healthHandler.Health)

	// Repositories needed for auth handler
	branchRepo := repository.NewBranchRepository(db)
	posRepo := repository.NewPOSRepository(db)
	userBranchRepo := repository.NewUserBranchRepository(db)

	// Auth
	authHandler := handlers.NewAuthHandler(userRepo, sessionRepo, userBranchRepo, branchRepo, posRepo, cfg.SessionDurationParsed())
	authGroup := r.Group("/auth")
	{
		authGroup.POST("/login", authHandler.Login)
		authGroup.POST("/logout", authMw.RequireAuth(), authHandler.Logout)
		authGroup.GET("/me", authMw.RequireAuth(), authHandler.Me)
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
	partsHandler := handlers.NewPartsHandler(partRepo)
	parts := r.Group("/parts")
	parts.Use(authMw.RequirePermission("parts", "read"))
	{
		parts.GET("", partsHandler.List)
		parts.GET("/search", partsHandler.Search)
		parts.GET("/:code", partsHandler.Get)
	}

	billRepo := repository.NewBillRepository(db)
	companyRepo := repository.NewCompanyRepository(db)
	promotionRepo := repository.NewPromotionRepository(db)
	addressRepo := repository.NewAddressRepository(db)
	billsHandler := handlers.NewBillsHandler(billRepo, branchRepo, posRepo, partRepo, companyRepo, promotionRepo, addressRepo)
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
		billsWrite.PUT("/:id/add-discount", billsHandler.AddDiscount)             // apply discount to bill
		billsWrite.PUT("/:id/remove-discount", billsHandler.RemoveDiscount)       // remove discount from bill
		billsWrite.PUT("/:id/hold", billsHandler.Hold)                            // hold bill
		billsWrite.PUT("/switch", billsHandler.SwitchBill)                        // switch bills: if currentBillId not provided, create new bill; otherwise hold current and resume target
		billsWrite.PUT("/:id/payment", billsHandler.Payment)                      // process payment
		billsWrite.PUT("/:id/cancel", billsHandler.Cancel)                        // cancel bill
	}
	billsDelete := r.Group("/bills")
	billsDelete.Use(authMw.RequirePermission("bills", "delete"))
	billsDelete.Use(middleware.RequirePOSBranch()) // Bills endpoints require POS session with branchId and posId
	{
		billsDelete.DELETE("/:id", billsHandler.Delete) // delete bill permanently
	}

	// Reports (CSV exports)
	reportRepo := repository.NewReportRepository(db)
	reportsHandler := handlers.NewReportsHandler(reportRepo)
	reports := r.Group("/reports")
	{
		reports.GET("/bills", authMw.RequirePermission("reports_bill", "read"), reportsHandler.BillsReport)              // bills report with date filter
		reports.GET("/parts", authMw.RequirePermission("reports_parts", "read"), reportsHandler.PartsReport)             // all parts report
		reports.GET("/inventory", authMw.RequirePermission("reports_inventory", "read"), reportsHandler.InventoryReport) // all inventory report
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

	// Fallback 404
	r.NoRoute(func(c *gin.Context) {
		c.JSON(http.StatusNotFound, gin.H{"error": "not_found"})
	})

	return r
}
