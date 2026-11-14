package store

import (
	"encoding/json"
	"errors"
	"github.com/Mickoki/zuma-health/server/internal/domain"
	"github.com/Mickoki/zuma-health/server/internal/games"
	"github.com/Mickoki/zuma-health/server/internal/testutil"
	"path/filepath"
	"sync"
	"testing"
	"time"
)

func TestGameRunReplayReopen(t *testing.T) {
	path := filepath.Join(t.TempDir(), "db")
	s, e := Open(path)
	if e != nil {
		t.Fatal(e)
	}
	p, _ := s.CreateProfile(ctx, "Crew")
	in := testutil.GameInput("pairs")
	a, created, e := s.SaveGameRun(ctx, p.ID, in)
	if e != nil || !created {
		t.Fatal(e)
	}
	// Change JSON key order without changing values.
	var raw map[string]any
	json.Unmarshal(in.Initial, &raw)
	in.Initial, _ = json.Marshal(raw)
	b, created, e := s.SaveGameRun(ctx, p.ID, in)
	if e != nil || created || a.ID != b.ID {
		t.Fatal("bad replay", e)
	}
	in.Source = "observed"
	if _, _, e = s.SaveGameRun(ctx, p.ID, in); !errors.Is(e, ErrConflict) {
		t.Fatal(e)
	}
	s.Close()
	s, e = Open(path)
	if e != nil {
		t.Fatal(e)
	}
	defer s.Close()
	b, e = s.GetGameRun(ctx, a.ID)
	if e != nil || b.GameID != "pairs" {
		t.Fatal(b, e)
	}
}
func TestGameConcurrentReplay(t *testing.T) {
	s, p := setup(t)
	var wg sync.WaitGroup
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if _, _, e := s.SaveGameRun(ctx, p.ID, testutil.GameInput("math")); e != nil {
				t.Error(e)
			}
		}()
	}
	wg.Wait()
	items, total, e := s.ListGameRuns(ctx, p.ID, "math", 20, 0)
	if e != nil || total != 1 || len(items) != 1 {
		t.Fatal(total, e)
	}
}
func TestGameBaselineByTimeAndSource(t *testing.T) {
	s, p := setup(t)
	in := testutil.GameInput("fifteen")
	cur, _, e := s.SaveGameRun(ctx, p.ID, in)
	if e != nil {
		t.Fatal(e)
	}
	for i, source := range []string{"synthetic", "observed"} {
		v := testutil.GameInput("fifteen")
		v.ClientRunID = []string{"123e4567-e89b-42d3-a456-426614174001", "123e4567-e89b-42d3-a456-426614174002"}[i]
		v.Source = source
		v.PerformedAt = v.PerformedAt.Add(time.Duration(i-2) * time.Hour)
		if _, _, e = s.SaveGameRun(ctx, p.ID, v); e != nil {
			t.Fatal(e)
		}
	}
	b, e := s.BaselineGameRun(ctx, cur)
	if e != nil || b == nil || b.Source != "synthetic" || !b.PerformedAt.Equal(in.PerformedAt.Add(-2*time.Hour)) {
		t.Fatal(b, e)
	}
}
func TestMigrationPreservesLegacy(t *testing.T) {
	s, p := setup(t)
	old := save(t, s, p.ID, testutil.Input())
	ex := domain.Explanation{Status: "ready", Model: "qwen3:8b"}
	if e := s.SaveExplanation(ctx, old.ID, "fingerprint", ex); e != nil {
		t.Fatal(e)
	}
	// Emulate populated version1 database by removing only new, empty tables.
	if _, e := s.db.Exec(`DROP TABLE game_run_explanations; DROP TABLE game_runs; PRAGMA user_version=1;`); e != nil {
		t.Fatal(e)
	}
	if e := s.migrate(ctx); e != nil {
		t.Fatal(e)
	}
	if _, e := s.GetSession(ctx, old.ID); e != nil {
		t.Fatal(e)
	}
	got, e := s.GetExplanation(ctx, old.ID, "fingerprint")
	if e != nil || got == nil {
		t.Fatal(e)
	}
	if _, _, e = s.SaveGameRun(ctx, p.ID, testutil.GameInput("chimp")); e != nil {
		t.Fatal(e)
	}
}
func TestGameReportAndFingerprint(t *testing.T) {
	v := testutil.GameInput("math")
	r := games.Run{ID: "current", ProfileID: "p", Input: v}
	b := r
	b.ID = "baseline"
	b.PerformedAt = b.PerformedAt.Add(-time.Hour)
	report, e := games.Calculate(r, &b)
	if e != nil || report.BaselineRunID == nil || *report.Deltas["correct"] != 0 {
		t.Fatal(report, e)
	}
	fp := games.Fingerprint(report)
	report.Explanation = &domain.Explanation{Status: "ready"}
	if fp != games.Fingerprint(report) {
		t.Fatal("explanation changed own fingerprint")
	}
	b.ID = "other"
	next, e := games.Calculate(r, &b)
	if e != nil || fp == games.Fingerprint(next) {
		t.Fatal("baseline identity not fingerprinted")
	}
}

func TestChimpLossHasComparableBaseline(t *testing.T) {
	s, p := setup(t)
	in := testutil.GameInput("chimp")
	in.Events = nil
	in.Status = "failed"
	in.FinishReason = "mistake_limit"
	for round := 0; round < 4; round++ {
		positions := []int{}
		for i := 0; i < 5; i++ {
			positions = append(positions, round*5+i)
		}
		in.Events = append(in.Events, games.Event{Kind: "show", TMS: testutil.P(int64(round * 200)), Positions: positions}, games.Event{Kind: "click", TMS: testutil.P(int64(round*200 + 100)), Index: testutil.P(round*5 + 4)})
	}
	in.DurationMS = testutil.P(int64(800))
	in.Events = append(in.Events, games.Event{Kind: "finish", TMS: testutil.P(int64(800))})
	earlier := in
	earlier.PerformedAt = in.PerformedAt.Add(-time.Hour)
	earlier.ClientRunID = "123e4567-e89b-42d3-a456-426614174001"
	old, _, err := s.SaveGameRun(ctx, p.ID, earlier)
	if err != nil {
		t.Fatal(err)
	}
	current, _, err := s.SaveGameRun(ctx, p.ID, in)
	if err != nil {
		t.Fatal(err)
	}
	baseline, err := s.BaselineGameRun(ctx, current)
	if err != nil || baseline == nil || baseline.ID != old.ID {
		t.Fatal(baseline, err)
	}
	report, err := games.Calculate(current, baseline)
	if err != nil || report.BaselineRunID == nil || report.Metrics["max_completed_count"] != nil {
		t.Fatal(report, err)
	}
}
