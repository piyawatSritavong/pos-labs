//go:build windows

package printer

import (
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// PrintRaw sends `data` (raw bytes, typically ESC-POS) to a Windows printer.
//
// `target` may be one of:
//   - A port name like "LPT1" / "LPT2" / "COM1" — written by staging a
//     binary temp file and running `cmd /C copy /B <tempfile> LPT1`. This
//     matches the verified production Windows POS behavior.
//   - A printer share name like "POS 80mm LPT1" — sent through the spooler
//     by spawning `cmd /C copy /B tempfile "\\localhost\<name>"`.
//
// Returns a wrapped error on failure with enough context for the operator
// to debug from the backend log.
func PrintRaw(target string, data []byte) error {
	target = strings.TrimSpace(target)
	if target == "" {
		return fmt.Errorf("printer: target is empty (set RECEIPT_PRINTER_PORT=LPT1 in .env)")
	}

	// 1) Port-style target — open the device path directly.
	if isPortName(target) {
		return writeToPort(target, data)
	}

	// 2) Otherwise treat as a printer share name on localhost.
	return writeToShare(target, data)
}

func isPortName(t string) bool {
	_, ok := normalizePortName(t)
	return ok
}

func normalizePortName(t string) (string, bool) {
	upper := strings.ToUpper(strings.TrimSpace(t))
	upper = strings.TrimPrefix(upper, `\\.\`)
	upper = strings.TrimPrefix(upper, "//./")
	upper = strings.TrimSuffix(upper, ":")
	if upper == "" {
		return "", false
	}
	prefix := ""
	switch {
	case strings.HasPrefix(upper, "LPT"):
		prefix = "LPT"
	case strings.HasPrefix(upper, "COM"):
		prefix = "COM"
	default:
		return "", false
	}
	digits := strings.TrimPrefix(upper, prefix)
	if digits == "" {
		return "", false
	}
	for _, ch := range digits {
		if ch < '0' || ch > '9' {
			return "", false
		}
	}
	return prefix + digits, true
}

func writeToPort(target string, data []byte) error {
	port, ok := normalizePortName(target)
	if !ok {
		return fmt.Errorf("printer: invalid port target %q", target)
	}

	tmpFile, err := os.CreateTemp(os.TempDir(), "pos-printer-*.bin")
	if err != nil {
		return fmt.Errorf("printer: create temp file for %s: %w", port, err)
	}
	tmpPath := tmpFile.Name()
	defer func() {
		_ = tmpFile.Close()
		_ = os.Remove(tmpPath)
	}()
	if _, err := tmpFile.Write(data); err != nil {
		return fmt.Errorf("printer: write temp file %s for %s: %w", tmpPath, port, err)
	}
	if err := tmpFile.Close(); err != nil {
		return fmt.Errorf("printer: close temp file %s for %s: %w", tmpPath, port, err)
	}

	cmd := exec.Command("cmd", "/C", "copy", "/B", filepath.Clean(tmpPath), port)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("printer: copy /B %s -> %s failed: %w (output: %s)",
			tmpPath, port, err, strings.TrimSpace(string(output)))
	}
	log.Printf("printer: copied %d bytes to port %s (output: %s)",
		len(data), port, strings.TrimSpace(string(output)))
	return nil
}

func writeToShare(name string, data []byte) error {
	// Stage the bytes in a temp file then `copy /B` to the share. We can't
	// pipe via stdin into `copy` reliably, so the temp-file hop is required.
	tmpDir := os.TempDir()
	tmpFile, err := os.CreateTemp(tmpDir, "pos-receipt-*.bin")
	if err != nil {
		return fmt.Errorf("printer: create temp file: %w", err)
	}
	tmpPath := tmpFile.Name()
	defer func() {
		_ = tmpFile.Close()
		_ = os.Remove(tmpPath)
	}()
	if _, err := tmpFile.Write(data); err != nil {
		return fmt.Errorf("printer: write temp file %s: %w", tmpPath, err)
	}
	if err := tmpFile.Close(); err != nil {
		return fmt.Errorf("printer: close temp file %s: %w", tmpPath, err)
	}

	share := fmt.Sprintf(`\\localhost\%s`, name)
	cmd := exec.Command("cmd", "/C", "copy", "/B", filepath.Clean(tmpPath), share)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("printer: copy /B %s -> %s failed: %w (output: %s)",
			tmpPath, share, err, strings.TrimSpace(string(output)))
	}
	log.Printf("printer: copied %d bytes to share %s (output: %s)",
		len(data), share, strings.TrimSpace(string(output)))
	return nil
}
