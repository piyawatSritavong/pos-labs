package handlers

import (
	"fmt"
	"log"
	"os"
	"strings"
	"time"
)

const slowTimingThreshold = 500 * time.Millisecond

func logSlowTiming(operation string, started time.Time, fields ...any) {
	elapsed := time.Since(started)
	if elapsed < slowTimingThreshold && !timingLogsEnabled() {
		return
	}

	var b strings.Builder
	for i := 0; i+1 < len(fields); i += 2 {
		if b.Len() > 0 {
			b.WriteByte(' ')
		}
		b.WriteString(toLogString(fields[i]))
		b.WriteByte('=')
		b.WriteString(toLogString(fields[i+1]))
	}
	if b.Len() > 0 {
		log.Printf("timing operation=%s elapsed=%s %s", operation, elapsed.Round(time.Millisecond), b.String())
		return
	}
	log.Printf("timing operation=%s elapsed=%s", operation, elapsed.Round(time.Millisecond))
}

func timingLogsEnabled() bool {
	switch strings.ToLower(strings.TrimSpace(os.Getenv("LOG_SLOW_QUERIES"))) {
	case "1", "true", "yes", "y", "on":
		return true
	default:
		return false
	}
}

func toLogString(value any) string {
	switch v := value.(type) {
	case string:
		return strings.TrimSpace(v)
	case time.Duration:
		return v.Round(time.Millisecond).String()
	default:
		return strings.TrimSpace(strings.ReplaceAll(strings.ReplaceAll(fmt.Sprint(v), "\n", " "), "\t", " "))
	}
}
