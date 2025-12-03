package main

import (
	"context"
	"log"
	"net/http"
	"time"

	"backend/internal/config"
	"backend/internal/db"
	"backend/internal/httpserver"
	"backend/internal/repository"
)

func main() {
	cfg := config.Load()

	sqlDB, err := db.Connect(cfg)
	if err != nil {
		log.Fatalf("failed to connect to database: %v", err)
	}
	defer sqlDB.Close()

	if err := db.RunMigrations(cfg); err != nil {
		log.Fatalf("failed to run migrations: %v", err)
	}

	if err := db.SeedCoreData(sqlDB); err != nil {
		log.Fatalf("failed to seed core data: %v", err)
	}

	// Development-only mock data
	if cfg.Env == "development" {
		if err := db.SeedMockData(sqlDB); err != nil {
			log.Printf("failed to seed mock data (development): %v", err)
		}
	}

	// Start background session cleanup
	sessionRepo := repository.NewSessionRepository(sqlDB)
	go func() {
		ticker := time.NewTicker(5 * time.Minute)
		defer ticker.Stop()
		for range ticker.C {
			ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
			if err := sessionRepo.DeleteExpired(ctx, time.Now().UTC()); err != nil {
				log.Printf("failed to delete expired sessions: %v", err)
			}
			cancel()
		}
	}()

	engine := httpserver.NewRouter(cfg, sqlDB)

	addr := ":" + cfg.Port
	log.Printf("Starting backend server on %s", addr)
	if err := http.ListenAndServe(addr, engine); err != nil {
		log.Fatalf("server stopped with error: %v", err)
	}
}


