package middleware

import (
	"log"
	"time"

	"github.com/gin-gonic/gin"
)

// Timing logs a single greppable line per request with the wall-clock duration,
// so endpoint latency can be compared before/after performance work:
//
//	[timing] GET /parts/search 200 12ms
//
// Requests slower than slowThreshold are tagged with " SLOW" to make hotspots
// easy to spot in logs (especially with a cross-region database).
func Timing() gin.HandlerFunc {
	const slowThreshold = 300 * time.Millisecond
	return func(c *gin.Context) {
		start := time.Now()
		c.Next()
		dur := time.Since(start)

		path := c.FullPath()
		if path == "" {
			path = c.Request.URL.Path
		}
		suffix := ""
		if dur >= slowThreshold {
			suffix = " SLOW"
		}
		log.Printf("[timing] %s %s %d %dms%s",
			c.Request.Method, path, c.Writer.Status(), dur.Milliseconds(), suffix)
	}
}
