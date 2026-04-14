package handlers

import (
	"encoding/json"
	"strings"

	"github.com/gin-gonic/gin"
)

func attachPaymentOutput(target gin.H, paymentMethod, paymentRef string) {
	target["paymentMethod"] = paymentMethod
	target["paymentRef"] = paymentRef

	if meta := parsePaymentMeta(paymentRef); meta != nil {
		target["paymentMeta"] = meta
	}
}

func parsePaymentMeta(raw string) interface{} {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return nil
	}

	var decoded interface{}
	if err := json.Unmarshal([]byte(trimmed), &decoded); err != nil {
		return nil
	}

	switch decoded.(type) {
	case map[string]interface{}, []interface{}:
		return decoded
	default:
		return nil
	}
}
