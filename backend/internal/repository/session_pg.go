package repository

import (
	"context"
	"database/sql"
	"time"
)

type sessionRepositoryPG struct {
	db *sql.DB
}

func NewSessionRepository(db *sql.DB) SessionRepository {
	return &sessionRepositoryPG{db: db}
}

func (r *sessionRepositoryPG) Create(ctx context.Context, s *Session) error {
	_, err := r.db.ExecContext(ctx, `
		INSERT INTO "session"("id", "user_id", "ip", "user_agent", "created_at", "expires_at", "last_seen_at")
		VALUES ($1, $2, $3, $4, $5, $6, $7)
	`, s.ID, s.UserID, s.IP, s.UserAgent, s.CreatedAt, s.ExpiresAt, s.LastSeen)
	return err
}

func (r *sessionRepositoryPG) GetValidByID(ctx context.Context, id string, ip string, now time.Time) (*Session, error) {
	row := r.db.QueryRowContext(ctx, `
		SELECT "id", "user_id", "ip", "user_agent", "created_at", "expires_at", "last_seen_at"
		FROM "session"
		WHERE "id" = $1
		  AND "expires_at" > $2
	`, id, now)

	var s Session
	if err := row.Scan(&s.ID, &s.UserID, &s.IP, &s.UserAgent, &s.CreatedAt, &s.ExpiresAt, &s.LastSeen); err != nil {
		return nil, err
	}

	// Optional strict IP check: if stored IP is non-empty and doesn't match, treat as invalid
	if s.IP != "" && ip != "" && s.IP != ip {
		return nil, sql.ErrNoRows
	}

	return &s, nil
}

func (r *sessionRepositoryPG) DeleteByID(ctx context.Context, id string) error {
	_, err := r.db.ExecContext(ctx, `DELETE FROM "session" WHERE "id" = $1`, id)
	return err
}

func (r *sessionRepositoryPG) DeleteExpired(ctx context.Context, now time.Time) error {
	_, err := r.db.ExecContext(ctx, `DELETE FROM "session" WHERE "expires_at" <= $1`, now)
	return err
}

func (r *sessionRepositoryPG) Touch(ctx context.Context, id string, now time.Time) error {
	_, err := r.db.ExecContext(ctx, `
		UPDATE "session"
		SET "last_seen_at" = $1
		WHERE "id" = $2
	`, now, id)
	return err
}


