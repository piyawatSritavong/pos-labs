package db

import (
	"fmt"
	"log"

	"backend/internal/config"

	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/postgres"
	_ "github.com/golang-migrate/migrate/v4/source/file"
)

// RunMigrations applies any pending database migrations on startup.
func RunMigrations(cfg config.Config) error {
	migrationsPath := "file://migrations"

	log.Printf("Running database migrations from %s", migrationsPath)

	m, err := migrate.New(migrationsPath, cfg.PostgresURL())
	if err != nil {
		return fmt.Errorf("create migrate instance: %w", err)
	}
	defer m.Close()

	if err := m.Up(); err != nil && err != migrate.ErrNoChange {
		return fmt.Errorf("migrate up: %w", err)
	}

	log.Printf("Database migrations applied successfully")
	return nil
}


