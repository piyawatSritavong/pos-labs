package middleware

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

// RequirePOSBranch ensures that the session has both branchId and posId
// This middleware should be used for bills endpoints that require POS context
func RequirePOSBranch() gin.HandlerFunc {
	return func(c *gin.Context) {
		branchIDVal, exists := c.Get("branch_id")
		if !exists {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
				"error": "session_not_allow",
				"message": "Session does not have branchId. Bills endpoints require a POS session with branchId and posId.",
			})
			return
		}

		branchID, ok := branchIDVal.(string)
		if !ok || branchID == "" {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
				"error": "session_not_allow",
				"message": "Session does not have branchId. Bills endpoints require a POS session with branchId and posId.",
			})
			return
		}

		posIDVal, exists := c.Get("pos_id")
		if !exists {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
				"error": "session_not_allow",
				"message": "Session does not have posId. Bills endpoints require a POS session with branchId and posId.",
			})
			return
		}

		posID, ok := posIDVal.(string)
		if !ok || posID == "" {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
				"error": "session_not_allow",
				"message": "Session does not have posId. Bills endpoints require a POS session with branchId and posId.",
			})
			return
		}

		c.Next()
	}
}

