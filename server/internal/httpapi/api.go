package httpapi

import (
	"context"
	"errors"
	"net/http"
	"time"

	"github.com/Mickoki/zuma-health/server/internal/domain"
	"github.com/Mickoki/zuma-health/server/internal/model"
	"github.com/Mickoki/zuma-health/server/internal/store"
)

type api struct {
	s *store.Store
	m *model.Client
}

func New(s *store.Store, m *model.Client) http.Handler {
	a := &api{s: s, m: m}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) { send(w, 200, map[string]string{"status": "ok"}) })
	mux.HandleFunc("GET /readyz", func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
		defer cancel()
		if s.Ping(ctx) != nil {
			fail(w, 503, "storage_unavailable", "Storage is not ready.", nil)
			return
		}
		send(w, 200, map[string]string{"status": "ready"})
	})
	mux.HandleFunc("GET /api/v1/model/status", func(w http.ResponseWriter, r *http.Request) { send(w, 200, m.Status(r.Context())) })
	mux.HandleFunc("POST /api/v1/profiles", a.createProfile)
	mux.HandleFunc("GET /api/v1/profiles", a.profiles)
	mux.HandleFunc("GET /api/v1/profiles/{id}", a.profile)
	mux.HandleFunc("POST /api/v1/profiles/{id}/sessions", a.saveSession)
	mux.HandleFunc("GET /api/v1/profiles/{id}/sessions", a.sessions)
	mux.HandleFunc("GET /api/v1/sessions/{id}", a.session)
	mux.HandleFunc("GET /api/v1/sessions/{id}/report", a.reportJSON)
	mux.HandleFunc("GET /api/v1/sessions/{id}/report.html", a.reportHTML)
	mux.HandleFunc("POST /api/v1/sessions/{id}/explanation", a.explain)
	a.registerGames(mux)
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) { fail(w, 404, "not_found", "Endpoint not found.", nil) })
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Cache-Control", "no-store")
		mux.ServeHTTP(w, r)
	})
}
func key(w http.ResponseWriter, r *http.Request) (string, bool) {
	id := r.PathValue("id")
	if !domain.ValidID(id) {
		fail(w, 400, "invalid_id", "Invalid resource identifier.", nil)
		return "", false
	}
	return id, true
}
func storageError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, store.ErrNotFound):
		fail(w, 404, "not_found", "Resource not found.", nil)
	case errors.Is(err, store.ErrConflict):
		fail(w, 409, "session_conflict", "client_session_id already exists with different data.", nil)
	case errors.Is(err, store.ErrInvalid):
		fail(w, 422, "invalid_input", "Input failed validation.", nil)
	default:
		fail(w, 503, "storage_unavailable", "Storage operation failed.", nil)
	}
}
func (a *api) createProfile(w http.ResponseWriter, r *http.Request) {
	var in struct {
		DisplayName string `json:"display_name"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	if !domain.ValidName(in.DisplayName) {
		fail(w, 422, "invalid_input", "Profile name must contain 1–100 characters.", map[string]string{"display_name": "required, 1–100 characters"})
		return
	}
	p, err := a.s.CreateProfile(r.Context(), in.DisplayName)
	if err != nil {
		storageError(w, err)
		return
	}
	send(w, 201, p)
}
func (a *api) profiles(w http.ResponseWriter, r *http.Request) {
	limit, offset, ok := pagination(w, r)
	if !ok {
		return
	}
	items, total, err := a.s.ListProfiles(r.Context(), limit, offset)
	if err != nil {
		storageError(w, err)
		return
	}
	send(w, 200, list(items, limit, offset, total))
}
func (a *api) profile(w http.ResponseWriter, r *http.Request) {
	id, ok := key(w, r)
	if !ok {
		return
	}
	p, err := a.s.GetProfile(r.Context(), id)
	if err != nil {
		storageError(w, err)
		return
	}
	send(w, 200, p)
}
func (a *api) saveSession(w http.ResponseWriter, r *http.Request) {
	id, ok := key(w, r)
	if !ok {
		return
	}
	var in domain.SessionInput
	if !readJSON(w, r, &in) {
		return
	}
	if fields := domain.ValidateSession(in, time.Now()); len(fields) > 0 {
		fail(w, 422, "invalid_input", "Session failed validation.", fields)
		return
	}
	v, created, err := a.s.SaveSession(r.Context(), id, in)
	if err != nil {
		storageError(w, err)
		return
	}
	status := 200
	if created {
		status = 201
	}
	send(w, status, v)
}
func (a *api) sessions(w http.ResponseWriter, r *http.Request) {
	id, ok := key(w, r)
	if !ok {
		return
	}
	limit, offset, ok := pagination(w, r)
	if !ok {
		return
	}
	items, total, err := a.s.ListSessions(r.Context(), id, limit, offset)
	if err != nil {
		storageError(w, err)
		return
	}
	send(w, 200, list(items, limit, offset, total))
}
func (a *api) session(w http.ResponseWriter, r *http.Request) {
	id, ok := key(w, r)
	if !ok {
		return
	}
	v, err := a.s.GetSession(r.Context(), id)
	if err != nil {
		storageError(w, err)
		return
	}
	send(w, 200, v)
}
func (a *api) loadReport(ctx context.Context, id string) (domain.Report, error) {
	s, err := a.s.GetSession(ctx, id)
	if err != nil {
		return domain.Report{}, err
	}
	b, err := a.s.Baseline(ctx, s)
	if err != nil {
		return domain.Report{}, err
	}
	rep := domain.Calculate(s, b)
	rep.Explanation, err = a.s.GetExplanation(ctx, id, domain.Fingerprint(rep))
	return rep, err
}
func (a *api) reportJSON(w http.ResponseWriter, r *http.Request) {
	id, ok := key(w, r)
	if !ok {
		return
	}
	rep, err := a.loadReport(r.Context(), id)
	if err != nil {
		storageError(w, err)
		return
	}
	send(w, 200, rep)
}
func (a *api) explain(w http.ResponseWriter, r *http.Request) {
	id, ok := key(w, r)
	if !ok {
		return
	}
	if r.ContentLength != 0 {
		fail(w, 400, "unexpected_body", "This endpoint accepts no request body.", nil)
		return
	}
	rep, err := a.loadReport(r.Context(), id)
	if err != nil {
		storageError(w, err)
		return
	}
	fingerprint := domain.Fingerprint(rep)
	v, err := a.m.Explain(r.Context(), rep)
	if errors.Is(err, model.ErrBusy) {
		fail(w, 409, "model_busy", "Another explanation is in progress.", nil)
		return
	}
	if err != nil {
		if r.Context().Err() != nil {
			return
		}
		fail(w, 500, "model_error", "Explanation failed.", nil)
		return
	}
	var explanation *domain.Explanation
	reason := ""
	if v.Status == "ready" {
		latest, e := a.loadReport(r.Context(), id)
		if e != nil {
			storageError(w, e)
			return
		}
		if domain.Fingerprint(latest) != fingerprint {
			v.Status = "invalid"
			reason = "report_changed"
		} else {
			if err = a.s.SaveExplanation(r.Context(), id, fingerprint, v); err != nil {
				storageError(w, err)
				return
			}
			explanation = &v
		}
	}
	if reason == "" && v.Status != "ready" {
		reason = "model_" + v.Status
	}
	send(w, 200, struct {
		Status      string              `json:"status"`
		Explanation *domain.Explanation `json:"explanation"`
		Reason      string              `json:"reason,omitempty"`
		Fingerprint string              `json:"report_fingerprint"`
		BaselineID  *string             `json:"baseline_session_id"`
	}{v.Status, explanation, reason, fingerprint, rep.BaselineSessionID})
}
