package middleware

import (
	"strings"

	"backend/internal/config"

	"github.com/gin-gonic/gin"
)

// CORS returns a CORS middleware that is environment-aware
func CORS(cfg config.Config) gin.HandlerFunc {
	allowedOrigins := parseAllowedOrigins(cfg.CORSAllowedOrigins)
	return func(c *gin.Context) {
		origin := c.Request.Header.Get("Origin")

		allowed := originAllowed(origin, allowedOrigins, cfg)
		if allowed && origin != "" {
			c.Header("Access-Control-Allow-Origin", origin)
			c.Header("Vary", "Origin")
		}

		if allowed {
			if cfg.CORSAllowCredentials {
				c.Header("Access-Control-Allow-Credentials", "true")
			}
			c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, PATCH, OPTIONS")
			c.Header("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Requested-With, X-POS-Secret")
			c.Header("Access-Control-Expose-Headers", "Content-Length")
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

func parseAllowedOrigins(raw string) []string {
	if raw == "" {
		return nil
	}
	parts := strings.Split(raw, ",")
	origins := make([]string, 0, len(parts))
	for _, part := range parts {
		origin := strings.TrimSpace(part)
		if origin != "" {
			origins = append(origins, origin)
		}
	}
	return origins
}

func originAllowed(origin string, allowedOrigins []string, cfg config.Config) bool {
	if origin == "" {
		return false
	}
	for _, allowedOrigin := range allowedOrigins {
		if origin == allowedOrigin {
			return true
		}
	}
	if !cfg.IsProduction() {
		return strings.HasPrefix(origin, "http://localhost:") ||
			strings.HasPrefix(origin, "http://127.0.0.1:") ||
			strings.HasPrefix(origin, "https://localhost:") ||
			strings.HasPrefix(origin, "https://127.0.0.1:")
	}
	return false
}
