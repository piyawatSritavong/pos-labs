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

	if err := db.Ping(); err != nil {
		return nil, err
	}

	// Ensure the session timezone is UTC for this connection pool.
	if _, err := db.Exec(`SET TIME ZONE 'UTC'`); err != nil {
		return nil, err
	}

	return db, nil
}


