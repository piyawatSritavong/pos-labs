package db

import (
	"database/sql"

	"backend/internal/config"

	_ "github.com/lib/pq"
)

func Connect(cfg config.Config) (*sql.DB, error) {
	db, err := sql.Open("postgres", cfg.PostgresURL())
	if err != nil {
		return nil, err
	}
	if cfg.DBMaxOpenConns > 0 {
		db.SetMaxOpenConns(cfg.DBMaxOpenConns)
	}
	if cfg.DBMaxIdleConns > 0 {
		db.SetMaxIdleConns(cfg.DBMaxIdleConns)
	}
	if cfg.DBConnMaxLifetime > 0 {
		db.SetConnMaxLifetime(cfg.DBConnMaxLifetime)
	}

	if err := db.Ping(); err != nil {
		return nil, err
	}

	// Ensure the session timezone is UTC for this connection pool.
	if _, err := db.Exec(`SET TIME ZONE 'UTC'`); err != nil {
		return nil, err
	}

	return db, nil
}
