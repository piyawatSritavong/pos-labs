package middleware

import (
	"net/http"
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

func (m *AuthMiddleware) RequireAuth() gin.HandlerFunc {
	return func(c *gin.Context) {
		token := extractBearerToken(c)
		if token == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "missing_token"})
			return
		}

		ip := c.ClientIP()
		now := time.Now().UTC()

		sess, err := m.sessions.GetValidByID(c.Request.Context(), token, ip, now)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid_or_expired_session"})
			return
		}

		_ = m.sessions.Touch(c.Request.Context(), sess.ID, now)

		user, err := m.users.GetByID(c.Request.Context(), sess.UserID)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
			return
		}
		if !user.IsActive {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "user_inactive"})
			return
		}

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

		ip := c.ClientIP()
		now := time.Now().UTC()

		sess, err := m.sessions.GetValidByID(c.Request.Context(), token, ip, now)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid_or_expired_session"})
			return
		}

		_ = m.sessions.Touch(c.Request.Context(), sess.ID, now)

		allowed, err := m.rbac.UserHasPermission(c.Request.Context(), sess.UserID, resource, action)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{"error": "rbac_error"})
			return
		}
		if !allowed {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "forbidden"})
			return
		}

		user, err := m.users.GetByID(c.Request.Context(), sess.UserID)
		if err == nil && user.IsActive {
			c.Set("user", user)
		}
		c.Set("session_id", sess.ID)
		c.Set("branch_id", sess.BranchID)
		c.Set("pos_id", sess.POSID)

		c.Next()
	}
}



