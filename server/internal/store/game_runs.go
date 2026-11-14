package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/Mickoki/zuma-health/server/internal/domain"
	"github.com/Mickoki/zuma-health/server/internal/games"
	"time"
)

func (s *Store) SaveGameRun(ctx context.Context, profileID string, input games.Input) (games.Run, bool, error) {
	if _, err := games.Validate(input, time.Now()); err != nil {
		return games.Run{}, false, fmt.Errorf("%w: %v", ErrInvalid, err)
	}
	payload, err := games.Canonical(input)
	if err != nil {
		return games.Run{}, false, err
	}
	if err = json.Unmarshal(payload, &input); err != nil {
		return games.Run{}, false, err
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return games.Run{}, false, err
	}
	defer tx.Rollback()
	var exists int
	if err = tx.QueryRowContext(ctx, "SELECT 1 FROM profiles WHERE id=?", profileID).Scan(&exists); err != nil {
		return games.Run{}, false, notFound(err)
	}
	var old, doc string
	err = tx.QueryRowContext(ctx, "SELECT payload,document FROM game_runs WHERE profile_id=? AND client_run_id=?", profileID, input.ClientRunID).Scan(&old, &doc)
	if err == nil {
		if old != string(payload) {
			return games.Run{}, false, ErrConflict
		}
		var r games.Run
		err = json.Unmarshal([]byte(doc), &r)
		return r, false, err
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return games.Run{}, false, err
	}
	r := games.Run{ID: id(), ProfileID: profileID, ReceivedAt: time.Now().UTC(), CalculationVersion: "v1", Input: input}
	document, err := json.Marshal(r)
	if err != nil {
		return r, false, err
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO game_runs(id,profile_id,client_run_id,game_id,performed_at,comparison_key,payload,document) VALUES(?,?,?,?,?,?,?,?)`, r.ID, r.ProfileID, r.ClientRunID, r.GameID, stamp(r.PerformedAt), games.ComparisonKey(r.Input), string(payload), string(document))
	if err != nil {
		return r, false, err
	}
	return r, true, tx.Commit()
}
func scanGame(row interface{ Scan(...any) error }) (games.Run, error) {
	var document string
	var r games.Run
	if err := row.Scan(&document); err != nil {
		return r, notFound(err)
	}
	err := json.Unmarshal([]byte(document), &r)
	return r, err
}
func (s *Store) GetGameRun(ctx context.Context, key string) (games.Run, error) {
	return scanGame(s.db.QueryRowContext(ctx, "SELECT document FROM game_runs WHERE id=?", key))
}
func (s *Store) ListGameRuns(ctx context.Context, profileID, gameID string, limit, offset int) ([]games.Run, int, error) {
	if _, err := s.GetProfile(ctx, profileID); err != nil {
		return nil, 0, err
	}
	filter := "profile_id=?"
	args := []any{profileID}
	if gameID != "" {
		filter += " AND game_id=?"
		args = append(args, gameID)
	}
	var total int
	if err := s.db.QueryRowContext(ctx, "SELECT count(*) FROM game_runs WHERE "+filter, args...).Scan(&total); err != nil {
		return nil, 0, err
	}
	pageArgs := append(append([]any{}, args...), limit, offset)
	rows, err := s.db.QueryContext(ctx, "SELECT document FROM game_runs WHERE "+filter+" ORDER BY performed_at DESC,id DESC LIMIT ? OFFSET ?", pageArgs...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	items := []games.Run{}
	for rows.Next() {
		r, e := scanGame(rows)
		if e != nil {
			return nil, 0, e
		}
		items = append(items, r)
	}
	return items, total, rows.Err()
}
func (s *Store) BaselineGameRun(ctx context.Context, r games.Run) (*games.Run, error) {
	key := games.ComparisonKey(r.Input)
	if key == "" {
		return nil, nil
	}
	b, err := scanGame(s.db.QueryRowContext(ctx, `SELECT document FROM game_runs WHERE profile_id=? AND comparison_key=? AND performed_at<? ORDER BY performed_at DESC,id DESC LIMIT 1`, r.ProfileID, key, stamp(r.PerformedAt)))
	if errors.Is(err, ErrNotFound) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &b, nil
}
func (s *Store) SaveGameExplanation(ctx context.Context, runID, fingerprint string, v domain.Explanation) error {
	if v.Status != "ready" {
		return ErrInvalid
	}
	b, err := json.Marshal(v)
	if err != nil {
		return err
	}
	_, err = s.db.ExecContext(ctx, `INSERT INTO game_run_explanations(run_id,fingerprint,document) VALUES(?,?,?) ON CONFLICT(run_id,fingerprint) DO UPDATE SET document=excluded.document`, runID, fingerprint, string(b))
	return err
}
func (s *Store) GetGameExplanation(ctx context.Context, runID, fingerprint string) (*domain.Explanation, error) {
	var b string
	err := s.db.QueryRowContext(ctx, "SELECT document FROM game_run_explanations WHERE run_id=? AND fingerprint=?", runID, fingerprint).Scan(&b)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var v domain.Explanation
	err = json.Unmarshal([]byte(b), &v)
	return &v, err
}
