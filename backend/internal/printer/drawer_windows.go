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

const defaultDrawerBinPath = `C:\POSApp\drawer.bin`

type DrawerKickResult struct {
	Target  string
	Method  string
	BinPath string
	Bytes   int
	Output  string
}

// KickCashDrawer sends only the ESC/POS drawer pulse. On Windows port targets
// it intentionally uses the same PowerShell + cmd copy path that was verified
// on the production POS machine.
func KickCashDrawer(target string, command []byte) (DrawerKickResult, error) {
	target = strings.TrimSpace(target)
	data := BuildDrawerKick(command)
	if target == "" {
		return DrawerKickResult{Bytes: len(data)}, fmt.Errorf("printer: target is empty (set RECEIPT_PRINTER_PORT=LPT1 in .env)")
	}

	if isPortName(target) {
		return kickDrawerPowerShellPort(target, data)
	}

	if err := PrintRaw(target, data); err != nil {
		return DrawerKickResult{Target: target, Method: "share_copy", Bytes: len(data)}, err
	}
	return DrawerKickResult{Target: target, Method: "share_copy", Bytes: len(data)}, nil
}

func kickDrawerPowerShellPort(target string, data []byte) (DrawerKickResult, error) {
	port, ok := normalizePortName(target)
	result := DrawerKickResult{
		Target: target,
		Method: "powershell_setcontent_cmd_copy",
		Bytes:  len(data),
	}
	if !ok {
		return result, fmt.Errorf("printer: invalid port target %q", target)
	}
	result.Target = port

	binPath := strings.TrimSpace(os.Getenv("CASH_DRAWER_BIN_PATH"))
	if binPath == "" {
		binPath = defaultDrawerBinPath
	}
	binPath = filepath.Clean(binPath)
	result.BinPath = binPath

	if dir := filepath.Dir(binPath); dir != "." && dir != "" {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return result, fmt.Errorf("printer: create drawer bin directory %s: %w", dir, err)
		}
	}

	byteList := make([]string, 0, len(data))
	for _, b := range data {
		byteList = append(byteList, fmt.Sprintf("0x%02X", b))
	}

	ps := strings.Join([]string{
		"$ErrorActionPreference = 'Stop'",
		fmt.Sprintf("[byte[]](%s) | Set-Content -Encoding Byte -LiteralPath %s", strings.Join(byteList, ","), psQuote(binPath)),
		fmt.Sprintf("& cmd.exe /c copy /b %s %s", cmdQuote(binPath), port),
		"if ($LASTEXITCODE -ne 0) { throw \"copy /b failed with exit code $LASTEXITCODE\" }",
	}, "; ")

	cmd := exec.Command("powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", ps)
	output, err := cmd.CombinedOutput()
	result.Output = strings.TrimSpace(string(output))
	if err != nil {
		return result, fmt.Errorf("printer: powershell drawer copy %s -> %s failed: %w (output: %s)",
			binPath, port, err, result.Output)
	}

	log.Printf("printer: drawer kick wrote %d bytes to port %s via PowerShell bin=%s output=%s",
		len(data), port, binPath, result.Output)
	return result, nil
}

func psQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", "''") + "'"
}

func cmdQuote(s string) string {
	return `"` + strings.ReplaceAll(s, `"`, `\"`) + `"`
}
