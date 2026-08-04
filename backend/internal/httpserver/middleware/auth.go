package middleware

import (
	"context"
	"errors"
	"net/http"
	"os"
	"strings"
	"time"

	"backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type AuthMiddleware struct {
	users    repository.UserRepository
	rbac     repository.RBACRepository
	sessions repository.SessionRepository
}

func NewAuthMiddleware(users repository.UserRepository, rbac repository.RBACRepository, sessions repository.SessionRepository) *AuthMiddleware {
	return &AuthMiddleware{
		users:    users,
		rbac:     rbac,
		sessions: sessions,
	}
}

func extractBearerToken(c *gin.Context) string {
	authHeader := c.GetHeader("Authorization")
	if authHeader == "" {
		return ""
	}
	parts := strings.SplitN(authHeader, " ", 2)
	if len(parts) != 2 {
		return ""
	}
	if !strings.EqualFold(parts[0], "Bearer") {
		return ""
	}
	return strings.TrimSpace(parts[1])
}

func isDevelopmentEnv() bool {
	// Support multiple common env keys
	v := strings.ToLower(strings.TrimSpace(os.Getenv("APP_ENV")))
	if v == "" {
		v = strings.ToLower(strings.TrimSpace(os.Getenv("ENV")))
	}
	if v == "" {
		v = strings.ToLower(strings.TrimSpace(os.Getenv("GO_ENV")))
	}
	return v == "development" || v == "dev"
}

func (m *AuthMiddleware) RequireAuth() gin.HandlerFunc {
	return func(c *gin.Context) {
		token := extractBearerToken(c)
		if token == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "missing_token"})
			return
		}

		// DEV BYPASS: allow a fixed mock token for local development only.
		if isDevelopmentEnv() && token == "mock-admin-token" {
			// Prefer loading the seeded admin user.
			user, err := m.users.GetByUsername(c.Request.Context(), "admin")
			if err == nil && user != nil {
				if !user.IsActive {
					c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "user_inactive"})
					return
				}
				c.Set("user", user)
				// mimic session context keys expected by handlers
				c.Set("session_id", token)
				c.Set("branch_id", "00000")
				c.Set("pos_id", "POS001")
				c.Next()
				return
			}
		}

		now := time.Now().UTC()

		sess, user, err := m.sessions.GetValidWithUserByID(c.Request.Context(), token)
		if err != nil {
			if errors.Is(err, repository.ErrSessionPending) {
				c.AbortWithStatusJSON(http.StatusLocked, gin.H{"error": "session_pending"})
				return
			}
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid_or_expired_session"})
			return
		}

		if !user.IsActive {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "user_inactive"})
			return
		}
		go m.touchSession(sess.ID, now)

		c.Set("user", user)
		c.Set("session_id", sess.ID)
		c.Set("branch_id", sess.BranchID)
		c.Set("pos_id", sess.POSID)
		c.Next()
	}
}

func (m *AuthMiddleware) RequirePermission(resource, action string) gin.HandlerFunc {
	return func(c *gin.Context) {
		token := extractBearerToken(c)
		if token == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "missing_token"})
			return
		}

		// DEV BYPASS: allow a fixed mock token for local development only.
		if isDevelopmentEnv() && token == "mock-admin-token" {
			user, err := m.users.GetByUsername(c.Request.Context(), "admin")
			if err == nil && user != nil {
				if !user.IsActive {
					c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "user_inactive"})
					return
				}
				c.Set("user", user)
				c.Set("session_id", token)
				c.Set("branch_id", "00000")
				c.Set("pos_id", "POS001")
				c.Next()
				return
			}
		}

		now := time.Now().UTC()

		sess, user, err := m.sessions.GetValidWithUserByID(c.Request.Context(), token)
		if err != nil {
			if errors.Is(err, repository.ErrSessionPending) {
				c.AbortWithStatusJSON(http.StatusLocked, gin.H{"error": "session_pending"})
				return
			}
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid_or_expired_session"})
			return
		}

		if !user.IsActive {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "user_inactive"})
			return
		}
		go m.touchSession(sess.ID, now)

		allowed, err := m.rbac.UserHasPermission(c.Request.Context(), sess.UserID, resource, action)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{"error": "rbac_error"})
			return
		}
		if !allowed {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "forbidden"})
			return
		}

		c.Set("user", user)
		c.Set("session_id", sess.ID)
		c.Set("branch_id", sess.BranchID)
		c.Set("pos_id", sess.POSID)

		c.Next()
	}
}

func (m *AuthMiddleware) touchSession(sessionID string, now time.Time) {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	_ = m.sessions.Touch(ctx, sessionID, now)
}
