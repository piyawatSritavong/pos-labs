//go:build !windows

package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestCloudPrintingRejectsHardwareAndReleasesRetryKeys(t *testing.T) {
	gin.SetMode(gin.TestMode)
	bills := NewBillsHandler(nil, nil, nil, nil, nil, nil, nil, nil, nil)
	bills.PrinterEnabled = true
	bills.PrinterTarget = "LPT1"
	returns := NewReturnNotesHandler(nil, nil, nil, nil, nil, nil)
	returns.PrinterEnabled = true
	returns.PrinterTarget = "LPT1"
	router := gin.New()
	router.POST("/bills/:id/print", bills.PrintReceipt)
	router.POST("/return-notes/:id/print", returns.PrintReceipt)
	router.POST("/printer/test", bills.PrintTestReceipt)

	for _, path := range []string{"/bills/BILL-1/print", "/return-notes/CN-1/print", "/printer/test"} {
		t.Run(path, func(t *testing.T) {
			// Retrying the same idempotency key must not return a false 200
			// duplicate/success when the first request never reached hardware.
			for attempt := 0; attempt < 2; attempt++ {
				recorder := httptest.NewRecorder()
				request := httptest.NewRequest(http.MethodPost, path,
					strings.NewReader(`{"idempotencyKey":"same-key"}`))
				request.Header.Set("Content-Type", "application/json")
				router.ServeHTTP(recorder, request)
				if recorder.Code != http.StatusServiceUnavailable {
					t.Fatalf("attempt %d: expected 503, got %d: %s", attempt, recorder.Code, recorder.Body.String())
				}
				var response map[string]interface{}
				if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
					t.Fatal(err)
				}
				if response["error"] != "printer_host_unsupported" || response["printed"] == true {
					t.Fatalf("must not claim successful printing: %v", response)
				}
			}
		})
	}
}
