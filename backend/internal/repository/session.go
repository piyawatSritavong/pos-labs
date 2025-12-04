package repository

import (
	"context"
	"time"
)

type Session struct {
	ID        string
	UserID    string
	IP        string
	UserAgent string
	CreatedAt time.Time
	ExpiresAt time.Time
	LastSeen  time.Time
}

type SessionRepository interface {
	Create(ctx context.Context, s *Session) error
	GetValidByID(ctx context.Context, id string, ip string, now time.Time) (*Session, error)
	DeleteByID(ctx context.Context, id string) error
	DeleteExpired(ctx context.Context, now time.Time) error
	Touch(ctx context.Context, id string, now time.Time) error
}


