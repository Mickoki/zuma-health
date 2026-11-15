package httpapi

import (
	"encoding/json"
	stdhtml "html"
	"strings"
	"testing"

	"github.com/Mickoki/zuma-health/server/internal/games"
	"github.com/Mickoki/zuma-health/server/internal/testutil"
)

func TestPrintGameDesign(t *testing.T) {
	r := gameRig(t)
	body, _ := json.Marshal(testutil.GameInput("math"))
	run := decode[games.Run](t, request(r.h, "POST", "/api/v1/profiles/"+r.p.ID+"/game-runs", string(body)), 201)
	html := request(r.h, "GET", "/api/v1/game-runs/"+run.ID+"/report.html", "")
	for _, required := range []string{"@page", "A4", "<table", "<th", "Динамика", "Показатели заданий не являются медицинским диагнозом.", "Математика", "Синтетические данные"} {
		if !strings.Contains(html.Body.String(), required) {
			t.Errorf("missing print element %q", required)
		}
	}
	if strings.Contains(html.Body.String(), "<script") || strings.Contains(html.Body.String(), "https://fonts") {
		t.Fatal("print report must work offline without scripts")
	}
}

func TestPrintAccuracyDeltaUnit(t *testing.T) {
	value := 25.0
	var html strings.Builder
	err := gameTemplate.Execute(&html, struct {
		Name   string
		Report games.Report
		Facts  []any
	}{Name: "Synthetic", Report: games.Report{GameID: "math", Metrics: games.Metrics{"accuracy_percent": &value}, Units: map[string]string{"accuracy_percent": "%"}, Deltas: games.Metrics{"accuracy_percent": &value}}})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(stdhtml.UnescapeString(html.String()), "+25.00 п.п.") {
		t.Fatal("accuracy delta must be labeled in percentage points")
	}
}
