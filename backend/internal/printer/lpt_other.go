//go:build !windows

package printer

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
)

// PrintRaw on non-Windows hosts is a development stub: it writes the bytes to
// /tmp/pos-last-receipt.bin so a Mac/Linux dev can verify the ESC-POS output
// without owning a printer. Real printing only happens on the Windows POS.
func PrintRaw(target string, data []byte) error {
	dir := os.TempDir()
	path := filepath.Join(dir, "pos-last-receipt.bin")
	if err := os.WriteFile(path, data, 0o644); err != nil {
		return fmt.Errorf("printer (dev stub): write %s: %w", path, err)
	}
	log.Printf("printer (dev stub): wrote %d bytes to %s (target=%q ignored)",
		len(data), path, target)
	return nil
}
