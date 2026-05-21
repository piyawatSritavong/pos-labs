package config

import (
	"os"
	"time"
)

// Pagination defaults
const (
	DefaultLimit  = 20
	DefaultOffset = 0
	// MaxLimit raised to 2000 so the Backoffice Parts/Addresses pages can load
	// the full real-data set (~1,566 rows) in a single request.
	MaxLimit = 2000
)

type Config struct {
	Env             string
	Port            string
	DBHost          string
	DBPort          string
	DBUser          string
	DBPassword      string
	DBName          string
	DBSSLMode       string
	SessionSecret   string
	SessionDuration string
	StaticFilesPath string
	// ReceiptPrinterEnabled gates all backend-controlled receipt/drawer writes.
	ReceiptPrinterEnabled bool
	// ReceiptPrinter targets the 80mm thermal printer used for POS receipts.
	// Accepts a port name ("LPT1", "COM1") or a Windows printer share name
	// like "POS 80mm LPT1". The printer package decides which write path to use.
	ReceiptPrinter     string
	ReceiptPrinterPort string
	ReceiptPrinterName string
	// ReceiptCharset is the ESC t code page number sent to the printer before
	// any text. 21 = Thai (CP874 / TIS-620) on most Star/Bixolon-style devices.
	// Override if the operator's printer expects a different value
	// (Epson firmwares often use 20 or 18 for Thai).
	ReceiptCharset int
	// ReceiptPrintMode controls text encoding. "ascii" is the safe production
	// fallback for printers whose Thai ESC/POS table renders incorrectly.
	// "thai_cp874" remains available after the printer code table is verified.
	ReceiptPrintMode       string
	ReceiptForceASCII      bool
	ReceiptProductNameMode string
	// CashDrawerEnabled sends ESC p drawer pulse with each receipt when true.
	CashDrawerEnabled bool
	// CashDrawerKickCommand is the raw ESC/POS drawer command sent to the
	// printer DK port. Common values are 1B700019FA and 1B700119FA.
	CashDrawerKickCommand string
}

func Load() Config {
	return Config{
		Env:                   getEnv("ENV", "development"),
		Port:                  getEnv("PORT", "8080"),
		DBHost:                getEnv("DB_HOST", "localhost"),
		DBPort:                getEnv("DB_PORT", "5432"),
		DBUser:                getEnv("DB_USER", "posuser"),
		DBPassword:            getEnv("DB_PASSWORD", "pospass"),
		DBName:                getEnv("DB_NAME", "poslabs"),
		DBSSLMode:             getEnv("DB_SSLMODE", "disable"),
		SessionSecret:         getEnv("SESSION_SECRET", "dev-session-secret-change-me"),
		SessionDuration:       getEnv("SESSION_DURATION", "4h"),
		StaticFilesPath:       getEnv("STATIC_FILES_PATH", "static"),
		ReceiptPrinterEnabled: getEnvBool("RECEIPT_PRINTER_ENABLED", true),
		ReceiptPrinterPort:    getEnv("RECEIPT_PRINTER_PORT", "LPT1"),
		ReceiptPrinterName:    getEnv("RECEIPT_PRINTER_NAME", ""),
		ReceiptPrinter: resolveReceiptPrinterTarget(
			getEnv("RECEIPT_PRINTER_TARGET", ""),
			getEnv("RECEIPT_PRINTER_PORT", "LPT1"),
			getEnv("RECEIPT_PRINTER_NAME", ""),
		),
		ReceiptCharset: getEnvInt("RECEIPT_CHARSET", 21),
		ReceiptPrintMode: resolveReceiptTextMode(
			getEnv("RECEIPT_TEXT_MODE", getEnv("RECEIPT_PRINT_MODE", "ascii")),
			getEnvBool("RECEIPT_FORCE_ASCII", true),
		),
		ReceiptForceASCII:      getEnvBool("RECEIPT_FORCE_ASCII", true),
		ReceiptProductNameMode: getEnv("RECEIPT_PRODUCT_NAME_MODE", "receipt_name"),
		CashDrawerEnabled:      getEnvBool("CASH_DRAWER_ENABLED", getEnvBool("RECEIPT_OPEN_DRAWER", false)),
		CashDrawerKickCommand: getEnv(
			"CASH_DRAWER_COMMAND",
			getEnv("CASH_DRAWER_KICK_COMMAND", getEnv("RECEIPT_DRAWER_KICK_COMMAND", "1B700019FA")),
		),
	}
}

func resolveReceiptPrinterTarget(target, port, name string) string {
	if target != "" {
		return target
	}
	if port != "" {
		return port
	}
	if name != "" {
		return name
	}
	return "LPT1"
}

func resolveReceiptTextMode(mode string, forceASCII bool) string {
	if forceASCII {
		return "ascii"
	}
	if mode != "" {
		return mode
	}
	return "ascii"
}

func getEnvBool(key string, def bool) bool {
	v, ok := os.LookupEnv(key)
	if !ok || v == "" {
		return def
	}
	switch v {
	case "1", "true", "TRUE", "True", "yes", "YES", "Yes", "y", "Y", "on", "ON", "On":
		return true
	case "0", "false", "FALSE", "False", "no", "NO", "No", "n", "N", "off", "OFF", "Off":
		return false
	default:
		return def
	}
}

func getEnvInt(key string, def int) int {
	v, ok := lookupEnvInt(key)
	if !ok {
		return def
	}
	return v
}

func lookupEnvInt(key string) (int, bool) {
	s, ok := os.LookupEnv(key)
	if !ok || s == "" {
		return 0, false
	}
	n := 0
	neg := false
	for i, ch := range s {
		if i == 0 && ch == '-' {
			neg = true
			continue
		}
		if ch < '0' || ch > '9' {
			return 0, false
		}
		n = n*10 + int(ch-'0')
	}
	if neg {
		n = -n
	}
	return n, true
}

func (c Config) PostgresURL() string {
	// postgres://user:pass@host:port/db?sslmode=disable&timezone=UTC
	return "postgres://" + c.DBUser + ":" + c.DBPassword + "@" + c.DBHost + ":" + c.DBPort + "/" + c.DBName + "?sslmode=" + c.DBSSLMode + "&timezone=UTC"
}

// SessionDurationParsed returns the parsed time.Duration from SessionDuration string (e.g., "4h" -> 4*time.Hour).
// Returns default 4h if parsing fails.
func (c Config) SessionDurationParsed() time.Duration {
	d, err := time.ParseDuration(c.SessionDuration)
	if err != nil {
		// Default to 4h if parsing fails
		return 4 * time.Hour
	}
	return d
}

func getEnv(key, def string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return def
}
