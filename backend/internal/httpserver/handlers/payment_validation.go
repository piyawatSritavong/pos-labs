package handlers

import (
	"encoding/json"
	"fmt"
	"math"
	"strings"
	"time"
)

func normalizeBillPaymentMethod(raw string) string {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "", "cash":
		return "cash"
	case "bank", "transfer", "qr", "qr_code":
		return "bank"
	case "credit_term", "credit-term", "creditterm":
		return "credit_term"
	case "exchange":
		return "exchange"
	default:
		return ""
	}
}

func validateAndSerializePayment(
	paymentMethod string,
	paymentRef string,
	paymentMeta interface{},
	billTotal float64,
) (string, string, error) {
	method := normalizeBillPaymentMethod(paymentMethod)
	if method == "" {
		return "", "", fmt.Errorf("unsupported_payment_method")
	}
	serializedRef := strings.TrimSpace(paymentRef)

	var meta interface{}
	if paymentMeta != nil {
		raw, err := json.Marshal(paymentMeta)
		if err != nil {
			return "", "", fmt.Errorf("invalid_payment_meta")
		}
		serializedRef = string(raw)
		meta = paymentMeta
	} else if parsed := parsePaymentMeta(serializedRef); parsed != nil {
		meta = parsed
	}

	if method == "credit_term" {
		if billTotal <= 0 {
			return "", "", fmt.Errorf("credit_term_requires_positive_total")
		}
		metaMap, ok := meta.(map[string]interface{})
		if !ok {
			return "", "", fmt.Errorf("credit_term_requires_payment_meta")
		}
		if err := validateCreditTermMeta(metaMap, billTotal); err != nil {
			return "", "", err
		}
	}

	return method, serializedRef, nil
}

func validateCreditTermMeta(meta map[string]interface{}, billTotal float64) error {
	deliveryDate, _ := meta["deliveryDate"].(string)
	if _, err := time.Parse("2006-01-02", strings.TrimSpace(deliveryDate)); err != nil {
		return fmt.Errorf("invalid_credit_term_delivery_date")
	}

	rawInstallments, ok := meta["installments"].([]interface{})
	if !ok || len(rawInstallments) == 0 {
		return fmt.Errorf("missing_credit_term_installments")
	}

	total := 0.0
	for _, raw := range rawInstallments {
		installment, ok := raw.(map[string]interface{})
		if !ok {
			return fmt.Errorf("invalid_credit_term_installment")
		}

		dueDate, _ := installment["dueDate"].(string)
		if _, err := time.Parse("2006-01-02", strings.TrimSpace(dueDate)); err != nil {
			return fmt.Errorf("invalid_credit_term_due_date")
		}

		amount, ok := toFloat64(installment["amount"])
		if !ok || amount <= 0 {
			return fmt.Errorf("invalid_credit_term_installment_amount")
		}
		total += amount
	}

	if math.Abs(total-billTotal) > 0.01 {
		return fmt.Errorf("credit_term_amount_mismatch")
	}

	return nil
}

func toFloat64(value interface{}) (float64, bool) {
	switch typed := value.(type) {
	case float64:
		return typed, true
	case float32:
		return float64(typed), true
	case int:
		return float64(typed), true
	case int32:
		return float64(typed), true
	case int64:
		return float64(typed), true
	case json.Number:
		parsed, err := typed.Float64()
		if err != nil {
			return 0, false
		}
		return parsed, true
	case string:
		parsed, err := json.Number(strings.TrimSpace(typed)).Float64()
		if err != nil {
			return 0, false
		}
		return parsed, true
	default:
		return 0, false
	}
}
