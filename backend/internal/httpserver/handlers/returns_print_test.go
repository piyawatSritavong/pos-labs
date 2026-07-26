package handlers

import "testing"

func TestReturnNotesHandlerPrintIdempotency(t *testing.T) {
	h := NewReturnNotesHandler(nil, nil, nil, nil, nil, nil, nil)

	if !h.beginPrint("return:CN-001") {
		t.Fatal("first return receipt print should be allowed")
	}
	if h.beginPrint("return:CN-001") {
		t.Fatal("duplicate return receipt print should be suppressed while key is tracked")
	}

	h.completePrint("return:CN-001", false)
	if !h.beginPrint("return:CN-001") {
		t.Fatal("failed return receipt print should release key for retry")
	}

	h.completePrint("return:CN-001", true)
	if h.beginPrint("return:CN-001") {
		t.Fatal("successful return receipt print should keep key suppressed")
	}
}
