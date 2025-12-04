package handlers

import (
	"crypto/rand"
	"encoding/hex"
	"net/http"
	"time"

	"backend/internal/repository"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"
)

type AuthHandler struct {
	users            repository.UserRepository
	sessions         repository.SessionRepository
	sessionDuration  time.Duration
}

func NewAuthHandler(users repository.UserRepository, sessions repository.SessionRepository, sessionDuration time.Duration) *AuthHandler {
	return &AuthHandler{
		users:           users,
		sessions:        sessions,
		sessionDuration: sessionDuration,
	}
}

type loginRequest struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`
}

func (h *AuthHandler) Login(c *gin.Context) {
	var req loginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request"})
		return
	}

	user, err := h.users.GetByUsername(c.Request.Context(), req.Username)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid_credentials"})
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid_credentials"})
		return
	}
	if !user.IsActive {
		c.JSON(http.StatusForbidden, gin.H{"error": "user_inactive"})
		return
	}

	// Generate opaque session ID
	sidBytes := make([]byte, 32)
	if _, err := rand.Read(sidBytes); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "session_generate_failed"})
		return
	}
	sid := hex.EncodeToString(sidBytes)

	ip := c.ClientIP()
	ua := c.GetHeader("User-Agent")
	now := time.Now().UTC()
	expires := now.Add(h.sessionDuration)

	session := &repository.Session{
		ID:        sid,
		UserID:    user.ID,
		IP:        ip,
		UserAgent: ua,
		CreatedAt: now,
		ExpiresAt: expires,
		LastSeen:  now,
	}

	if err := h.sessions.Create(c.Request.Context(), session); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "session_persist_failed"})
		return
	}

	// Return only session token and display info; do not expose internal IDs
	c.JSON(http.StatusOK, gin.H{
		"token":   sid,
		"name":    user.Name,
		"role_id": user.RoleID,
		"expires": expires.Format(time.RFC3339),
	})
}

func (h *AuthHandler) Logout(c *gin.Context) {
	token := c.GetHeader("Authorization")
	if token == "" {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
		return
	}
	// Expect "Bearer <token>"
	if len(token) > 7 && token[:7] == "Bearer " {
		token = token[7:]
	}
	if token != "" {
		_ = h.sessions.DeleteByID(c.Request.Context(), token)
	}
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

func (h *AuthHandler) Me(c *gin.Context) {
	userVal, exists := c.Get("user")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	user, ok := userVal.(*repository.User)
	if !ok {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "user_cast_error"})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"name":    user.Name,
		"role_id": user.RoleID,
		"active":  user.IsActive,
	})
}


