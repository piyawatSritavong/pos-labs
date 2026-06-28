package repository

import (
	"context"
	"time"
)

type Member struct {
	ID        string
	Code      string
	Name      string
	Phone     string
	Email     string
	Points    int
	CreatedAt time.Time
	UpdatedAt time.Time
}

type MemberRepository interface {
	GetByID(ctx context.Context, id string) (*Member, error)
	// GetByIDs loads many members in one query, keyed by member ID (avoids N+1
	// when enriching bill/return lists with member info).
	GetByIDs(ctx context.Context, ids []string) (map[string]*Member, error)
	GetByPhone(ctx context.Context, phone string) (*Member, error)
	List(ctx context.Context, limit, offset int) ([]Member, error)
	Search(ctx context.Context, query string, limit, offset int) ([]Member, error)
	Create(ctx context.Context, member *Member) error
	UpdateByID(ctx context.Context, id string, member *Member) error
	Delete(ctx context.Context, id string) error
}
