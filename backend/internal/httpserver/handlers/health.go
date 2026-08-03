package handlers

import (
	"context"
	"database/sql"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

type HealthHandler struct {
	db *sql.DB
}

func NewHealthHandler(db *sql.DB) *HealthHandler {
	return &HealthHandler{db: db}
}

func (h *HealthHandler) Health(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

func (h *HealthHandler) Ready(c *gin.Context) {
	// Create a context with timeout for the database query
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	// Verify connectivity and expose the canonical migration state so a deploy
	// cannot be considered ready while its schema is dirty or behind.
	var version int
	var dirty bool
	err := h.db.QueryRowContext(ctx, `
		SELECT version, dirty FROM schema_migrations LIMIT 1
	`).Scan(&version, &dirty)
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"status": "unhealthy", "db": "down"})
		return
	}
	if dirty {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status":           "unhealthy",
			"db":               "up",
			"migrationVersion": version,
			"migrationDirty":   true,
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status":           "ok",
		"db":               "up",
		"migrationVersion": version,
		"migrationDirty":   false,
	})
}
