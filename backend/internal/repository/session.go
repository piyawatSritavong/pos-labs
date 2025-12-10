package repository

import (
	"context"
	"time"
)

type Session struct {
	ID        string
	UserID    string
	BranchID  string // Branch the user is working at
	POSID     string // POS the user is working at
	IP        string
	UserAgent string
	CreatedAt time.Time
	ExpiresAt time.Time
	LastSeen  time.Time
}

type SessionRepository interface {
	Create(ctx context.Context, s *Session) error
	GetValidByID(ctx context.Context, id string, ip string, now time.Time) (*Session, error)
	GetByUserID(ctx context.Context, userID string) ([]*Session, error)
	DeleteByID(ctx context.Context, id string) error
	DeleteExpired(ctx context.Context, now time.Time) error
	Touch(ctx context.Context, id string, now time.Time) error
}


