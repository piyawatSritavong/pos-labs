package app

import (
	"context"
	"database/sql"
	"errors"
	"log"
	"net/http"
	"time"

	"backend/internal/config"
	"backend/internal/db"
	"backend/internal/httpserver"
	"backend/internal/repository"
)

func RunServer(cfg config.Config) error {
	sqlDB, err := db.Connect(cfg)
	if err != nil {
		return err
	}
	defer sqlDB.Close()

	if err := prepareDatabase(sqlDB, cfg); err != nil {
		return err
	}

	startSessionCleanup(sqlDB)

	engine := httpserver.NewRouter(cfg, sqlDB)

	addr := ":" + cfg.Port
	log.Printf("Starting backend server on %s", addr)
	server := &http.Server{
		Addr:         addr,
		Handler:      engine,
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 10 * time.Second,
	}
	if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	return nil
}

func prepareDatabase(sqlDB *sql.DB, cfg config.Config) error {
	runMigrations := cfg.AutoMigrate
	if !runMigrations {
		legacyProduction, err := db.HasProductionCatalog20260724(sqlDB)
		if err != nil {
			return err
		}
		if legacyProduction {
			runMigrations = true
			log.Printf("Applying pending migrations for the legacy Render production database")
		}
	}

	if runMigrations {
		if err := db.RunMigrations(cfg); err != nil {
			return err
		}
	} else {
		log.Printf("Skipping database migrations (AUTO_MIGRATE=false)")
	}

	if err := db.EnsureAddressActiveState(sqlDB); err != nil {
		return err
	}

	if cfg.AutoSeedCore {
		if err := db.SeedCoreData(sqlDB); err != nil {
			return err
		}
	} else {
		log.Printf("Skipping core seed (AUTO_SEED_CORE=false)")
	}

	// One-time data load requested for the PPSale deployment. It is guarded by
	// data_seed_history instead of APP_ENV because the existing Render service
	// currently runs with its legacy development environment settings.
	applied, err := db.ApplyProductionCatalog20260724(sqlDB)
	if err != nil {
		return err
	}
	if applied {
		log.Printf("Applied catalog seed catalog-20260724-ppsale-v1")
	} else {
		log.Printf("Catalog seed catalog-20260724-ppsale-v1 already applied")
	}

	if cfg.AutoSeedMock {
		if err := db.SeedMockData(sqlDB); err != nil {
			log.Printf("failed to seed mock data: %v", err)
		}
	}

	if cfg.AutoEnsureBarcodes {
		if err := db.EnsureBarcodes(sqlDB); err != nil {
			log.Printf("failed to backfill barcodes: %v", err)
		}
	}

	return nil
}

func startSessionCleanup(sqlDB *sql.DB) {
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
}
