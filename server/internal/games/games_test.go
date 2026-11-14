package games_test

import (
	"encoding/json"
	"github.com/Mickoki/zuma-health/server/internal/games"
	"github.com/Mickoki/zuma-health/server/internal/testutil"
	"testing"
	"time"
)

func TestKnownCompletedGames(t *testing.T) {
	for _, id := range []string{"fifteen", "pairs", "math", "chimp"} {
		t.Run(id, func(t *testing.T) {
			v := testutil.GameInput(id)
			m, e := games.Validate(v, time.Now())
			if e != nil {
				t.Fatal(e)
			}
			key, want := "moves", 30.0
			switch id {
			case "pairs":
				key, want = "attempts", 9
			case "math":
				key, want = "accuracy_percent", 100
			case "chimp":
				key, want = "max_completed_count", 12
			}
			if m[key] == nil || *m[key] != want {
				t.Fatalf("%s expected %g: %+v", key, want, m)
			}
		})
	}
}
func TestReplayRejectsForgedGames(t *testing.T) {
	for _, id := range []string{"fifteen", "pairs", "math", "chimp"} {
		t.Run(id, func(t *testing.T) {
			v := testutil.GameInput(id)
			switch id {
			case "fifteen":
				v.Events[0].Index = testutil.P(0)
			case "pairs":
				v.Events[0].TMS = testutil.P(int64(0))
			case "math":
				v.Events[1].TMS = testutil.P(int64(8000))
			case "chimp":
				v.Events[1].Index = testutil.P(4)
			}
			if _, e := games.Validate(v, time.Now()); e == nil {
				t.Fatal("forged log accepted")
			}
		})
	}
}
func TestRequiredAndLimits(t *testing.T) {
	cases := []func(*games.Input){func(v *games.Input) { v.DurationMS = nil }, func(v *games.Input) { v.RulesVersion = nil }, func(v *games.Input) { v.Config = nil }, func(v *games.Input) { v.Events[0].TMS = nil }, func(v *games.Input) { v.ClientRunID = "x" }, func(v *games.Input) { v.Source = "watch" }, func(v *games.Input) { v.PerformedAt = time.Now().Add(time.Hour) }, func(v *games.Input) { v.Status = "aborted" }, func(v *games.Input) { v.Events = append(v.Events, v.Events[0]) }, func(v *games.Input) { v.Events[0].TMS = testutil.P(int64(-1)) }}
	for i, change := range cases {
		v := testutil.GameInput("fifteen")
		change(&v)
		if _, e := games.Validate(v, time.Now()); e == nil {
			t.Errorf("case %d accepted", i)
		}
	}
}
func TestAbortedGames(t *testing.T) {
	for _, id := range []string{"fifteen", "pairs", "math", "chimp"} {
		v := testutil.GameInput(id)
		v.Events = []games.Event{{Kind: "finish", TMS: testutil.P(int64(0))}}
		v.Status = "aborted"
		v.FinishReason = "user_exit"
		v.DurationMS = testutil.P(int64(0))
		if _, e := games.Validate(v, time.Now()); e != nil {
			t.Errorf("%s: %v", id, e)
		}
	}
}
func TestInvalidInitials(t *testing.T) {
	for _, id := range []string{"fifteen", "pairs", "math", "chimp"} {
		v := testutil.GameInput(id)
		v.Initial = json.RawMessage(`{"unknown":1}`)
		if _, e := games.Validate(v, time.Now()); e == nil {
			t.Fatal(id)
		}
	}
}
func TestDefaultsIncreased(t *testing.T) {
	p, _ := games.Defaults("pairs", "hard")
	f, _ := games.Defaults("fifteen", "hard")
	c, _ := games.Defaults("chimp", "hard")
	if p["pairs"] != 18 || f["shuffle_moves"] != 180 || c["target_count"] != 24 {
		t.Fatal(p, f, c)
	}
}
