package httpserver

import (
	"bufio"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"testing"

	"backend/internal/config"
)

func TestRouterManifest(t *testing.T) {
	router := NewRouter(config.Config{
		StaticFilesPath:       t.TempDir(),
		ReceiptCharset:        21,
		ReceiptPrinterEnabled: false,
	}, nil)

	_, sourceFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("cannot resolve test source path")
	}
	manifestPath := filepath.Join(filepath.Dir(sourceFile), "..", "..", "..", "scripts", "api_routes.txt")
	file, err := os.Open(manifestPath)
	if err != nil {
		t.Fatalf("open route manifest: %v", err)
	}
	defer file.Close()

	expected := make(map[string]struct{})
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line != "" && !strings.HasPrefix(line, "#") {
			expected[line] = struct{}{}
		}
	}
	if err := scanner.Err(); err != nil {
		t.Fatalf("read route manifest: %v", err)
	}

	actual := make(map[string]struct{})
	for _, route := range router.Routes() {
		actual[route.Method+" "+route.Path] = struct{}{}
	}
	var missing, unexpected []string
	for route := range expected {
		if _, ok := actual[route]; !ok {
			missing = append(missing, route)
		}
	}
	for route := range actual {
		if _, ok := expected[route]; !ok {
			unexpected = append(unexpected, route)
		}
	}
	sort.Strings(missing)
	sort.Strings(unexpected)
	if len(missing) > 0 || len(unexpected) > 0 {
		t.Fatalf("router manifest mismatch\nmissing: %v\nunexpected: %v", missing, unexpected)
	}

	routes := router.Routes()
	for _, route := range routes {
		key := route.Method + " " + route.Path
		if _, ok := actual[key]; !ok {
			t.Fatalf("duplicate or invalid route: %s", key)
		}
	}
	if got, want := len(routes), len(expected); got != want {
		t.Fatalf("registered route count = %d, want %d", got, want)
	}
}
