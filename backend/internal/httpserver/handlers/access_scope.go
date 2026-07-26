package handlers

import (
	"strings"

	"backend/internal/repository"

	"github.com/gin-gonic/gin"
)

func currentRequestUser(c *gin.Context) *repository.User {
	value, _ := c.Get("user")
	user, _ := value.(*repository.User)
	return user
}

func canReadAllOperationalData(c *gin.Context) bool {
	user := currentRequestUser(c)
	return user != nil && (user.IsSuperuser || user.RoleID == "role.admin")
}

func canReadOperationalRecord(c *gin.Context, branchID, posID string) bool {
	if canReadAllOperationalData(c) {
		return true
	}
	sessionBranch, _ := c.Get("branch_id")
	currentBranch, _ := sessionBranch.(string)
	if strings.TrimSpace(currentBranch) == "" || currentBranch != branchID {
		return false
	}
	user := currentRequestUser(c)
	if user != nil && isPOSRole(user) {
		sessionPOS, _ := c.Get("pos_id")
		currentPOS, _ := sessionPOS.(string)
		return strings.TrimSpace(currentPOS) != "" && currentPOS == posID
	}
	return true
}

func canReadOperationalBranch(c *gin.Context, branchID string) bool {
	if canReadAllOperationalData(c) {
		return true
	}
	sessionBranch, _ := c.Get("branch_id")
	currentBranch, _ := sessionBranch.(string)
	return strings.TrimSpace(currentBranch) != "" && currentBranch == branchID
}

func canWriteOperationalRecord(c *gin.Context, branchID, posID string) bool {
	sessionBranch, _ := c.Get("branch_id")
	currentBranch, _ := sessionBranch.(string)
	sessionPOS, _ := c.Get("pos_id")
	currentPOS, _ := sessionPOS.(string)
	return strings.TrimSpace(currentBranch) != "" &&
		strings.TrimSpace(currentPOS) != "" &&
		currentBranch == branchID &&
		currentPOS == posID
}
