package config

import (
	"os"
	"time"
)

// Pagination defaults
const (
	DefaultLimit  = 20
	DefaultOffset = 0
	MaxLimit      = 500
)

type Config struct {
	Env            string
	Port           string
	DBHost         string
	DBPort         string
	DBUser         string
	DBPassword     string
	DBName         string
	DBSSLMode      string
	SessionSecret  string
	SessionDuration string
	StaticFilesPath string
}

func Load() Config {
	return Config{
		Env:           getEnv("ENV", "development"),
		Port:          getEnv("PORT", "8080"),
		DBHost:        getEnv("DB_HOST", "localhost"),
		DBPort:        getEnv("DB_PORT", "5432"),
		DBUser:        getEnv("DB_USER", "posuser"),
		DBPassword:    getEnv("DB_PASSWORD", "pospass"),
		DBName:        getEnv("DB_NAME", "poslabs"),
		DBSSLMode:     getEnv("DB_SSLMODE", "disable"),
		SessionSecret: getEnv("SESSION_SECRET", "dev-session-secret-change-me"),
		SessionDuration: getEnv("SESSION_DURATION", "4h"),
		StaticFilesPath: getEnv("STATIC_FILES_PATH", "static"),
	}
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


