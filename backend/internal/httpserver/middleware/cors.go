package middleware

import (
	"os"
	"strings"

	"backend/internal/config"

	"github.com/gin-gonic/gin"
)

// CORS returns a CORS middleware that is environment-aware
func CORS(cfg config.Config) gin.HandlerFunc {
	return func(c *gin.Context) {
		origin := c.Request.Header.Get("Origin")

		// Determine allowed origins based on environment
		var allowedOrigins []string
		if cfg.Env == "development" {
			// Development: Allow common localhost origins
			allowedOrigins = []string{
				"http://localhost:3000",
				"http://localhost:3001",
				"http://localhost:5173", // Vite default
				"http://localhost:8080",
				"http://localhost:8081",
				"http://127.0.0.1:3000",
				"http://127.0.0.1:5173",
				"http://127.0.0.1:8080",
			}
		} else {
			// Production: Use environment variable for allowed origins
			// Format: comma-separated list, e.g., "https://app.example.com,https://www.example.com"
			allowedOriginsStr := getEnv("CORS_ALLOWED_ORIGINS", "")
			if allowedOriginsStr != "" {
				allowedOrigins = strings.Split(allowedOriginsStr, ",")
				// Trim whitespace from each origin
				for i := range allowedOrigins {
					allowedOrigins[i] = strings.TrimSpace(allowedOrigins[i])
				}
			} else {
				// Fallback: no origins allowed if not configured
				allowedOrigins = []string{}
			}
		}

		// Check if origin is allowed
		allowed := false
		if origin != "" {
			for _, allowedOrigin := range allowedOrigins {
				if origin == allowedOrigin {
					allowed = true
					break
				}
			}
		}

		// Set CORS headers
		if allowed {
			c.Header("Access-Control-Allow-Origin", origin)
		} else if cfg.Env == "development" && origin != "" {
			// In development, allow any localhost origin even if not in the list
			// This provides flexibility during development
			if strings.HasPrefix(origin, "http://localhost:") || 
			   strings.HasPrefix(origin, "http://127.0.0.1:") {
				c.Header("Access-Control-Allow-Origin", origin)
				allowed = true
			}
		}

		if allowed {
			c.Header("Access-Control-Allow-Credentials", "true")
			c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, PATCH, OPTIONS")
			c.Header("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Requested-With")
			c.Header("Access-Control-Max-Age", "3600")
		}

		// Handle preflight requests
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}

		c.Next()
	}
}

// getEnv is a helper to get environment variables (same pattern as config package)
func getEnv(key, def string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return def
}

