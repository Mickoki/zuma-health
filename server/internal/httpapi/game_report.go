package httpapi

import (
	"bytes"
	"github.com/Mickoki/zuma-health/server/internal/domain"
	"github.com/Mickoki/zuma-health/server/internal/games"
	"html/template"
	"net/http"
)

var gameTemplate = template.Must(template.New("game").Funcs(printFunctions).Parse(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Zuma — game run</title><style>` + printStyle + `</style></head><body>
<header><div class="wordmark">ZUMA / MISSION HEALTH</div><h1>{{gameTitle .Report.GameID}} — run report</h1><span class="badge" data-source="{{.Report.Source}}">{{sourceTitle .Report.Source}}</span></header><p>Profile: {{.Name}}</p><p class="meta">Run: {{.Report.RunID}}<br>Started: {{.Report.PerformedAt}}<br>Difficulty: {{difficultyTitle .Report.Difficulty}}; rules: {{.Report.RulesVersion}}; calculations: {{.Report.CalculationVersion}}<br>Outcome: {{outcomeTitle .Report.FinishReason}}{{if .Report.BaselineRunID}}<br>Previous comparable run: {{.Report.BaselineRunID}}{{end}}</p>
<h2>Saved survey</h2>{{if .Report.Survey}}<p>Sleep: {{.Report.Survey.SleepHours}} h; fatigue: {{.Report.Survey.Fatigue}}/10; stress: {{.Report.Survey.Stress}}/10; mood: {{.Report.Survey.Mood}}/10.</p><p>This is a copy of the saved survey selected when starting the game; its completion time was not recorded.</p>{{else}}<p>No survey is linked to this run.</p>{{end}}
<h2>Metrics and comparison</h2><p class="meta">Changes are calculated relative to the previous comparable run. A dash means a metric or comparison is unavailable.</p><table><thead><tr><th>Metric</th><th>Value</th><th>Unit</th><th>Change</th></tr></thead><tbody>{{range $key, $value := .Report.Metrics}}<tr><td>{{metricTitle $key}}</td><td class="value">{{number $value}}</td><td>{{index $.Report.Units $key}}</td><td class="value">{{delta (index $.Report.Deltas $key)}}{{if ne (index $.Report.Deltas $key) nil}} {{deltaUnit $key (index $.Report.Units $key)}}{{end}}</td></tr>{{end}}</tbody></table><h2>Limitations</h2><ul>{{range .Facts}}{{if eq .Category "limitations"}}<li>{{.Text}}</li>{{end}}{{end}}</ul>
<h2>Next steps</h2><p>Check that the survey is up to date and review the history of comparable runs. If you have concerning symptoms or questions, follow the mission protocol and contact a medical professional. Game metrics do not set treatment thresholds.</p>
<h2>Model explanation</h2>{{if .Report.Explanation}}<p>{{.Report.Explanation.Model}} selected verified facts; Go generated the text.</p><ul>{{range .Report.Explanation.Observations}}<li>{{.Text}}</li>{{end}}{{range .Report.Explanation.Comparisons}}<li>{{.Text}}</li>{{end}}{{range .Report.Explanation.Limitations}}<li>{{.Text}}</li>{{end}}</ul>{{else}}<p>The explanation was not requested, is unavailable, or is outdated. Metrics are available independently of the model.</p>{{end}}<div class="note"><strong>Task results are not a medical diagnosis.</strong><br>Results describe task performance and do not replace medical advice.</div><footer>ZUMA · Calculated by the server · This report covers only the current game run; other tasks have separate reports.</footer></body></html>`))

func (a *api) gameHTML(w http.ResponseWriter, r *http.Request) {
	id, ok := key(w, r)
	if !ok {
		return
	}
	rep, err := a.loadGameReport(r.Context(), id)
	if err != nil {
		storageError(w, err)
		return
	}
	run, err := a.s.GetGameRun(r.Context(), id)
	if err != nil {
		storageError(w, err)
		return
	}
	p, err := a.s.GetProfile(r.Context(), run.ProfileID)
	if err != nil {
		storageError(w, err)
		return
	}
	var body bytes.Buffer
	if err = gameTemplate.Execute(&body, struct {
		Name   string
		Report games.Report
		Facts  []domain.Fact
	}{p.DisplayName, rep, games.Facts(rep)}); err != nil {
		fail(w, 500, "report_error", "Could not render report.", nil)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'")
	w.Write(body.Bytes())
}
