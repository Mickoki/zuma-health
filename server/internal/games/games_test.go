package games_test

import (
	"encoding/json"
	"github.com/Mickoki/zuma-health/server/internal/games"
	"github.com/Mickoki/zuma-health/server/internal/testutil"
	"os"
	"path/filepath"
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

func TestGodotGeneratedRuns(t *testing.T) {
	folder := os.Getenv("ZUMA_GODOT_FIXTURES")
	if folder == "" {
		t.Skip("set ZUMA_GODOT_FIXTURES to cross-check actual Godot exports")
	}
	files, err := filepath.Glob(filepath.Join(folder, "*.json"))
	if err != nil || len(files) != 12 {
		t.Fatalf("want12 exports, got%d: %v", len(files), err)
	}
	for _, file := range files {
		t.Run(filepath.Base(file), func(t *testing.T) {
			b, e := os.ReadFile(file)
			if e != nil {
				t.Fatal(e)
			}
			var in games.Input
			if e = json.Unmarshal(b, &in); e != nil {
				t.Fatal(e)
			}
			if _, e = games.Validate(in, time.Now()); e != nil {
				t.Fatal(e)
			}
		})
	}
}

func TestMathCannotAbortPastUnresolvedDeadline(t *testing.T) {
	for _, ms := range []int64{8000, 60000, 60001} {
		v := testutil.GameInput("math")
		v.Status = "aborted"
		v.FinishReason = "user_exit"
		v.DurationMS = testutil.P(ms)
		v.Events = []games.Event{{Kind: "show", TMS: testutil.P(int64(0)), Index: testutil.P(0)}, {Kind: "finish", TMS: testutil.P(ms)}}
		if _, e := games.Validate(v, time.Now()); e == nil {
			t.Errorf("abort at%d accepted without mandatory timeout", ms)
		}
	}
}

func TestNullArrayElementsRejected(t *testing.T) {
	for _, game := range []string{"fifteen", "pairs", "math", "chimp"} {
		t.Run(game, func(t *testing.T) {
			v := testutil.GameInput(game)
			if game == "chimp" {
				b, _ := json.Marshal(v)
				var raw map[string]any
				json.Unmarshal(b, &raw)
				events := raw["events"].([]any)
				positions := events[0].(map[string]any)["positions"].([]any)
				positions[0] = nil
				b, _ = json.Marshal(raw)
				var decoded games.Input
				e := json.Unmarshal(b, &decoded)
				if e == nil {
					_, e = games.Validate(decoded, time.Now())
				}
				if e == nil {
					t.Fatal("null position accepted")
				}
				return
			}
			var initial map[string]any
			json.Unmarshal(v.Initial, &initial)
			switch game {
			case "fifteen":
				board := initial["board"].([]any)
				for i, x := range board {
					if x == float64(0) {
						board[i] = nil
						break
					}
				}
			case "pairs":
				initial["cards"].([]any)[0] = nil
			case "math":
				initial["questions"].([]any)[0].(map[string]any)["options"].([]any)[0] = nil
			}
			v.Initial, _ = json.Marshal(initial)
			if _, e := games.Validate(v, time.Now()); e == nil {
				t.Fatal("null integer interpreted as zero")
			}
		})
	}
}
