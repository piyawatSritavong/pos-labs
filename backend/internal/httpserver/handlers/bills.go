package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

type BillsHandler struct{}

func NewBillsHandler() *BillsHandler {
	return &BillsHandler{}
}

// List is a placeholder endpoint to show protected resource wiring.
func (h *BillsHandler) List(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"items": []interface{}{},
	})
}


