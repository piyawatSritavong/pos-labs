package handlers

import (
	"crypto/rand"
	"encoding/hex"
	"net/http"
	"os"
	"time"

	"backend/internal/repository"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"
)

type AuthHandler struct {
	users           repository.UserRepository
	sessions        repository.SessionRepository
	userBranches    repository.UserBranchRepository
	branches        repository.BranchRepository
	pos             repository.POSRepository
	sessionDuration time.Duration
}

func NewAuthHandler(
	users repository.UserRepository,
	sessions repository.SessionRepository,
	userBranches repository.UserBranchRepository,
	branches repository.BranchRepository,
	pos repository.POSRepository,
	sessionDuration time.Duration,
) *AuthHandler {
	return &AuthHandler{
		users:           users,
		sessions:        sessions,
		userBranches:    userBranches,
		branches:        branches,
		pos:             pos,
		sessionDuration: sessionDuration,
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

	// Concurrent sessions of the same account are allowed; the clients detect
	// the overlap via GET /auth/sessions and resolve it themselves (the user
	// picks "stay" → POST /auth/sessions/revoke-others, or "leave" → logout).

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
	} else {
		// No terminal given (single shared web URL) — resolve it from the
		// account instead. No posSecret needed here: the client never chose
		// the terminal.
		// 1) The account's pinned terminal (user.default_pos_id): admin →
		//    POS003, pos1 → POS001, pos2 → POS002 — accounts on the same
		//    branch still get distinct terminals.
		if user.DefaultPOSID != "" {
			if pos, err := h.pos.GetByID(ctx, user.DefaultPOSID); err == nil && pos.IsActive {
				branchID = pos.BranchID
				posID = pos.POSID
			}
		}
		// 2) Fall back to the user's assigned branch → that branch's first
		//    active POS; superusers (no user_branch rows) get the first
		//    active POS overall.
		if posID == "" {
			userBranchID := ""
			if branches, err := h.userBranches.GetByUserID(ctx, user.ID); err == nil && len(branches) > 0 {
				userBranchID = branches[0].BranchID
			}
			if pos, err := h.pos.GetFirstActiveByBranch(ctx, userBranchID); err == nil {
				branchID = pos.BranchID
				posID = pos.POSID
			}
		}
		// If no POS exists the session simply has no terminal, as before.
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
		BranchID:  branchID,
		POSID:     posID,
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
		"roleId":  user.RoleID,
		"expires": expires.Format(time.RFC3339),
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

// sessionFreshWindow is how recently a session must have been seen to count as
// an actively-used session. Clients poll /auth/sessions every few seconds and
// RequireAuth touches last_seen_at on every request, so an open app stays
// fresh; a closed tab goes stale within this window.
const sessionFreshWindow = 45 * time.Second

// Sessions lists the current user's sessions so a client can detect a
// concurrent login of the same account. Session IDs are never returned — they
// are bearer tokens.
func (h *AuthHandler) Sessions(c *gin.Context) {
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
	currentID := c.GetString("session_id")
	now := time.Now().UTC()

	sessions, err := h.sessions.GetByUserID(c.Request.Context(), user.ID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_list_sessions"})
		return
	}

	othersActive := false
	list := make([]gin.H, 0, len(sessions))
	for _, s := range sessions {
		if !s.ExpiresAt.After(now) {
			continue
		}
		isCurrent := s.ID == currentID
		fresh := now.Sub(s.LastSeen) <= sessionFreshWindow
		if !isCurrent && fresh {
			othersActive = true
		}
		list = append(list, gin.H{
			"current":   isCurrent,
			"active":    fresh,
			"ip":        s.IP,
			"userAgent": s.UserAgent,
			"branchId":  s.BranchID,
			"posId":     s.POSID,
			"createdAt": s.CreatedAt,
			"lastSeen":  s.LastSeen,
		})
	}

	c.JSON(http.StatusOK, gin.H{"sessions": list, "othersActive": othersActive})
}

// RevokeOtherSessions deletes every other session of the current user — the
// "ให้ฉันอยู่ต่อ" action of the duplicate-login dialog. The kicked clients get
// invalid_or_expired_session on their next request.
func (h *AuthHandler) RevokeOtherSessions(c *gin.Context) {
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
	currentID := c.GetString("session_id")
	ctx := c.Request.Context()

	sessions, err := h.sessions.GetByUserID(ctx, user.ID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_list_sessions"})
		return
	}

	revoked := 0
	for _, s := range sessions {
		if s.ID == currentID {
			continue
		}
		if err := h.sessions.DeleteByID(ctx, s.ID); err == nil {
			revoked++
		}
	}

	c.JSON(http.StatusOK, gin.H{"status": "ok", "revoked": revoked})
}
