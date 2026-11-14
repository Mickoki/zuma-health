package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"github.com/Mickoki/zuma-health/server/internal/domain"
	"github.com/Mickoki/zuma-health/server/internal/model"
	"github.com/Mickoki/zuma-health/server/internal/store"
	"github.com/Mickoki/zuma-health/server/internal/testutil"
	"io"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

type rig struct {
	h    http.Handler
	s    *store.Store
	p    domain.Profile
	fail atomic.Bool
}

func setup(t *testing.T) *rig {
	t.Helper()
	s, e := store.Open(filepath.Join(t.TempDir(), "db"))
	if e != nil {
		t.Fatal(e)
	}
	t.Cleanup(func() { s.Close() })
	p, e := s.CreateProfile(context.Background(), "<script>alert(1)</script>")
	if e != nil {
		t.Fatal(e)
	}
	r := &rig{s: s, p: p}
	ollama := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		if r.fail.Load() {
			http.Error(w, "offline", 503)
			return
		}
		io.Copy(io.Discard, req.Body)
		json.NewEncoder(w).Encode(map[string]any{"model": "qwen3:8b", "done": true, "message": map[string]string{"role": "assistant", "content": `{"observations":["reaction_median"],"comparisons":[],"limitations":[]}`}})
	}))
	t.Cleanup(ollama.Close)
	c, _ := model.NewClient(ollama.URL, "qwen3:8b", time.Second)
	r.h = New(s, c)
	return r
}
func request(h http.Handler, method, path, body string) *httptest.ResponseRecorder {
	w := httptest.NewRecorder()
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	if body != "" {
		req.Header.Set("Content-Type", "application/json; charset=utf-8")
	}
	h.ServeHTTP(w, req)
	return w
}
func decode[T any](t *testing.T, w *httptest.ResponseRecorder, status int) T {
	t.Helper()
	if w.Code != status {
		t.Fatalf("status %d want %d: %s", w.Code, status, w.Body.String())
	}
	var v T
	if e := json.Unmarshal(w.Body.Bytes(), &v); e != nil {
		t.Fatal(e)
	}
	return v
}
func (r *rig) save(t *testing.T, body string) domain.Session {
	t.Helper()
	return decode[domain.Session](t, request(r.h, "POST", "/api/v1/profiles/"+r.p.ID+"/sessions", body), 201)
}
func TestFullSessionWorkflow(t *testing.T) {
	r := setup(t)
	p := decode[domain.Profile](t, request(r.h, "POST", "/api/v1/profiles", `{"display_name":"Crew"}`), 201)
	if p.ID == "" {
		t.Fatal(p)
	}
	s := r.save(t, testutil.SessionJSON)
	v := decode[domain.Session](t, request(r.h, "GET", "/api/v1/sessions/"+s.ID, ""), 200)
	if *v.Memory.Correct != 3 {
		t.Fatal(v)
	}
	rep := decode[domain.Report](t, request(r.h, "GET", "/api/v1/sessions/"+s.ID+"/report", ""), 200)
	if *rep.Reaction.MedianMS != 250 || rep.MemoryPercent != 75 {
		t.Fatal(rep)
	}
	for _, path := range []string{"/healthz", "/readyz", "/api/v1/profiles/" + r.p.ID, "/api/v1/model/status"} {
		if w := request(r.h, "GET", path, ""); w.Code != 200 {
			t.Fatal(path, w.Code)
		}
	}
}
func TestReplayHTTP(t *testing.T) {
	r := setup(t)
	s := r.save(t, testutil.SessionJSON)
	var payload map[string]any
	json.Unmarshal([]byte(testutil.SessionJSON), &payload)
	b, _ := json.Marshal(payload)
	got := decode[domain.Session](t, request(r.h, "POST", "/api/v1/profiles/"+r.p.ID+"/sessions", string(b)), 200)
	if got.ID != s.ID {
		t.Fatal("new ID on replay")
	}
	body := strings.Replace(testutil.SessionJSON, `"correct":3`, `"correct":2`, 1)
	decode[map[string]any](t, request(r.h, "POST", "/api/v1/profiles/"+r.p.ID+"/sessions", body), 409)
}
func TestValidationResponses(t *testing.T) {
	r := setup(t)
	path := "/api/v1/profiles/" + r.p.ID + "/sessions"
	cases := []struct {
		body   string
		status int
	}{{`{`, 400}, {testutil.SessionJSON + ` {}`, 400}, {strings.Replace(testutil.SessionJSON, `"source":"synthetic"`, `"source":"synthetic","extra":1`, 1), 400}, {strings.Replace(testutil.SessionJSON, `"fatigue":0,`, ``, 1), 422}, {strings.Replace(testutil.SessionJSON, `"fatigue":0`, `"fatigue":null`, 1), 422}, {strings.Replace(testutil.SessionJSON, `"total":4`, `"total":0`, 1), 422}, {strings.Replace(testutil.SessionJSON, `"performed_at":"2026-01-02T12:00:00Z"`, `"performed_at":"yesterday"`, 1), 400}, {strings.Repeat(" ", 256*1024) + testutil.SessionJSON, 413}}
	for i, c := range cases {
		w := request(r.h, "POST", path, c.body)
		if w.Code != c.status {
			t.Errorf("case %d got %d want %d: %s", i, w.Code, c.status, w.Body.String())
		}
	}
	w := httptest.NewRecorder()
	req := httptest.NewRequest("POST", path, strings.NewReader(testutil.SessionJSON))
	req.Header.Set("Content-Type", "text/plain")
	r.h.ServeHTTP(w, req)
	if w.Code != 415 {
		t.Fatal(w.Code)
	}
}
func TestPagination(t *testing.T) {
	r := setup(t)
	for _, path := range []string{"/api/v1/profiles", "/api/v1/profiles/" + r.p.ID + "/sessions"} {
		for _, q := range []string{"?limit=0", "?limit=101", "?offset=-1", "?limit=no", "?limit=1&limit=2"} {
			if w := request(r.h, "GET", path+q, ""); w.Code != 400 {
				t.Fatal(path, q, w.Code)
			}
		}
	}
	v := decode[struct {
		Items []domain.Session `json:"items"`
		Total int              `json:"total"`
	}](t, request(r.h, "GET", "/api/v1/profiles/"+r.p.ID+"/sessions", ""), 200)
	if v.Items == nil || len(v.Items) != 0 || v.Total != 0 {
		t.Fatal(v)
	}
	r.save(t, testutil.SessionJSON)
	v = decode[struct {
		Items []domain.Session `json:"items"`
		Total int              `json:"total"`
	}](t, request(r.h, "GET", "/api/v1/profiles/"+r.p.ID+"/sessions?limit=1&offset=1", ""), 200)
	if len(v.Items) != 0 || v.Total != 1 {
		t.Fatal(v)
	}
}
func TestUnknownResources(t *testing.T) {
	r := setup(t)
	for _, path := range []string{"/api/v1/profiles/00000000000000000000000000000000/sessions", "/api/v1/sessions/00000000000000000000000000000000/report", "/missing"} {
		w := request(r.h, "GET", path, "")
		decode[map[string]any](t, w, 404)
	}
	if w := request(r.h, "GET", "/api/v1/sessions/bad", ""); w.Code != 400 {
		t.Fatal(w.Code)
	}
}
func TestHTMLInjectionEscaped(t *testing.T) {
	r := setup(t)
	s := r.save(t, testutil.SessionJSON)
	w := request(r.h, "GET", "/api/v1/sessions/"+s.ID+"/report.html", "")
	if w.Code != 200 || bytes.Contains(w.Body.Bytes(), []byte("<script>")) || !bytes.Contains(w.Body.Bytes(), []byte("&lt;script&gt;")) || !strings.Contains(w.Body.String(), "75.00") {
		t.Fatal(w.Code, w.Body.String())
	}
}
func TestBackfillInvalidatesExplanation(t *testing.T) {
	r := setup(t)
	s := r.save(t, testutil.SessionJSON)
	path := "/api/v1/sessions/" + s.ID
	decode[map[string]any](t, request(r.h, "POST", path+"/explanation", ""), 200)
	a := decode[domain.Report](t, request(r.h, "GET", path+"/report", ""), 200)
	if a.Explanation == nil {
		t.Fatal("not cached")
	}
	in := testutil.Input()
	in.ClientSessionID = "123e4567-e89b-42d3-a456-426614174001"
	in.PerformedAt = in.PerformedAt.Add(-time.Hour)
	b, _ := json.Marshal(in)
	r.save(t, string(b))
	a = decode[domain.Report](t, request(r.h, "GET", path+"/report", ""), 200)
	if a.BaselineSessionID == nil || a.Explanation != nil {
		t.Fatal("stale explanation served")
	}
}
func TestFailedRegenerationPreservesExplanation(t *testing.T) {
	r := setup(t)
	s := r.save(t, testutil.SessionJSON)
	path := "/api/v1/sessions/" + s.ID
	v := decode[struct {
		Status string `json:"status"`
	}](t, request(r.h, "POST", path+"/explanation", ""), 200)
	if v.Status != "ready" {
		t.Fatal(v)
	}
	r.fail.Store(true)
	v = decode[struct {
		Status string `json:"status"`
	}](t, request(r.h, "POST", path+"/explanation", ""), 200)
	if v.Status != "unavailable" {
		t.Fatal(v)
	}
	a := decode[domain.Report](t, request(r.h, "GET", path+"/report", ""), 200)
	if a.Explanation == nil || a.Explanation.Status != "ready" {
		t.Fatal(a)
	}
}
