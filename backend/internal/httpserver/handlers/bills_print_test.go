package handlers

import "testing"

func TestBillsHandlerPrintIdempotency(t *testing.T) {
	h := NewBillsHandler(nil, nil, nil, nil, nil, nil, nil, nil, nil)

	if !h.beginPrint("checkout:BILL-001") {
		t.Fatal("first print should be allowed")
	}
	if h.beginPrint("checkout:BILL-001") {
		t.Fatal("duplicate print should be suppressed while key is tracked")
	}

	h.completePrint("checkout:BILL-001", false)
	if !h.beginPrint("checkout:BILL-001") {
		t.Fatal("failed print should release key for retry")
	}

	h.completePrint("checkout:BILL-001", true)
	if h.beginPrint("checkout:BILL-001") {
		t.Fatal("successful print should keep key suppressed")
	}
}
