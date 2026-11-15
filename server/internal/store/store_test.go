package store

import (
	"context"
	"errors"
	"fmt"
	"github.com/Mickoki/zuma-health/server/internal/domain"
	"github.com/Mickoki/zuma-health/server/internal/testutil"
	"math"
	"path/filepath"
	"sync"
	"testing"
	"time"
)

var ctx = context.Background()

func setup(t *testing.T) (*Store, domain.Profile) {
	t.Helper()
	s, e := Open(filepath.Join(t.TempDir(), "data.db"))
	if e != nil {
		t.Fatal(e)
	}
	t.Cleanup(func() { s.Close() })
	p, e := s.CreateProfile(ctx, "Crew")
	if e != nil {
		t.Fatal(e)
	}
	return s, p
}
func save(t *testing.T, s *Store, p string, in domain.SessionInput) domain.Session {
	t.Helper()
	v, _, e := s.SaveSession(ctx, p, in)
	if e != nil {
		t.Fatal(e)
	}
	return v
}
func TestPersistenceAfterReopen(t *testing.T) {
	path := filepath.Join(t.TempDir(), "db")
	s, e := Open(path)
	if e != nil {
		t.Fatal(e)
	}
	p, e := s.CreateProfile(ctx, "Crew")
	if e != nil {
		t.Fatal(e)
	}
	v := save(t, s, p.ID, testutil.Input())
	s.Close()
	s, e = Open(path)
	if e != nil {
		t.Fatal(e)
	}
	defer s.Close()
	got, e := s.GetSession(ctx, v.ID)
	if e != nil || *got.Memory.Correct != 3 || got.CalculationVersion != "v1" {
		t.Fatalf("%+v %v", got, e)
	}
}
func TestMigrateTwice(t *testing.T) {
	path := filepath.Join(t.TempDir(), "db")
	for i := 0; i < 2; i++ {
		s, e := Open(path)
		if e != nil {
			t.Fatal(e)
		}
		s.Close()
	}
}
func TestIdempotencyAndConflict(t *testing.T) {
	s, p := setup(t)
	in := testutil.Input()
	a := save(t, s, p.ID, in)
	loc := time.FixedZone("offset", 5*3600)
	in.PerformedAt = in.PerformedAt.In(loc)
	b, created, e := s.SaveSession(ctx, p.ID, in)
	if e != nil || created || a.ID != b.ID {
		t.Fatalf("replay %v %v", created, e)
	}
	*in.Memory.Correct = 2
	if _, _, e = s.SaveSession(ctx, p.ID, in); !errors.Is(e, ErrConflict) {
		t.Fatal(e)
	}
}
func TestConcurrentReplay(t *testing.T) {
	s, p := setup(t)
	var wg sync.WaitGroup
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if _, _, e := s.SaveSession(ctx, p.ID, testutil.Input()); e != nil {
				t.Error(e)
			}
		}()
	}
	wg.Wait()
	items, total, e := s.ListSessions(ctx, p.ID, 20, 0)
	if e != nil || len(items) != 1 || total != 1 {
		t.Fatalf("%d %d %v", len(items), total, e)
	}
}
func TestBaselineByPerformedTime(t *testing.T) {
	s, p := setup(t)
	cur := save(t, s, p.ID, testutil.Input())
	for i, h := range []int{-3, -1, -2, 0, 1} {
		in := testutil.Input()
		in.ClientSessionID = fmt.Sprintf("123e4567-e89b-42d3-a456-%012d", i+1)
		in.PerformedAt = in.PerformedAt.Add(time.Duration(h) * time.Hour)
		save(t, s, p.ID, in)
	}
	b, e := s.Baseline(ctx, cur)
	if e != nil || b == nil || !b.PerformedAt.Equal(cur.PerformedAt.Add(-time.Hour)) {
		t.Fatalf("%+v %v", b, e)
	}
}
func TestSourceIsolation(t *testing.T) {
	s, p := setup(t)
	cur := save(t, s, p.ID, testutil.Input())
	in := testutil.Input()
	in.ClientSessionID = "123e4567-e89b-42d3-a456-426614174001"
	in.Source = "observed"
	in.PerformedAt = in.PerformedAt.Add(-time.Hour)
	save(t, s, p.ID, in)
	b, e := s.Baseline(ctx, cur)
	if e != nil || b != nil {
		t.Fatalf("mixed sources: %+v %v", b, e)
	}
}
func TestMissingProfileAtomicity(t *testing.T) {
	s, _ := setup(t)
	if _, _, e := s.SaveSession(ctx, "00000000000000000000000000000000", testutil.Input()); !errors.Is(e, ErrNotFound) {
		t.Fatal(e)
	}
	var n int
	if e := s.db.QueryRow("SELECT count(*) FROM sessions").Scan(&n); e != nil || n != 0 {
		t.Fatalf("%d %v", n, e)
	}
}
func TestExplanationFingerprint(t *testing.T) {
	s, p := setup(t)
	v := save(t, s, p.ID, testutil.Input())
	value := domain.Explanation{Status: "ready", Model: "qwen3:8b"}
	if e := s.SaveExplanation(ctx, v.ID, "one", value); e != nil {
		t.Fatal(e)
	}
	a, e := s.GetExplanation(ctx, v.ID, "one")
	if e != nil || a == nil || a.Status != "ready" {
		t.Fatal(a, e)
	}
	b, e := s.GetExplanation(ctx, v.ID, "two")
	if e != nil || b != nil {
		t.Fatal(b, e)
	}
}

func TestSignedZeroReplay(t *testing.T) {
	s, p := setup(t)
	input := testutil.Input()
	negativeZero := math.Copysign(0, -1)
	input.Survey.Fatigue = &negativeZero
	first := save(t, s, p.ID, input)
	if !math.Signbit(*input.Survey.Fatigue) {
		t.Fatal("store mutated caller input")
	}
	again := testutil.Input()
	second, created, err := s.SaveSession(ctx, p.ID, again)
	if err != nil || created || first.ID != second.ID {
		t.Fatalf("signed zero is a numerical replay: created=%v err=%v", created, err)
	}
}
