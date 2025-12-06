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
	userBranches     repository.UserBranchRepository
	branches         repository.BranchRepository
	pos              repository.POSRepository
	sessionDuration  time.Duration
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
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`
	BranchID string `json:"branchId" binding:"omitempty"`
	POSID    string `json:"posId" binding:"omitempty"`
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

	// Delete any existing session for this user (only 1 session per user)
	existingSessions, _ := h.sessions.GetByUserID(ctx, user.ID)
	for _, sess := range existingSessions {
		_ = h.sessions.DeleteByID(ctx, sess.ID)
	}

	var branchID, posID string

	// If branchId and posId are provided, validate them
	if req.BranchID != "" && req.POSID != "" {
		// Validate branchId exists
		_, err = h.branches.GetByID(ctx, req.BranchID)
		if err != nil {
			if repository.IsNotFoundError(err) {
				c.JSON(http.StatusBadRequest, gin.H{
					"error": "incorrect_branch_id",
					"message": "Branch ID does not exist",
				})
				return
			}
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_validate_branch"})
			return
		}

		// Validate posId exists
		_, err = h.pos.GetByID(ctx, req.POSID)
		if err != nil {
			if repository.IsNotFoundError(err) {
				c.JSON(http.StatusBadRequest, gin.H{
					"error": "incorrect_pos_id",
					"message": "POS ID does not exist",
				})
				return
			}
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_validate_pos"})
			return
		}

		// Validate user has access to this branch (unless superuser)
		if !user.IsSuperuser {
			_, err = h.userBranches.GetByUserAndBranch(ctx, user.ID, req.BranchID)
			if err != nil {
				if repository.IsNotFoundError(err) {
					c.JSON(http.StatusForbidden, gin.H{
						"error": "access_denied",
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
		"token":  sid,
		"name":   user.Name,
		"roleId": user.RoleID,
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
		"name":   user.Name,
		"roleId": user.RoleID,
		"active": user.IsActive,
	})
}


