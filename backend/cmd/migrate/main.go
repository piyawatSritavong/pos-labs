package main

import (
	"fmt"
	"log"
	"os"

	"backend/internal/config"
	"backend/internal/db"
)

func main() {
	action := "up"
	if len(os.Args) > 1 {
		action = os.Args[1]
	}
	if action != "up" {
		_, _ = fmt.Fprintf(os.Stderr, "unsupported migrate action %q; supported action: up\n", action)
		os.Exit(2)
	}

	cfg := config.Load()
	if err := db.RunMigrations(cfg); err != nil {
		log.Fatalf("migration failed: %v", err)
	}
}
