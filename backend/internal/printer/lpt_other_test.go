//go:build !windows

package printer

import "testing"

func TestNonWindowsPrinterFailsClosed(t *testing.T) {
	if HardwareSupported() {
		t.Fatal("a non-Windows host must not advertise a physical printer")
	}
	if err := PrintRaw("LPT1", []byte("test receipt")); err == nil {
		t.Fatal("writing a development file must never be reported as printing")
	}
	if result, err := KickCashDrawer("LPT1", nil); err == nil || result.Method != "unsupported" {
		t.Fatal("a cloud host must not claim that the POS drawer was opened")
	}
}
