package httpapi

import (
	"encoding/json"
	"github.com/Mickoki/zuma-health/server/internal/domain"
	"github.com/Mickoki/zuma-health/server/internal/games"
	"github.com/Mickoki/zuma-health/server/internal/model"
	"github.com/Mickoki/zuma-health/server/internal/testutil"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestGameSurveySnapshotAndReplay(t *testing.T) {
	r := gameRig(t)
	in := testutil.GameInput("pairs")
	sleep, fatigue, stress, mood := 8.0, 0.0, 2.0, 7.0
	in.Survey = &domain.Survey{SleepHours: &sleep, Fatigue: &fatigue, Stress: &stress, Mood: &mood}
	body, _ := json.Marshal(in)
	path := "/api/v1/profiles/" + r.p.ID + "/game-runs"
	run := decode[games.Run](t, request(r.h, "POST", path, string(body)), 201)
	decode[games.Run](t, request(r.h, "POST", path, string(body)), 200)
	report := decode[games.Report](t, request(r.h, "GET", "/api/v1/game-runs/"+run.ID+"/report", ""), 200)
	if report.Survey == nil || *report.Survey.Fatigue != 0 || *report.Survey.SleepHours != 8 {
		t.Fatal(report.Survey)
	}
	html := request(r.h, "GET", "/api/v1/game-runs/"+run.ID+"/report.html", "")
	if !strings.Contains(html.Body.String(), "Сон: 8 ч") {
		t.Fatal(html.Body.String())
	}
	stress = 3
	changed, _ := json.Marshal(in)
	if w := request(r.h, "POST", path, string(changed)); w.Code != 409 {
		t.Fatal(w.Code)
	}
	stress = 11
	invalid, _ := json.Marshal(in)
	if w := request(r.h, "POST", path, string(invalid)); w.Code != 422 {
		t.Fatal(w.Code)
	}
}

func gameRig(t *testing.T) *rig {
	r := setup(t)
	remote := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		if r.fail.Load() {
			http.Error(w, "offline", 503)
			return
		}
		json.NewEncoder(w).Encode(map[string]any{"done": true, "message": map[string]string{"role": "assistant", "content": `{"observations":["duration_ms"],"comparisons":[],"limitations":[]}`}})
	}))
	t.Cleanup(remote.Close)
	c, _ := model.NewClient(remote.URL, "qwen3:8b", time.Second)
	r.h = New(r.s, c)
	return r
}
func TestFourGameHTTPWorkflows(t *testing.T) {
	for _, id := range []string{"fifteen", "pairs", "math", "chimp"} {
		t.Run(id, func(t *testing.T) {
			r := gameRig(t)
			in := testutil.GameInput(id)
			body, _ := json.Marshal(in)
			path := "/api/v1/profiles/" + r.p.ID + "/game-runs"
			run := decode[games.Run](t, request(r.h, "POST", path, string(body)), 201)
			again := decode[games.Run](t, request(r.h, "POST", path, string(body)), 200)
			if run.ID != again.ID {
				t.Fatal("duplicate run")
			}
			decode[games.Run](t, request(r.h, "GET", "/api/v1/game-runs/"+run.ID, ""), 200)
			rep := decode[games.Report](t, request(r.h, "GET", "/api/v1/game-runs/"+run.ID+"/report", ""), 200)
			if *rep.Metrics["duration_ms"] != float64(*in.DurationMS) {
				t.Fatal(rep)
			}
			out := decode[struct {
				Status string `json:"status"`
			}](t, request(r.h, "POST", "/api/v1/game-runs/"+run.ID+"/explanation", ""), 200)
			if out.Status != "ready" {
				t.Fatal(out)
			}
			r.fail.Store(true)
			out = decode[struct {
				Status string `json:"status"`
			}](t, request(r.h, "POST", "/api/v1/game-runs/"+run.ID+"/explanation", ""), 200)
			if out.Status != "unavailable" {
				t.Fatal(out)
			}
			rep = decode[games.Report](t, request(r.h, "GET", "/api/v1/game-runs/"+run.ID+"/report", ""), 200)
			if rep.Explanation == nil {
				t.Fatal("ready explanation lost")
			}
			html := request(r.h, "GET", "/api/v1/game-runs/"+run.ID+"/report.html", "")
			if html.Code != 200 || strings.Contains(html.Body.String(), "<script>") || !strings.Contains(html.Body.String(), "&lt;script&gt;") {
				t.Fatal(html.Code, html.Body.String())
			}
			page := decode[struct {
				Total int `json:"total"`
			}](t, request(r.h, "GET", path+"?game_id="+id, ""), 200)
			if page.Total != 1 {
				t.Fatal(page)
			}
		})
	}
}
func TestGameBodyLimitsAndInvalidReplay(t *testing.T) {
	r := gameRig(t)
	path := "/api/v1/profiles/" + r.p.ID + "/game-runs"
	body, _ := json.Marshal(testutil.GameInput("pairs"))
	decode[games.Run](t, request(r.h, "POST", path, strings.Repeat(" ", 300*1024)+string(body)), 201)
	for _, c := range []struct {
		path, body string
		status     int
	}{{path, strings.Repeat(" ", 1024*1024) + string(body), 413}, {"/api/v1/profiles/" + r.p.ID + "/sessions", strings.Repeat(" ", 300*1024) + testutil.SessionJSON, 413}, {path, strings.Replace(string(body), `"status":"completed"`, `"status":"aborted"`, 1), 422}} {
		w := request(r.h, "POST", c.path, c.body)
		if w.Code != c.status {
			t.Fatalf("%d want %d", w.Code, c.status)
		}
	}
	for _, q := range []string{"?game_id=bad", "?game_id=math&game_id=pairs"} {
		if w := request(r.h, "GET", path+q, ""); w.Code != 400 {
			t.Fatal(q, w.Code)
		}
	}
}
func TestGameBackfillInvalidatesExplanation(t *testing.T) {
	r := gameRig(t)
	in := testutil.GameInput("pairs")
	body, _ := json.Marshal(in)
	path := "/api/v1/profiles/" + r.p.ID + "/game-runs"
	cur := decode[games.Run](t, request(r.h, "POST", path, string(body)), 201)
	rp := "/api/v1/game-runs/" + cur.ID
	decode[map[string]any](t, request(r.h, "POST", rp+"/explanation", ""), 200)
	in.ClientRunID = "123e4567-e89b-42d3-a456-426614174001"
	in.PerformedAt = in.PerformedAt.Add(-time.Hour)
	body, _ = json.Marshal(in)
	decode[games.Run](t, request(r.h, "POST", path, string(body)), 201)
	rep := decode[games.Report](t, request(r.h, "GET", rp+"/report", ""), 200)
	if rep.BaselineRunID == nil || rep.Explanation != nil {
		t.Fatal("stale explanation")
	}
}

func TestLegacyAndGameExplanationShareSlot(t *testing.T) {
	for _, legacyFirst := range []bool{true, false} {
		name := "game_first"
		if legacyFirst {
			name = "legacy_first"
		}
		t.Run(name, func(t *testing.T) {
			r := setup(t)
			entered := make(chan struct{}, 2)
			release := make(chan struct{})
			remote := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
				entered <- struct{}{}
				<-release
				http.Error(w, "unavailable", 503)
			}))
			defer remote.Close()
			defer close(release)
			client, _ := model.NewClient(remote.URL, "qwen3:8b", time.Second)
			r.h = New(r.s, client)
			old := r.save(t, testutil.SessionJSON)
			body, _ := json.Marshal(testutil.GameInput("pairs"))
			run := decode[games.Run](t, request(r.h, "POST", "/api/v1/profiles/"+r.p.ID+"/game-runs", string(body)), 201)
			first, second := "/api/v1/game-runs/"+run.ID+"/explanation", "/api/v1/sessions/"+old.ID+"/explanation"
			if legacyFirst {
				first, second = second, first
			}
			done := make(chan *httptest.ResponseRecorder, 1)
			go func() { done <- request(r.h, "POST", first, "") }()
			select {
			case <-entered:
			case <-time.After(time.Second):
				t.Fatal("generation did not enter")
			}
			busy := request(r.h, "POST", second, "")
			if busy.Code != 409 {
				t.Fatalf("expected shared-slot409, got%d", busy.Code)
			}
			// Let the first request reach its bounded timeout; report endpoints remain usable.
			select {
			case result := <-done:
				if result.Code != 200 {
					t.Fatal(result.Code)
				}
			case <-time.After(2 * time.Second):
				t.Fatal("generation did not timeout")
			}
			decode[games.Report](t, request(r.h, "GET", "/api/v1/game-runs/"+run.ID+"/report", ""), 200)
		})
	}
}
