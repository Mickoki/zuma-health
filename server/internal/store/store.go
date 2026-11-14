package store

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/Mickoki/zuma-health/server/internal/domain"
	_ "modernc.org/sqlite"
)

var ErrNotFound = errors.New("not found")
var ErrConflict = errors.New("idempotency conflict")
var ErrInvalid = errors.New("invalid input")

type Store struct{ db *sql.DB }

func Open(path string) (*Store, error) {
	abs, err := filepath.Abs(path)
	if err != nil {
		return nil, err
	}
	if err = os.MkdirAll(filepath.Dir(abs), 0700); err != nil {
		return nil, err
	}
	u := url.URL{Scheme: "file", Path: "/" + strings.TrimLeft(filepath.ToSlash(abs), "/")}
	q := u.Query()
	q.Add("_pragma", "foreign_keys(1)")
	q.Add("_pragma", "busy_timeout(5000)")
	q.Add("_pragma", "journal_mode(WAL)")
	u.RawQuery = q.Encode()
	db, err := sql.Open("sqlite", u.String())
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	db.SetMaxIdleConns(1)
	s := &Store{db: db}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err = s.migrate(ctx); err != nil {
		db.Close()
		return nil, err
	}
	return s, nil
}
func (s *Store) Close() error                   { return s.db.Close() }
func (s *Store) Ping(ctx context.Context) error { return s.db.PingContext(ctx) }
func id() string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		panic(err)
	}
	return hex.EncodeToString(b[:])
}
func stamp(t time.Time) string { return t.UTC().Format("2006-01-02T15:04:05.000000000Z") }
func notFound(err error) error {
	if errors.Is(err, sql.ErrNoRows) {
		return ErrNotFound
	}
	return err
}

func (s *Store) CreateProfile(ctx context.Context, name string) (domain.Profile, error) {
	if !domain.ValidName(name) {
		return domain.Profile{}, ErrInvalid
	}
	p := domain.Profile{ID: id(), DisplayName: strings.TrimSpace(name), CreatedAt: time.Now().UTC()}
	_, err := s.db.ExecContext(ctx, "INSERT INTO profiles(id,display_name,created_at) VALUES(?,?,?)", p.ID, p.DisplayName, stamp(p.CreatedAt))
	return p, err
}
func (s *Store) GetProfile(ctx context.Context, key string) (domain.Profile, error) {
	var p domain.Profile
	var created string
	err := s.db.QueryRowContext(ctx, "SELECT id,display_name,created_at FROM profiles WHERE id=?", key).Scan(&p.ID, &p.DisplayName, &created)
	if err != nil {
		return p, notFound(err)
	}
	p.CreatedAt, err = time.Parse(time.RFC3339Nano, created)
	return p, err
}
func (s *Store) ListProfiles(ctx context.Context, limit, offset int) ([]domain.Profile, int, error) {
	items := []domain.Profile{}
	var total int
	if err := s.db.QueryRowContext(ctx, "SELECT count(*) FROM profiles").Scan(&total); err != nil {
		return nil, 0, err
	}
	rows, err := s.db.QueryContext(ctx, "SELECT id,display_name,created_at FROM profiles ORDER BY created_at DESC,id DESC LIMIT ? OFFSET ?", limit, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	for rows.Next() {
		var p domain.Profile
		var created string
		if err = rows.Scan(&p.ID, &p.DisplayName, &created); err != nil {
			return nil, 0, err
		}
		p.CreatedAt, err = time.Parse(time.RFC3339Nano, created)
		if err != nil {
			return nil, 0, err
		}
		items = append(items, p)
	}
	return items, total, rows.Err()
}
func (s *Store) SaveSession(ctx context.Context, profileID string, input domain.SessionInput) (domain.Session, bool, error) {
	if len(domain.ValidateSession(input, time.Now())) > 0 {
		return domain.Session{}, false, ErrInvalid
	}
	input.PerformedAt = input.PerformedAt.UTC()
	input.ClientSessionID = strings.ToLower(input.ClientSessionID)
	payload, err := json.Marshal(input)
	if err != nil {
		return domain.Session{}, false, err
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return domain.Session{}, false, err
	}
	defer tx.Rollback()
	var exists int
	if err = tx.QueryRowContext(ctx, "SELECT 1 FROM profiles WHERE id=?", profileID).Scan(&exists); err != nil {
		return domain.Session{}, false, notFound(err)
	}
	var existingPayload, document string
	err = tx.QueryRowContext(ctx, "SELECT payload,document FROM sessions WHERE profile_id=? AND client_session_id=?", profileID, input.ClientSessionID).Scan(&existingPayload, &document)
	if err == nil {
		if existingPayload != string(payload) {
			return domain.Session{}, false, ErrConflict
		}
		var existing domain.Session
		err = json.Unmarshal([]byte(document), &existing)
		return existing, false, err
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return domain.Session{}, false, err
	}
	v := domain.Session{ID: id(), ProfileID: profileID, ReceivedAt: time.Now().UTC(), CalculationVersion: "v1", SessionInput: input}
	doc, err := json.Marshal(v)
	if err != nil {
		return v, false, err
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO sessions(id,profile_id,client_session_id,performed_at,protocol_version,source,payload,document) VALUES(?,?,?,?,?,?,?,?)`, v.ID, v.ProfileID, v.ClientSessionID, stamp(v.PerformedAt), v.ProtocolVersion, v.Source, string(payload), string(doc))
	if err != nil {
		return v, false, err
	}
	return v, true, tx.Commit()
}
func scanSession(row interface{ Scan(...any) error }) (domain.Session, error) {
	var document string
	var s domain.Session
	err := row.Scan(&document)
	if err != nil {
		return s, notFound(err)
	}
	err = json.Unmarshal([]byte(document), &s)
	return s, err
}
func (s *Store) GetSession(ctx context.Context, key string) (domain.Session, error) {
	return scanSession(s.db.QueryRowContext(ctx, "SELECT document FROM sessions WHERE id=?", key))
}
func (s *Store) ListSessions(ctx context.Context, profileID string, limit, offset int) ([]domain.Session, int, error) {
	if _, err := s.GetProfile(ctx, profileID); err != nil {
		return nil, 0, err
	}
	items := []domain.Session{}
	var total int
	if err := s.db.QueryRowContext(ctx, "SELECT count(*) FROM sessions WHERE profile_id=?", profileID).Scan(&total); err != nil {
		return nil, 0, err
	}
	rows, err := s.db.QueryContext(ctx, "SELECT document FROM sessions WHERE profile_id=? ORDER BY performed_at DESC,id DESC LIMIT ? OFFSET ?", profileID, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	for rows.Next() {
		v, e := scanSession(rows)
		if e != nil {
			return nil, 0, e
		}
		items = append(items, v)
	}
	return items, total, rows.Err()
}
func (s *Store) Baseline(ctx context.Context, v domain.Session) (*domain.Session, error) {
	b, err := scanSession(s.db.QueryRowContext(ctx, `SELECT document FROM sessions WHERE profile_id=? AND source=? AND protocol_version=? AND performed_at<? ORDER BY performed_at DESC,id DESC LIMIT 1`, v.ProfileID, v.Source, v.ProtocolVersion, stamp(v.PerformedAt)))
	if errors.Is(err, ErrNotFound) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &b, nil
}
func (s *Store) SaveExplanation(ctx context.Context, sessionID, fingerprint string, v domain.Explanation) error {
	if v.Status != "ready" {
		return fmt.Errorf("%w: only ready explanations may be stored", ErrInvalid)
	}
	doc, err := json.Marshal(v)
	if err != nil {
		return err
	}
	_, err = s.db.ExecContext(ctx, `INSERT INTO explanations(session_id,fingerprint,document) VALUES(?,?,?) ON CONFLICT(session_id,fingerprint) DO UPDATE SET document=excluded.document`, sessionID, fingerprint, string(doc))
	return err
}
func (s *Store) GetExplanation(ctx context.Context, sessionID, fingerprint string) (*domain.Explanation, error) {
	var document string
	err := s.db.QueryRowContext(ctx, "SELECT document FROM explanations WHERE session_id=? AND fingerprint=?", sessionID, fingerprint).Scan(&document)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var v domain.Explanation
	err = json.Unmarshal([]byte(document), &v)
	return &v, err
}
