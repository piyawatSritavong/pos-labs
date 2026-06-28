package config

import (
	"net/url"
	"os"
	"strings"
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
	Env                  string
	Port                 string
	DatabaseURL          string
	DBHost               string
	DBPort               string
	DBUser               string
	DBPassword           string
	DBName               string
	DBSSLMode            string
	DBMaxOpenConns       int
	DBMaxIdleConns       int
	DBConnMaxLifetime    time.Duration
	SessionSecret        string
	SessionDuration      string
	StaticFilesPath      string
	ServeStatic          bool
	AutoMigrate          bool
	AutoSeedCore         bool
	AutoSeedMock         bool
	AutoEnsureBarcodes   bool
	CORSAllowedOrigins   string
	CORSAllowCredentials bool
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
	env := getEnv("APP_ENV", getEnv("ENV", "development"))
	return Config{
		Env:                   env,
		Port:                  getEnv("PORT", "8080"),
		DatabaseURL:           getEnv("DATABASE_URL", ""),
		DBHost:                getEnv("DB_HOST", "localhost"),
		DBPort:                getEnv("DB_PORT", "5432"),
		DBUser:                getEnv("DB_USER", "posuser"),
		DBPassword:            getEnv("DB_PASSWORD", "pospass"),
		DBName:                getEnv("DB_NAME", "poslabs"),
		DBSSLMode:             getEnv("DB_SSLMODE", "disable"),
		DBMaxOpenConns:        getEnvInt("DB_MAX_OPEN_CONNS", 10),
		DBMaxIdleConns:        getEnvInt("DB_MAX_IDLE_CONNS", 5),
		DBConnMaxLifetime:     getEnvDuration("DB_CONN_MAX_LIFETIME", 30*time.Minute),
		SessionSecret:         getEnv("SESSION_SECRET", "dev-session-secret-change-me"),
		SessionDuration:       getEnv("SESSION_DURATION", "4h"),
		StaticFilesPath:       getEnv("STATIC_FILES_PATH", "static"),
		ServeStatic:           getEnvBool("SERVE_STATIC", true),
		AutoMigrate:           getEnvBool("AUTO_MIGRATE", true),
		AutoSeedCore:          getEnvBool("AUTO_SEED_CORE", true),
		AutoSeedMock:          getEnvBool("AUTO_SEED_MOCK", env == "development"),
		AutoEnsureBarcodes:    getEnvBool("AUTO_ENSURE_BARCODES", true),
		CORSAllowedOrigins:    getEnv("CORS_ALLOWED_ORIGINS", ""),
		CORSAllowCredentials:  getEnvBool("CORS_ALLOW_CREDENTIALS", false),
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

// WithCloudDefaults disables startup mutations and static serving by default for
// the Render/API entrypoint while still allowing env vars to opt back in.
func (c Config) WithCloudDefaults() Config {
	if !c.IsProduction() {
		return c
	}
	if !envIsSet("SERVE_STATIC") {
		c.ServeStatic = false
	}
	if !envIsSet("AUTO_MIGRATE") {
		c.AutoMigrate = false
	}
	if !envIsSet("AUTO_SEED_CORE") {
		c.AutoSeedCore = false
	}
	if !envIsSet("AUTO_SEED_MOCK") {
		c.AutoSeedMock = false
	}
	if !envIsSet("AUTO_ENSURE_BARCODES") {
		c.AutoEnsureBarcodes = false
	}
	return c
}

func (c Config) IsProduction() bool {
	return strings.EqualFold(c.Env, "production")
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

func getEnvDuration(key string, def time.Duration) time.Duration {
	raw := getEnv(key, "")
	if raw == "" {
		return def
	}
	d, err := time.ParseDuration(raw)
	if err != nil {
		return def
	}
	return d
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
	if c.DatabaseURL != "" {
		return normalizePostgresURL(c.DatabaseURL, c)
	}

	u := url.URL{
		Scheme: "postgres",
		User:   url.UserPassword(c.DBUser, c.DBPassword),
		Host:   c.DBHost + ":" + c.DBPort,
		Path:   "/" + c.DBName,
	}
	q := u.Query()
	q.Set("sslmode", c.DBSSLMode)
	q.Set("timezone", "UTC")
	u.RawQuery = q.Encode()
	return u.String()
}

func normalizePostgresURL(raw string, cfg Config) string {
	u, err := url.Parse(raw)
	if err != nil {
		return raw
	}
	q := u.Query()
	if q.Get("sslmode") == "" && cfg.IsProduction() {
		q.Set("sslmode", "require")
	}
	if q.Get("timezone") == "" {
		q.Set("timezone", "UTC")
	}
	u.RawQuery = q.Encode()
	return u.String()
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

func envIsSet(key string) bool {
	v, ok := os.LookupEnv(key)
	return ok && v != ""
}
