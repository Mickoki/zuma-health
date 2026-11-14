package domain

import (
	"math"
	"testing"
	"time"
)

func ptr[T any](v T) *T { return &v }

func sample() Session {
	return Session{ID: "current", ProfileID: "profile", SessionInput: SessionInput{
		ClientSessionID: "123e4567-e89b-42d3-a456-426614174000", PerformedAt: time.Date(2026, 1, 2, 0, 0, 0, 0, time.UTC),
		ProtocolVersion: "reaction-memory-v1", Source: "synthetic",
		Survey:   &Survey{SleepHours: ptr(8.0), Fatigue: ptr(0.0), Stress: ptr(2.0), Mood: ptr(7.0)},
		Reaction: &Reaction{Trials: []Trial{{Outcome: "valid", ReactionMS: ptr(100.0)}, {Outcome: "valid", ReactionMS: ptr(200.0)}, {Outcome: "valid", ReactionMS: ptr(300.0)}, {Outcome: "valid", ReactionMS: ptr(400.0)}, {Outcome: "premature"}, {Outcome: "missed"}}},
		Memory:   &Memory{Correct: ptr(3), Total: ptr(4)}}}
}

func TestCalculateKnownResults(t *testing.T) {
	s := sample()
	b := sample()
	b.ID = "baseline"
	b.PerformedAt = b.PerformedAt.Add(-time.Hour)
	b.Reaction.Trials = []Trial{{Outcome: "valid", ReactionMS: ptr(200.0)}}
	r := Calculate(s, &b)
	if *r.Reaction.MeanMS != 250 || *r.Reaction.MedianMS != 250 || r.Reaction.Valid != 4 || r.Reaction.Premature != 1 || r.Reaction.Missed != 1 || r.MemoryPercent != 75 {
		t.Fatalf("wrong report: %+v", r)
	}
	if r.Comparison == nil || *r.Comparison.ReactionDeltaMS != 50 || *r.Comparison.ReactionDeltaPercent != 25 || r.Comparison.MemoryDeltaPP != 0 {
		t.Fatalf("wrong comparison: %+v", r.Comparison)
	}
}
func TestNoValidReaction(t *testing.T) {
	s := sample()
	s.Reaction.Trials = []Trial{{Outcome: "missed"}}
	r := Calculate(s, nil)
	if r.Reaction.MeanMS != nil || r.Reaction.MedianMS != nil || r.Comparison != nil || r.BaselineSessionID != nil {
		t.Fatal("missing values replaced by numbers")
	}
	facts := BuildFacts(r)
	found := false
	for _, f := range facts {
		if f.ID == "no_valid_reaction" {
			found = true
		}
	}
	if !found {
		t.Fatal("missing limitation")
	}
}
func TestIncompatibleBaseline(t *testing.T) {
	for _, change := range []func(*Session){func(b *Session) { b.Source = "observed" }, func(b *Session) { b.ProtocolVersion = "other" }, func(b *Session) { b.ProfileID = "other" }, func(b *Session) { b.PerformedAt = sample().PerformedAt }} {
		s := sample()
		b := sample()
		b.PerformedAt = b.PerformedAt.Add(-time.Hour)
		change(&b)
		if Calculate(s, &b).Comparison != nil {
			t.Fatal("incompatible baseline accepted")
		}
	}
}
func TestValidateRequiredZeroValues(t *testing.T) {
	s := sample()
	now := s.PerformedAt
	if e := ValidateSession(s.SessionInput, now); len(e) != 0 {
		t.Fatal(e)
	}
	s.Survey.Fatigue = nil
	if len(ValidateSession(s.SessionInput, now)) == 0 {
		t.Fatal("missing fatigue accepted")
	}
}
func TestValidateBounds(t *testing.T) {
	cases := []func(*Session){func(s *Session) { s.Survey.SleepHours = ptr(25.0) }, func(s *Session) { s.Memory.Total = ptr(0) }, func(s *Session) { s.Memory.Correct = ptr(5) }, func(s *Session) { s.Reaction.Trials[0].ReactionMS = ptr(math.NaN()) }, func(s *Session) { s.Reaction.Trials[4].ReactionMS = ptr(1.0) }, func(s *Session) { s.ProtocolVersion = "unknown" }, func(s *Session) { s.Source = "watch" }, func(s *Session) { s.PerformedAt = s.PerformedAt.Add(6 * time.Minute) }, func(s *Session) { s.ClientSessionID = "x" }, func(s *Session) { s.Reaction.Trials = nil }, func(s *Session) { s.Survey = nil }, func(s *Session) { s.Memory = nil }}
	for i, change := range cases {
		s := sample()
		now := s.PerformedAt
		change(&s)
		if len(ValidateSession(s.SessionInput, now)) == 0 {
			t.Errorf("case %d accepted", i)
		}
	}
}
