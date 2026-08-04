package repository

import (
	"context"
	"errors"
	"time"
)

const (
	SessionStatusActive   = "active"
	SessionStatusPending  = "pending"
	SessionStatusRejected = "rejected"
	SessionStatusReplaced = "replaced"
)

var (
	ErrSessionPending       = errors.New("session pending")
	ErrSessionNotActive     = errors.New("session not active")
	ErrPendingSessionExists = errors.New("pending session already exists")
)

type Session struct {
	ID        string
	UserID    string
	BranchID  string // Branch the user is working at
	POSID     string // POS the user is working at
	IP        string
	UserAgent string
	CreatedAt time.Time
	ExpiresAt *time.Time
	LastSeen  time.Time
	Status    string
	Reason    string
}

type SessionState struct {
	Session      *Session
	PendingLogin *Session
}

type SessionRepository interface {
	Create(ctx context.Context, s *Session) error
	CreateForLogin(ctx context.Context, s *Session, staleBefore time.Time) (string, error)
	GetValidByID(ctx context.Context, id string) (*Session, error)
	GetValidWithUserByID(ctx context.Context, id string) (*Session, *User, error)
	GetSessionState(ctx context.Context, id string, staleBefore, now time.Time) (*SessionState, error)
	ResolveConflict(ctx context.Context, activeSessionID, decision string, now time.Time) error
	Logout(ctx context.Context, id string, now time.Time) error
	GetByUserID(ctx context.Context, userID string) ([]*Session, error)
	DeleteByID(ctx context.Context, id string) error
	DeleteExpired(ctx context.Context, now time.Time) error
	Touch(ctx context.Context, id string, now time.Time) error
}
