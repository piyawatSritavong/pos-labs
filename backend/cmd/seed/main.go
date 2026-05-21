package main

import (
	"context"
	"flag"
	"log"
	"os"
	"time"

	"backend/internal/config"
	"backend/internal/db"
)

func main() {
	core := flag.Bool("core", false, "seed core roles, permissions, company, branch, POS, and admin data")
	realDataPath := flag.String("real-data", "", "path to seed-real-data.sql")
	ensureBarcodes := flag.Bool("ensure-barcodes", true, "backfill missing part barcodes after seeding")
	flag.Parse()

	if !*core && *realDataPath == "" {
		log.Fatalf("nothing to seed; pass --core and/or --real-data <path>")
	}

	cfg := config.Load()
	sqlDB, err := db.Connect(cfg)
	if err != nil {
		log.Fatalf("failed to connect to database: %v", err)
	}
	defer sqlDB.Close()

	if *core {
		if err := db.SeedCoreData(sqlDB); err != nil {
			log.Fatalf("core seed failed: %v", err)
		}
		log.Printf("core seed completed")
	}

	if *realDataPath != "" {
		script, err := os.ReadFile(*realDataPath)
		if err != nil {
			log.Fatalf("read real data seed %s: %v", *realDataPath, err)
		}
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
		defer cancel()
		if _, err := sqlDB.ExecContext(ctx, string(script)); err != nil {
			log.Fatalf("real data seed failed: %v", err)
		}
		log.Printf("real data seed completed from %s", *realDataPath)
	}

	if *ensureBarcodes {
		if err := db.EnsureBarcodes(sqlDB); err != nil {
			log.Fatalf("ensure barcodes failed: %v", err)
		}
	}
}
