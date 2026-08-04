package handlers

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"net/http"
	"os"
	"strings"
	"time"

	"backend/internal/repository"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"
)

type AuthHandler struct {
	users        repository.UserRepository
	sessions     repository.SessionRepository
	userBranches repository.UserBranchRepository
	branches     repository.BranchRepository
	pos          repository.POSRepository
}

func NewAuthHandler(
	users repository.UserRepository,
	sessions repository.SessionRepository,
	userBranches repository.UserBranchRepository,
	branches repository.BranchRepository,
	pos repository.POSRepository,
) *AuthHandler {
	return &AuthHandler{
		users:        users,
		sessions:     sessions,
		userBranches: userBranches,
		branches:     branches,
		pos:          pos,
	}
}

// if super user or admin or non cachier user
// They no need to provide branchId and posId
// In this case, they will only be able to work with endpoints that don't need them.
type loginRequest struct {
	Username  string `json:"username" binding:"required"`
	Password  string `json:"password" binding:"required"`
	BranchID  string `json:"branchId" binding:"omitempty"`
	POSID     string `json:"posId" binding:"omitempty"`
	POSSecret string `json:"posSecret" binding:"omitempty"`
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

	ctx := c.Request.Context()

	var branchID, posID string

	// If branchId and posId are provided, validate them
	if req.BranchID != "" && req.POSID != "" {
		// Validate branchId exists
		_, err = h.branches.GetByID(ctx, req.BranchID)
		if err != nil {
			if repository.IsNotFoundError(err) {
				c.JSON(http.StatusBadRequest, gin.H{
					"error":   "incorrect_branch_id",
					"message": "Branch ID does not exist",
				})
				return
			}
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_validate_branch"})
			return
		}

		// Validate posId exists and is active
		pos, err := h.pos.GetByID(ctx, req.POSID)
		if err != nil {
			if repository.IsNotFoundError(err) {
				c.JSON(http.StatusBadRequest, gin.H{
					"error":   "incorrect_pos_id",
					"message": "POS ID does not exist",
				})
				return
			}
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_validate_pos"})
			return
		}

		// Validate POS is active
		if !pos.IsActive {
			c.JSON(http.StatusForbidden, gin.H{
				"error":   "pos_inactive",
				"message": "POS is not active",
			})
			return
		}

		// Require posSecret when posId is provided
		if req.POSSecret == "" {
			c.JSON(http.StatusBadRequest, gin.H{
				"error":   "missing_pos_secret",
				"message": "POS secret is required when logging in with posId",
			})
			return
		}

		// Allow overriding POS secret via environment variable.
		// Support both names to reduce config mismatch between frontend/backend.
		posSecretEnv := os.Getenv("POS_TERMINAL_SECRET")
		if posSecretEnv == "" {
			posSecretEnv = os.Getenv("POS_SECRET")
		}

		// Development fallback:
		// frontend default sends "default_if_needed" when POS_SECRET is not set.
		appEnv := os.Getenv("APP_ENV")
		if appEnv == "" {
			appEnv = os.Getenv("ENV")
		}
		allowDevDefaultSecret := (appEnv != "production") && req.POSSecret == "default_if_needed"

		// Validate posSecret matches
		if pos.POSSecret != req.POSSecret && req.POSSecret != posSecretEnv && !allowDevDefaultSecret {
			c.JSON(http.StatusUnauthorized, gin.H{
				"error":   "invalid_pos_secret",
				"message": "Invalid POS secret",
			})
			return
		}

		// Validate user has access to this branch (unless superuser)
		if !user.IsSuperuser {
			_, err = h.userBranches.GetByUserAndBranch(ctx, user.ID, req.BranchID)
			if err != nil {
				if repository.IsNotFoundError(err) {
					c.JSON(http.StatusForbidden, gin.H{
						"error":   "access_denied",
						"message": "User does not have access to this branch",
					})
					return
				}
				c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_check_user_branch"})
				return
			}
		}

		branchID = req.BranchID
		posID = req.POSID
	}
	// If branchId/posId are not provided, they remain empty (for non-cashier users)

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
	session := &repository.Session{
		ID:        sid,
		UserID:    user.ID,
		BranchID:  branchID,
		POSID:     posID,
		IP:        ip,
		UserAgent: ua,
		CreatedAt: now,
		ExpiresAt: nil,
		LastSeen:  now,
	}

	state, err := h.sessions.CreateForLogin(c.Request.Context(), session, now.Add(-60*time.Second))
	if errors.Is(err, repository.ErrPendingSessionExists) {
		c.JSON(http.StatusConflict, gin.H{
			"error":   "login_already_pending",
			"message": "มีคำขอเข้าสู่ระบบของบัญชีนี้รอการยืนยันอยู่แล้ว",
		})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "session_persist_failed"})
		return
	}

	// Return only session token and display info; do not expose internal IDs
	c.JSON(http.StatusOK, gin.H{
		"token":        sid,
		"name":         user.Name,
		"roleId":       user.RoleID,
		"expires":      nil,
		"sessionState": state,
	})
}

func (h *AuthHandler) VerifyPassword(c *gin.Context) {
	var req struct {
		Username string `json:"username" binding:"required"`
		Password string `json:"password" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
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
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

func (h *AuthHandler) Logout(c *gin.Context) {
	token := bearerToken(c)
	if token == "" {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
		return
	}
	_ = h.sessions.Logout(c.Request.Context(), token, time.Now().UTC())
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

func bearerToken(c *gin.Context) string {
	header := strings.TrimSpace(c.GetHeader("Authorization"))
	parts := strings.SplitN(header, " ", 2)
	if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
		return ""
	}
	return strings.TrimSpace(parts[1])
}

// SessionState is intentionally available to pending/terminal sessions so a
// waiting browser can learn the incumbent's decision without business access.
func (h *AuthHandler) SessionState(c *gin.Context) {
	token := bearerToken(c)
	if token == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "missing_token"})
		return
	}
	now := time.Now().UTC()
	state, err := h.sessions.GetSessionState(c.Request.Context(), token, now.Add(-60*time.Second), now)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid_or_expired_session"})
		return
	}
	response := gin.H{
		"state":  state.Session.Status,
		"reason": state.Session.Reason,
	}
	if state.PendingLogin != nil {
		response["pendingLogin"] = gin.H{
			"createdAt": state.PendingLogin.CreatedAt.Format(time.RFC3339),
			"ip":        state.PendingLogin.IP,
			"userAgent": state.PendingLogin.UserAgent,
		}
	}
	c.JSON(http.StatusOK, response)
}

func (h *AuthHandler) ResolveSessionConflict(c *gin.Context) {
	token := bearerToken(c)
	if token == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "missing_token"})
		return
	}
	var req struct {
		Decision string `json:"decision" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || (req.Decision != "stay" && req.Decision != "leave") {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_decision"})
		return
	}
	if err := h.sessions.ResolveConflict(c.Request.Context(), token, req.Decision, time.Now().UTC()); err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusConflict, gin.H{"error": "pending_session_not_found"})
			return
		}
		c.JSON(http.StatusConflict, gin.H{"error": "unable_to_resolve_session"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "ok", "decision": req.Decision})
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

	// Get branchId and posId from session context (set by RequireAuth middleware)
	// These are set from the session's branch_id and pos_id fields
	branchIDVal, branchExists := c.Get("branch_id")
	posIDVal, posExists := c.Get("pos_id")

	response := gin.H{
		"username": user.Username,
		"name":     user.Name,
		"roleId":   user.RoleID,
		"active":   user.IsActive,
	}

	// Include branchId if it exists in session (non-empty string)
	if branchExists && branchIDVal != nil {
		if branchID, ok := branchIDVal.(string); ok && branchID != "" {
			response["branchId"] = branchID
		}
	}

	// Include posId if it exists in session (non-empty string)
	if posExists && posIDVal != nil {
		if posID, ok := posIDVal.(string); ok && posID != "" {
			response["posId"] = posID
		}
	}

	c.JSON(http.StatusOK, response)
}
