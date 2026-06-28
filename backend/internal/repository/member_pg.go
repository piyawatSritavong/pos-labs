package repository

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"regexp"
	"strings"

	"github.com/lib/pq"
)

var nonDigitRegex = regexp.MustCompile(`\D`)

type memberRepositoryPG struct {
	db *sql.DB
}

func NewMemberRepository(db *sql.DB) MemberRepository {
	return &memberRepositoryPG{db: db}
}

func normalizePhone(phone string) string {
	return nonDigitRegex.ReplaceAllString(phone, "")
}

func generateMemberCode(ctx context.Context, tx *sql.Tx) (string, error) {
	var counter int
	err := tx.QueryRowContext(ctx, `
		INSERT INTO "counter"("key", "value")
		VALUES ('member', 1)
		ON CONFLICT ("key") DO UPDATE
		SET "value" = "counter"."value" + 1
		RETURNING "value"
	`).Scan(&counter)
	if err != nil {
		return "", fmt.Errorf("failed to generate member counter: %w", err)
	}

	return fmt.Sprintf("%06d", counter), nil
}

func (r *memberRepositoryPG) GetByID(ctx context.Context, id string) (*Member, error) {
	row := r.db.QueryRowContext(ctx, `
		SELECT "id", "code", "name", "phone", COALESCE("email", ''), "points", "created_at", "updated_at"
		FROM "member_master"
		WHERE "id" = $1
	`, id)

	var m Member
	if err := row.Scan(&m.ID, &m.Code, &m.Name, &m.Phone, &m.Email, &m.Points, &m.CreatedAt, &m.UpdatedAt); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	return &m, nil
}

// GetByIDs loads many members in one round-trip using `id = ANY($1)`,
// returning a map keyed by member ID. Missing IDs are simply absent from the map.
func (r *memberRepositoryPG) GetByIDs(ctx context.Context, ids []string) (map[string]*Member, error) {
	result := make(map[string]*Member, len(ids))
	if len(ids) == 0 {
		return result, nil
	}

	rows, err := r.db.QueryContext(ctx, `
		SELECT "id", "code", "name", "phone", COALESCE("email", ''), "points", "created_at", "updated_at"
		FROM "member_master"
		WHERE "id" = ANY($1)
	`, pq.Array(ids))
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var m Member
		if err := rows.Scan(&m.ID, &m.Code, &m.Name, &m.Phone, &m.Email, &m.Points, &m.CreatedAt, &m.UpdatedAt); err != nil {
			return nil, err
		}
		mm := m
		result[m.ID] = &mm
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	return result, nil
}

func (r *memberRepositoryPG) GetByPhone(ctx context.Context, phone string) (*Member, error) {
	normalized := normalizePhone(phone)
	if normalized == "" {
		return nil, ErrNotFound
	}

	row := r.db.QueryRowContext(ctx, `
		SELECT "id", "code", "name", "phone", COALESCE("email", ''), "points", "created_at", "updated_at"
		FROM "member_master"
		WHERE regexp_replace("phone", '\D', '', 'g') = $1
	`, normalized)

	var m Member
	if err := row.Scan(&m.ID, &m.Code, &m.Name, &m.Phone, &m.Email, &m.Points, &m.CreatedAt, &m.UpdatedAt); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	return &m, nil
}

func (r *memberRepositoryPG) List(ctx context.Context, limit, offset int) ([]Member, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT "id", "code", "name", "phone", COALESCE("email", ''), "points", "created_at", "updated_at"
		FROM "member_master"
		ORDER BY "updated_at" DESC, "id" DESC
		LIMIT $1 OFFSET $2
	`, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	members := make([]Member, 0)
	for rows.Next() {
		var m Member
		if err := rows.Scan(&m.ID, &m.Code, &m.Name, &m.Phone, &m.Email, &m.Points, &m.CreatedAt, &m.UpdatedAt); err != nil {
			return nil, err
		}
		members = append(members, m)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}
	return members, nil
}

func (r *memberRepositoryPG) Search(ctx context.Context, query string, limit, offset int) ([]Member, error) {
	q := strings.TrimSpace(query)
	if q == "" {
		return r.List(ctx, limit, offset)
	}

	phoneQ := normalizePhone(q)
	likeQ := "%" + q + "%"

	rows, err := r.db.QueryContext(ctx, `
		SELECT "id", "code", "name", "phone", COALESCE("email", ''), "points", "created_at", "updated_at"
		FROM "member_master"
		WHERE
			"id" ILIKE $1 OR
			"code" ILIKE $1 OR
			"name" ILIKE $1 OR
			"phone" ILIKE $1 OR
			COALESCE("email", '') ILIKE $1 OR
			($2 <> '' AND regexp_replace("phone", '\D', '', 'g') LIKE '%' || $2 || '%')
		ORDER BY "updated_at" DESC, "id" DESC
		LIMIT $3 OFFSET $4
	`, likeQ, phoneQ, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	members := make([]Member, 0)
	for rows.Next() {
		var m Member
		if err := rows.Scan(&m.ID, &m.Code, &m.Name, &m.Phone, &m.Email, &m.Points, &m.CreatedAt, &m.UpdatedAt); err != nil {
			return nil, err
		}
		members = append(members, m)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}
	return members, nil
}

func (r *memberRepositoryPG) Create(ctx context.Context, member *Member) error {
	member.Phone = strings.TrimSpace(member.Phone)
	digits := normalizePhone(member.Phone)
	if digits == "" {
		return fmt.Errorf("invalid member phone")
	}

	member.ID = digits

	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()

	if member.Code == "" {
		member.Code, err = generateMemberCode(ctx, tx)
		if err != nil {
			return err
		}
	}

	_, err = tx.ExecContext(ctx, `
		INSERT INTO "member_master"(
			"id", "code", "name", "phone", "email", "points", "created_at", "updated_at"
		)
		VALUES ($1, $2, $3, $4, NULLIF($5, ''), $6, now(), now())
	`, member.ID, member.Code, member.Name, member.Phone, member.Email, member.Points)
	if err != nil {
		return err
	}

	if err := tx.Commit(); err != nil {
		return err
	}

	return nil
}

func (r *memberRepositoryPG) UpdateByID(ctx context.Context, id string, member *Member) error {
	member.Phone = strings.TrimSpace(member.Phone)
	digits := normalizePhone(member.Phone)
	if digits == "" {
		return fmt.Errorf("invalid member phone")
	}

	// Keep id derived from phone digits and immutable after create.
	if digits != id {
		return fmt.Errorf("phone_must_match_member_id")
	}
	member.ID = id

	res, err := r.db.ExecContext(ctx, `
		UPDATE "member_master"
		SET
			"code" = COALESCE(NULLIF($1, ''), "code"),
			"name" = $2,
			"phone" = $3,
			"email" = NULLIF($4, ''),
			"points" = $5,
			"updated_at" = now()
		WHERE "id" = $6
	`, member.Code, member.Name, member.Phone, member.Email, member.Points, member.ID)
	if err != nil {
		return err
	}

	rowsAffected, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if rowsAffected == 0 {
		return ErrNotFound
	}
	return nil
}

func (r *memberRepositoryPG) Delete(ctx context.Context, id string) error {
	res, err := r.db.ExecContext(ctx, `
		DELETE FROM "member_master" WHERE "id" = $1
	`, id)
	if err != nil {
		return err
	}

	rowsAffected, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if rowsAffected == 0 {
		return ErrNotFound
	}
	return nil
}
