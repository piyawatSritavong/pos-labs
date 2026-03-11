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
	GetByPhone(ctx context.Context, phone string) (*Member, error)
	List(ctx context.Context, limit, offset int) ([]Member, error)
	Search(ctx context.Context, query string, limit, offset int) ([]Member, error)
	Create(ctx context.Context, member *Member) error
	UpdateByID(ctx context.Context, id string, member *Member) error
	Delete(ctx context.Context, id string) error
}
