//go:build !windows

package printer

import "errors"

// HardwareSupported reports whether this host has a real printer transport.
// A cloud server cannot reach the Windows POS's local LPT/USB printer.
func HardwareSupported() bool { return false }

// PrintRaw must never report a development file write as successful printing.
func PrintRaw(target string, data []byte) error {
	return errors.New("printer_host_unsupported: use browser printing or a local Windows print service")
}
