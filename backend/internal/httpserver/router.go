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
	}
	// Create bill requires write permission
	billsWrite := r.Group("/bills")
	billsWrite.Use(authMw.RequirePermission("bills", "write"))
	{
		billsWrite.POST("", billsHandler.Create)
	}

	// Fallback 404
	r.NoRoute(func(c *gin.Context) {
		c.JSON(http.StatusNotFound, gin.H{"error": "not_found"})
	})

	return r
}


