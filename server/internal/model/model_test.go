package model

import (
	"context"
	"encoding/json"
	"errors"
	"github.com/Mickoki/zuma-health/server/internal/domain"
	"github.com/Mickoki/zuma-health/server/internal/testutil"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func report() domain.Report {
	return domain.Calculate(domain.Session{ID: "session", ProfileID: "profile", SessionInput: testutil.Input()}, nil)
}
func fake(t *testing.T, content string) (*Client, func()) {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/chat" {
			t.Error(r.URL.Path)
		}
		var req map[string]any
		json.NewDecoder(r.Body).Decode(&req)
		if req["stream"] != false || req["think"] != false || req["model"] != "qwen3:8b" {
			t.Error("wrong Ollama request")
		}
		json.NewEncoder(w).Encode(map[string]any{"model": "qwen3:8b", "created_at": "2026-01-01T00:00:00Z", "done": true, "message": map[string]string{"role": "assistant", "content": content}})
	}))
	c, e := NewClient(srv.URL, "qwen3:8b", time.Second)
	if e != nil {
		t.Fatal(e)
	}
	return c, srv.Close
}

const valid = `{"observations":["reaction_median"],"comparisons":[],"limitations":[]}`

func TestValidFactSelection(t *testing.T) {
	c, close := fake(t, valid)
	defer close()
	v, e := c.Explain(context.Background(), report())
	if e != nil || v.Status != "ready" || len(v.Observations) != 1 || !strings.Contains(v.Observations[0].Text, "250.00") {
		t.Fatalf("%+v %v", v, e)
	}
}
func TestMandatoryLimitations(t *testing.T) {
	c, close := fake(t, valid)
	defer close()
	v, _ := c.Explain(context.Background(), report())
	if len(v.Limitations) != 3 {
		t.Fatalf("missing mandatory limitations: %+v", v)
	}
}
func invalid(t *testing.T, content string) {
	t.Helper()
	c, close := fake(t, content)
	defer close()
	v, e := c.Explain(context.Background(), report())
	if e != nil || v.Status != "invalid" {
		t.Fatalf("%+v %v", v, e)
	}
}
func TestUnknownFactRejected(t *testing.T) {
	invalid(t, `{"observations":["diagnosis"],"comparisons":[],"limitations":[]}`)
}
func TestCrossCategoryRejected(t *testing.T) {
	invalid(t, `{"observations":["synthetic"],"comparisons":[],"limitations":[]}`)
}
func TestExtraFieldsRejected(t *testing.T) {
	invalid(t, `{"observations":["reaction_median"],"comparisons":[],"limitations":[],"summary":"fake"}`)
}
func TestMalformedSelectionRejected(t *testing.T) {
	for _, s := range []string{`broken`, `{}`, `{"observations":null,"comparisons":[],"limitations":[]}`, `{"observations":["reaction_median","reaction_median"],"comparisons":[],"limitations":[]}`, valid + ` {}`} {
		t.Run(s, func(t *testing.T) { invalid(t, s) })
	}
}
func TestOversizedResponse(t *testing.T) { invalid(t, strings.Repeat("x", 150000)) }
func TestUnavailable(t *testing.T) {
	srv := httptest.NewServer(http.NotFoundHandler())
	url := srv.URL
	srv.Close()
	c, _ := NewClient(url, "qwen3:8b", time.Second)
	v, e := c.Explain(context.Background(), report())
	if e != nil || v.Status != "unavailable" {
		t.Fatal(v, e)
	}
}
func TestTimeoutReleasesSlot(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { io.Copy(io.Discard, r.Body); <-r.Context().Done() }))
	defer srv.Close()
	c, _ := NewClient(srv.URL, "qwen3:8b", 20*time.Millisecond)
	for i := 0; i < 2; i++ {
		v, e := c.Explain(context.Background(), report())
		if e != nil || v.Status != "unavailable" {
			t.Fatal(v, e)
		}
	}
}
func TestCancellation(t *testing.T) {
	c, close := fake(t, valid)
	defer close()
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	_, e := c.Explain(ctx, report())
	if !errors.Is(e, context.Canceled) {
		t.Fatal(e)
	}
	v, e := c.Explain(context.Background(), report())
	if e != nil || v.Status != "ready" {
		t.Fatal(v, e)
	}
}
func TestBusy(t *testing.T) {
	entered := make(chan struct{})
	release := make(chan struct{})
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { close(entered); <-release; http.Error(w, "offline", 503) }))
	defer srv.Close()
	c, _ := NewClient(srv.URL, "qwen3:8b", time.Second)
	done := make(chan struct{})
	go func() { defer close(done); c.Explain(context.Background(), report()) }()
	<-entered
	_, e := c.Explain(context.Background(), report())
	close(release)
	<-done
	if !errors.Is(e, ErrBusy) {
		t.Fatal(e)
	}
}
func TestStatus(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/api/version" {
			io.WriteString(w, `{"version":"test"}`)
		} else {
			io.WriteString(w, `{"models":[{"name":"qwen3:8b"}]}`)
		}
	}))
	defer srv.Close()
	c, _ := NewClient(srv.URL, "qwen3:8b", time.Second)
	s := c.Status(context.Background())
	if !s.Available || !s.ModelInstalled {
		t.Fatal(s)
	}
}
