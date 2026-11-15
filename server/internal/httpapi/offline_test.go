package httpapi

import (
	"context"
	"github.com/Mickoki/zuma-health/server/internal/domain"
	"github.com/Mickoki/zuma-health/server/internal/model"
	"github.com/Mickoki/zuma-health/server/internal/store"
	"github.com/Mickoki/zuma-health/server/internal/testutil"
	"net/http/httptest"
	"path/filepath"
	"testing"
	"time"
)

func TestWorkflowWithExternalNetworkDenied(t *testing.T) {
	// The actual model transport permits loopback only and ignores proxy settings.
	// Prove external base URLs cannot enter the runtime, then exercise all core APIs
	// with an unavailable loopback endpoint. No external service is involved.
	for _, url := range []string{"http://example.com:11434", "http://192.0.2.1:11434"} {
		if _, e := model.NewClient(url, "qwen3:8b", time.Second); e == nil {
			t.Fatal("external model address accepted")
		}
	}
	t.Setenv("HTTP_PROXY", "http://192.0.2.1:9")
	t.Setenv("HTTPS_PROXY", "http://192.0.2.1:9")
	closed := httptest.NewServer(nil)
	endpoint := closed.URL
	closed.Close()
	m, e := model.NewClient(endpoint, "qwen3:8b", 100*time.Millisecond)
	if e != nil {
		t.Fatal(e)
	}
	path := filepath.Join(t.TempDir(), "offline.db")
	s, e := store.Open(path)
	if e != nil {
		t.Fatal(e)
	}
	defer func() { s.Close() }()
	h := New(s, m)
	p := decode[domain.Profile](t, request(h, "POST", "/api/v1/profiles", `{"display_name":"Offline demo"}`), 201)
	v := decode[domain.Session](t, request(h, "POST", "/api/v1/profiles/"+p.ID+"/sessions", testutil.SessionJSON), 201)
	decode[domain.Session](t, request(h, "POST", "/api/v1/profiles/"+p.ID+"/sessions", testutil.SessionJSON), 200)
	rep := decode[domain.Report](t, request(h, "GET", "/api/v1/sessions/"+v.ID+"/report", ""), 200)
	if rep.Source != "synthetic" || rep.MemoryPercent != 75 {
		t.Fatal(rep)
	}
	outcome := decode[struct {
		Status string `json:"status"`
	}](t, request(h, "POST", "/api/v1/sessions/"+v.ID+"/explanation", ""), 200)
	if outcome.Status != "unavailable" {
		t.Fatal(outcome)
	}
	if w := request(h, "GET", "/api/v1/sessions/"+v.ID+"/report.html", ""); w.Code != 200 {
		t.Fatal(w.Code)
	}
	if e = s.Close(); e != nil {
		t.Fatal(e)
	}
	s, e = store.Open(path)
	if e != nil {
		t.Fatal(e)
	}
	items, total, e := s.ListSessions(context.Background(), p.ID, 20, 0)
	if e != nil || total != 1 || len(items) != 1 || items[0].ID != v.ID {
		t.Fatal(total, e)
	}
}
