package httpserver

import (
	"database/sql"
	"net/http"

	"backend/internal/config"
	"backend/internal/httpserver/handlers"
	"backend/internal/httpserver/middleware"
	"backend/internal/repository"

	"github.com/gin-gonic/gin"
)

func NewRouter(cfg config.Config, db *sql.DB) *gin.Engine {
	if cfg.Env == "production" {
		gin.SetMode(gin.ReleaseMode)
	}

	r := gin.New()
	r.Use(gin.Logger(), gin.Recovery())

	userRepo := repository.NewUserRepository(db)
	rbacRepo := repository.NewRBACRepository(db)
	sessionRepo := repository.NewSessionRepository(db)

	authMw := middleware.NewAuthMiddleware(userRepo, rbacRepo, sessionRepo)

	// Health
	healthHandler := handlers.NewHealthHandler(db)
	r.GET("/health", healthHandler.Health)

	// Auth
	authHandler := handlers.NewAuthHandler(userRepo, sessionRepo, cfg.SessionDurationParsed())
	authGroup := r.Group("/auth")
	{
		authGroup.POST("/login", authHandler.Login)
		authGroup.POST("/logout", authMw.RequireAuth(), authHandler.Logout)
		authGroup.GET("/me", authMw.RequireAuth(), authHandler.Me)
	}

	// Protected resources examples
	partRepo := repository.NewPartRepository(db)
	partsHandler := handlers.NewPartsHandler(partRepo)
	parts := r.Group("/parts")
	parts.Use(authMw.RequirePermission("parts", "read"))
	{
		parts.GET("", partsHandler.List)
		parts.GET("/:code", partsHandler.Get)
	}

	billRepo := repository.NewBillRepository(db)
	billsHandler := handlers.NewBillsHandler(billRepo)
	bills := r.Group("/bills")
	bills.Use(authMw.RequirePermission("bills", "read"))
	{
		bills.GET("", billsHandler.List)
		bills.GET("/:id", billsHandler.Get)
	}
	// Create bill requires write permission
	billsWrite := r.Group("/bills")
	billsWrite.Use(authMw.RequirePermission("bills", "write"))
	{
		billsWrite.POST("", billsHandler.Create)
		billsWrite.PUT("/:id/add-item", billsHandler.AddItem) // add item to bill
		billsWrite.PUT("/:id/remove-item", billsHandler.RemoveItem) // remove item from bill
		billsWrite.PUT("/:id/add-discount", billsHandler.AddDiscount) // apply discount to bill
		billsWrite.PUT("/:id/remove-discount", billsHandler.RemoveDiscount) // remove discount from bill
		billsWrite.PUT("/:id/hold", billsHandler.Hold) // hold bill
		billsWrite.PUT("/:id/resume", billsHandler.Resume) // resume held bill
		billsWrite.PUT("/:id/checkout", billsHandler.Checkout) // complete bill
		billsWrite.PUT("/:id/payment", billsHandler.Payment) // process payment
	}

	// Company (read and update only)
	companyRepo := repository.NewCompanyRepository(db)
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
	branchRepo := repository.NewBranchRepository(db)
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
	posRepo := repository.NewPOSRepository(db)
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
		posWrite.PUT("/:id", posHandler.Update)
	}
	posDelete := r.Group("/pos")
	posDelete.Use(authMw.RequirePermission("pos", "delete"))
	{
		posDelete.DELETE("/:id", posHandler.Delete)
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
	userBranchRepo := repository.NewUserBranchRepository(db)
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


