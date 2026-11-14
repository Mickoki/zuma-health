package httpapi

import (
	"context"
	"errors"
	"github.com/Mickoki/zuma-health/server/internal/domain"
	"github.com/Mickoki/zuma-health/server/internal/games"
	"github.com/Mickoki/zuma-health/server/internal/model"
	"net/http"
	"time"
)

func (a *api) registerGames(m *http.ServeMux) {
	m.HandleFunc("POST /api/v1/profiles/{id}/game-runs", a.saveGame)
	m.HandleFunc("GET /api/v1/profiles/{id}/game-runs", a.listGames)
	m.HandleFunc("GET /api/v1/game-runs/{id}", a.getGame)
	m.HandleFunc("GET /api/v1/game-runs/{id}/report", a.gameReport)
	m.HandleFunc("GET /api/v1/game-runs/{id}/report.html", a.gameHTML)
	m.HandleFunc("POST /api/v1/game-runs/{id}/explanation", a.gameExplanation)
}
func (a *api) saveGame(w http.ResponseWriter, r *http.Request) {
	id, ok := key(w, r)
	if !ok {
		return
	}
	var in games.Input
	if !readJSONLimit(w, r, &in, 1<<20) {
		return
	}
	if _, err := games.Validate(in, time.Now()); err != nil {
		fail(w, 422, "invalid_game_run", "Game replay failed validation.", map[string]string{"run": err.Error()})
		return
	}
	v, created, err := a.s.SaveGameRun(r.Context(), id, in)
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
func (a *api) listGames(w http.ResponseWriter, r *http.Request) {
	id, ok := key(w, r)
	if !ok {
		return
	}
	limit, offset, ok := pagination(w, r)
	if !ok {
		return
	}
	filter := r.URL.Query()["game_id"]
	if len(filter) > 1 {
		fail(w, 400, "invalid_query", "game_id must occur once.", nil)
		return
	}
	game := ""
	if len(filter) == 1 {
		game = filter[0]
		if _, err := games.Defaults(game, "easy"); err != nil {
			fail(w, 400, "invalid_query", "Unknown game_id.", nil)
			return
		}
	}
	items, total, err := a.s.ListGameRuns(r.Context(), id, game, limit, offset)
	if err != nil {
		storageError(w, err)
		return
	}
	send(w, 200, list(items, limit, offset, total))
}
func (a *api) getGame(w http.ResponseWriter, r *http.Request) {
	id, ok := key(w, r)
	if !ok {
		return
	}
	v, err := a.s.GetGameRun(r.Context(), id)
	if err != nil {
		storageError(w, err)
		return
	}
	send(w, 200, v)
}
func (a *api) loadGameReport(ctx context.Context, id string) (games.Report, error) {
	v, err := a.s.GetGameRun(ctx, id)
	if err != nil {
		return games.Report{}, err
	}
	b, err := a.s.BaselineGameRun(ctx, v)
	if err != nil {
		return games.Report{}, err
	}
	rep, err := games.Calculate(v, b)
	if err != nil {
		return rep, err
	}
	rep.Explanation, err = a.s.GetGameExplanation(ctx, id, games.Fingerprint(rep))
	return rep, err
}
func (a *api) gameReport(w http.ResponseWriter, r *http.Request) {
	id, ok := key(w, r)
	if !ok {
		return
	}
	v, err := a.loadGameReport(r.Context(), id)
	if err != nil {
		storageError(w, err)
		return
	}
	send(w, 200, v)
}
func (a *api) gameExplanation(w http.ResponseWriter, r *http.Request) {
	id, ok := key(w, r)
	if !ok {
		return
	}
	if r.ContentLength != 0 {
		fail(w, 400, "unexpected_body", "This endpoint accepts no body.", nil)
		return
	}
	rep, err := a.loadGameReport(r.Context(), id)
	if err != nil {
		storageError(w, err)
		return
	}
	fp := games.Fingerprint(rep)
	v, err := a.m.ExplainFacts(r.Context(), games.Facts(rep))
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
	reason := ""
	var explanation *domain.Explanation
	if v.Status == "ready" {
		latest, e := a.loadGameReport(r.Context(), id)
		if e != nil {
			storageError(w, e)
			return
		}
		if games.Fingerprint(latest) != fp {
			v.Status = "invalid"
			reason = "report_changed"
		} else {
			if e = a.s.SaveGameExplanation(r.Context(), id, fp, v); e != nil {
				storageError(w, e)
				return
			}
			explanation = &v
		}
	}
	if reason == "" && v.Status != "ready" {
		reason = "model_" + v.Status
	}
	send(w, 200, struct {
		Status        string              `json:"status"`
		Explanation   *domain.Explanation `json:"explanation"`
		Reason        string              `json:"reason,omitempty"`
		Fingerprint   string              `json:"report_fingerprint"`
		BaselineRunID *string             `json:"baseline_run_id"`
	}{v.Status, explanation, reason, fp, rep.BaselineRunID})
}
