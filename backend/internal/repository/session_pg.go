package repository

import (
	"context"
	"database/sql"
	"errors"
	"time"

	"github.com/lib/pq"
)

type sessionRepositoryPG struct {
	db *sql.DB
}

func NewSessionRepository(db *sql.DB) SessionRepository {
	return &sessionRepositoryPG{db: db}
}

func nullableString(value string) interface{} {
	if value == "" {
		return nil
	}
	return value
}

const sessionColumns = `"id", "user_id", "branch_id", "pos_id", "ip", "user_agent", "created_at", "expires_at", "last_seen_at", "status", "status_reason"`

func scanSession(scanner interface{ Scan(...interface{}) error }) (*Session, error) {
	var s Session
	var branchID, posID, ip, userAgent, reason sql.NullString
	var expiresAt sql.NullTime
	if err := scanner.Scan(
		&s.ID, &s.UserID, &branchID, &posID, &ip, &userAgent,
		&s.CreatedAt, &expiresAt, &s.LastSeen, &s.Status, &reason,
	); err != nil {
		return nil, err
	}
	if branchID.Valid {
		s.BranchID = branchID.String
	}
	if posID.Valid {
		s.POSID = posID.String
	}
	if ip.Valid {
		s.IP = ip.String
	}
	if userAgent.Valid {
		s.UserAgent = userAgent.String
	}
	if expiresAt.Valid {
		value := expiresAt.Time
		s.ExpiresAt = &value
	}
	if reason.Valid {
		s.Reason = reason.String
	}
	return &s, nil
}

func insertSession(ctx context.Context, exec interface {
	ExecContext(context.Context, string, ...interface{}) (sql.Result, error)
}, s *Session) error {
	status := s.Status
	if status == "" {
		status = SessionStatusActive
	}
	_, err := exec.ExecContext(ctx, `
		INSERT INTO "session"(
			"id", "user_id", "branch_id", "pos_id", "ip", "user_agent",
			"created_at", "expires_at", "last_seen_at", "status", "status_reason"
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
	`, s.ID, s.UserID, nullableString(s.BranchID), nullableString(s.POSID),
		nullableString(s.IP), nullableString(s.UserAgent), s.CreatedAt, s.ExpiresAt,
		s.LastSeen, status, nullableString(s.Reason))
	return err
}

func (r *sessionRepositoryPG) Create(ctx context.Context, s *Session) error {
	return insertSession(ctx, r.db, s)
}

func lockUser(ctx context.Context, tx *sql.Tx, userID string) error {
	_, err := tx.ExecContext(ctx, `SELECT pg_advisory_xact_lock(hashtext($1))`, userID)
	return err
}

func (r *sessionRepositoryPG) CreateForLogin(ctx context.Context, s *Session, staleBefore time.Time) (string, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return "", err
	}
	defer tx.Rollback()
	if err := lockUser(ctx, tx, s.UserID); err != nil {
		return "", err
	}

	var activeID string
	var activeSeen time.Time
	err = tx.QueryRowContext(ctx, `
		SELECT "id", "last_seen_at" FROM "session"
		WHERE "user_id"=$1 AND "status"='active'
		FOR UPDATE
	`, s.UserID).Scan(&activeID, &activeSeen)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return "", err
	}

	// A third login must never jump ahead of an existing pending request. The
	// pending browser will take over itself if the incumbent becomes stale.
	var pendingExists bool
	if err := tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM "session" WHERE "user_id"=$1 AND "status"='pending')`, s.UserID).Scan(&pendingExists); err != nil {
		return "", err
	}
	if pendingExists {
		return "", ErrPendingSessionExists
	}

	if errors.Is(err, sql.ErrNoRows) || activeSeen.Before(staleBefore) {
		if activeID != "" {
			if _, err := tx.ExecContext(ctx, `UPDATE "session" SET "status"='replaced', "status_reason"='stale_takeover' WHERE "id"=$1`, activeID); err != nil {
				return "", err
			}
		}
		if _, err := tx.ExecContext(ctx, `UPDATE "session" SET "status"='rejected', "status_reason"='superseded' WHERE "user_id"=$1 AND "status"='pending'`, s.UserID); err != nil {
			return "", err
		}
		s.Status = SessionStatusActive
		if err := insertSession(ctx, tx, s); err != nil {
			return "", err
		}
		if err := tx.Commit(); err != nil {
			return "", err
		}
		return SessionStatusActive, nil
	}

	s.Status = SessionStatusPending
	if err := insertSession(ctx, tx, s); err != nil {
		return "", err
	}
	if err := tx.Commit(); err != nil {
		return "", err
	}
	return SessionStatusPending, nil
}

func (r *sessionRepositoryPG) GetValidByID(ctx context.Context, id string) (*Session, error) {
	s, err := scanSession(r.db.QueryRowContext(ctx, `SELECT `+sessionColumns+` FROM "session" WHERE "id"=$1`, id))
	if err != nil {
		return nil, err
	}
	if s.Status == SessionStatusPending {
		return nil, ErrSessionPending
	}
	if s.Status != SessionStatusActive {
		return nil, ErrSessionNotActive
	}
	return s, nil
}

func (r *sessionRepositoryPG) GetValidWithUserByID(ctx context.Context, id string) (*Session, *User, error) {
	row := r.db.QueryRowContext(ctx, `
		SELECT
			s."id", s."user_id", s."branch_id", s."pos_id", s."ip", s."user_agent", s."created_at", s."expires_at", s."last_seen_at", s."status", s."status_reason",
			u."id", u."username", u."role_id", u."name", u."password", u."is_active", u."is_superuser", u."custom_permissions",
			COALESCE(ub."branch_id", '')
		FROM "session" s
		JOIN "user" u ON u."id"=s."user_id"
		LEFT JOIN (SELECT "user_id", MIN("branch_id") AS "branch_id" FROM "user_branch" GROUP BY "user_id") ub ON ub."user_id"=u."id"
		WHERE s."id"=$1
	`, id)

	var s Session
	var u User
	var branchID, posID, ip, ua, reason sql.NullString
	var expires sql.NullTime
	var perms pq.StringArray
	if err := row.Scan(
		&s.ID, &s.UserID, &branchID, &posID, &ip, &ua, &s.CreatedAt, &expires, &s.LastSeen, &s.Status, &reason,
		&u.ID, &u.Username, &u.RoleID, &u.Name, &u.PasswordHash, &u.IsActive, &u.IsSuperuser, &perms, &u.BranchID,
	); err != nil {
		return nil, nil, err
	}
	if branchID.Valid {
		s.BranchID = branchID.String
	}
	if posID.Valid {
		s.POSID = posID.String
	}
	if ip.Valid {
		s.IP = ip.String
	}
	if ua.Valid {
		s.UserAgent = ua.String
	}
	if reason.Valid {
		s.Reason = reason.String
	}
	if expires.Valid {
		value := expires.Time
		s.ExpiresAt = &value
	}
	if perms != nil {
		u.CustomPermissions = []string(perms)
	}
	if s.Status == SessionStatusPending {
		return nil, nil, ErrSessionPending
	}
	if s.Status != SessionStatusActive {
		return nil, nil, ErrSessionNotActive
	}
	return &s, &u, nil
}

func (r *sessionRepositoryPG) GetSessionState(ctx context.Context, id string, staleBefore, now time.Time) (*SessionState, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()
	var userID string
	if err := tx.QueryRowContext(ctx, `SELECT "user_id" FROM "session" WHERE "id"=$1`, id).Scan(&userID); err != nil {
		return nil, err
	}
	if err := lockUser(ctx, tx, userID); err != nil {
		return nil, err
	}
	s, err := scanSession(tx.QueryRowContext(ctx, `SELECT `+sessionColumns+` FROM "session" WHERE "id"=$1 FOR UPDATE`, id))
	if err != nil {
		return nil, err
	}

	if s.Status == SessionStatusPending {
		var activeID string
		var activeSeen time.Time
		err := tx.QueryRowContext(ctx, `SELECT "id", "last_seen_at" FROM "session" WHERE "user_id"=$1 AND "status"='active' FOR UPDATE`, s.UserID).Scan(&activeID, &activeSeen)
		if errors.Is(err, sql.ErrNoRows) || (err == nil && activeSeen.Before(staleBefore)) {
			if activeID != "" {
				if _, err := tx.ExecContext(ctx, `UPDATE "session" SET "status"='replaced', "status_reason"='stale_takeover' WHERE "id"=$1`, activeID); err != nil {
					return nil, err
				}
			}
			if _, err := tx.ExecContext(ctx, `UPDATE "session" SET "status"='active', "status_reason"=NULL, "last_seen_at"=$2 WHERE "id"=$1`, id, now); err != nil {
				return nil, err
			}
			s.Status = SessionStatusActive
			s.Reason = ""
			s.LastSeen = now
		} else if err != nil {
			return nil, err
		}
	}

	state := &SessionState{Session: s}
	if s.Status == SessionStatusActive {
		if _, err := tx.ExecContext(ctx, `UPDATE "session" SET "last_seen_at"=$2 WHERE "id"=$1`, id, now); err != nil {
			return nil, err
		}
		s.LastSeen = now
		pending, err := scanSession(tx.QueryRowContext(ctx, `SELECT `+sessionColumns+` FROM "session" WHERE "user_id"=$1 AND "status"='pending'`, s.UserID))
		if err == nil {
			state.PendingLogin = pending
		} else if !errors.Is(err, sql.ErrNoRows) {
			return nil, err
		}
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return state, nil
}

func (r *sessionRepositoryPG) ResolveConflict(ctx context.Context, activeID, decision string, now time.Time) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var userID string
	if err := tx.QueryRowContext(ctx, `SELECT "user_id" FROM "session" WHERE "id"=$1 AND "status"='active'`, activeID).Scan(&userID); err != nil {
		return err
	}
	if err := lockUser(ctx, tx, userID); err != nil {
		return err
	}
	var stillActive bool
	if err := tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM "session" WHERE "id"=$1 AND "status"='active')`, activeID).Scan(&stillActive); err != nil {
		return err
	}
	if !stillActive {
		return ErrSessionNotActive
	}
	var pendingID string
	if err := tx.QueryRowContext(ctx, `SELECT "id" FROM "session" WHERE "user_id"=$1 AND "status"='pending' FOR UPDATE`, userID).Scan(&pendingID); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return ErrNotFound
		}
		return err
	}
	switch decision {
	case "stay":
		if _, err := tx.ExecContext(ctx, `UPDATE "session" SET "status"='rejected', "status_reason"='incumbent_stayed' WHERE "id"=$1`, pendingID); err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, `UPDATE "session" SET "last_seen_at"=$2 WHERE "id"=$1`, activeID, now); err != nil {
			return err
		}
	case "leave":
		if _, err := tx.ExecContext(ctx, `UPDATE "session" SET "status"='replaced', "status_reason"='incumbent_left' WHERE "id"=$1`, activeID); err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, `UPDATE "session" SET "status"='active', "status_reason"=NULL, "last_seen_at"=$2 WHERE "id"=$1`, pendingID, now); err != nil {
			return err
		}
	default:
		return errors.New("invalid conflict decision")
	}
	return tx.Commit()
}

func (r *sessionRepositoryPG) Logout(ctx context.Context, id string, now time.Time) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var userID string
	err = tx.QueryRowContext(ctx, `SELECT "user_id" FROM "session" WHERE "id"=$1`, id).Scan(&userID)
	if errors.Is(err, sql.ErrNoRows) {
		return nil
	}
	if err != nil {
		return err
	}
	if err := lockUser(ctx, tx, userID); err != nil {
		return err
	}
	s, err := scanSession(tx.QueryRowContext(ctx, `SELECT `+sessionColumns+` FROM "session" WHERE "id"=$1 FOR UPDATE`, id))
	if errors.Is(err, sql.ErrNoRows) {
		return nil
	}
	if err != nil {
		return err
	}
	if s.Status == SessionStatusActive {
		var pendingID string
		err := tx.QueryRowContext(ctx, `SELECT "id" FROM "session" WHERE "user_id"=$1 AND "status"='pending' FOR UPDATE`, s.UserID).Scan(&pendingID)
		if err == nil {
			if _, err := tx.ExecContext(ctx, `DELETE FROM "session" WHERE "id"=$1`, id); err != nil {
				return err
			}
			if _, err := tx.ExecContext(ctx, `UPDATE "session" SET "status"='active', "status_reason"=NULL, "last_seen_at"=$2 WHERE "id"=$1`, pendingID, now); err != nil {
				return err
			}
			return tx.Commit()
		} else if !errors.Is(err, sql.ErrNoRows) {
			return err
		}
	}
	if _, err := tx.ExecContext(ctx, `DELETE FROM "session" WHERE "id"=$1`, id); err != nil {
		return err
	}
	return tx.Commit()
}

func (r *sessionRepositoryPG) DeleteByID(ctx context.Context, id string) error {
	_, err := r.db.ExecContext(ctx, `DELETE FROM "session" WHERE "id"=$1`, id)
	return err
}

func (r *sessionRepositoryPG) DeleteExpired(ctx context.Context, now time.Time) error {
	_, err := r.db.ExecContext(ctx, `DELETE FROM "session" WHERE ("expires_at" IS NOT NULL AND "expires_at" <= $1) OR ("status" IN ('rejected','replaced') AND "last_seen_at" <= $1 - interval '24 hours')`, now)
	return err
}

func (r *sessionRepositoryPG) GetByUserID(ctx context.Context, userID string) ([]*Session, error) {
	rows, err := r.db.QueryContext(ctx, `SELECT `+sessionColumns+` FROM "session" WHERE "user_id"=$1 ORDER BY "created_at"`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var sessions []*Session
	for rows.Next() {
		s, err := scanSession(rows)
		if err != nil {
			return nil, err
		}
		sessions = append(sessions, s)
	}
	return sessions, rows.Err()
}

func (r *sessionRepositoryPG) Touch(ctx context.Context, id string, now time.Time) error {
	_, err := r.db.ExecContext(ctx, `UPDATE "session" SET "last_seen_at"=$1 WHERE "id"=$2 AND "status"='active'`, now, id)
	return err
}
