package httpapi

import (
	"bytes"
	"github.com/Mickoki/zuma-health/server/internal/domain"
	"html/template"
	"net/http"
)

var reportTemplate = template.Must(template.New("report").Funcs(printFunctions).Parse(`<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Zuma — report</title>
<style>` + printStyle + `</style></head>
<body><header><div class="wordmark">ZUMA / MISSION HEALTH</div><h1>Zuma — session report</h1><span class="badge" data-source="{{.Report.Source}}">{{sourceTitle .Report.Source}}</span></header><p>Profile: {{.Name}}</p><p class="meta">Session: {{.Report.SessionID}}<br>Time: {{.Report.PerformedAt}}<br>Source: {{.Report.Source}}<br>Protocol: {{.Report.ProtocolVersion}}; calculations: {{.Report.CalculationVersion}}{{if .Report.BaselineSessionID}}<br>Previous session: {{.Report.BaselineSessionID}}{{end}}</p>
<h2>Results and comparison</h2><table><thead><tr><th>Section</th><th>Metric and change</th></tr></thead><tbody>{{range .Facts}}{{if ne .Category "limitations"}}<tr><td>{{if eq .Category "comparisons"}}Change{{else}}Result{{end}}</td><td>{{.Text}}</td></tr>{{end}}{{end}}</tbody></table>
<h2>Limitations</h2><div class="note"><ul>{{range .Facts}}{{if eq .Category "limitations"}}<li>{{.Text}}</li>{{end}}{{end}}</ul></div>
<h2>Model explanation</h2>{{if .Report.Explanation}}<p>Model {{.Report.Explanation.Model}} selected and ordered verified facts; the server generated the text. This is not medical advice.</p><ul>{{range .Report.Explanation.Observations}}<li>{{.Text}}</li>{{end}}{{range .Report.Explanation.Comparisons}}<li>{{.Text}}</li>{{end}}{{range .Report.Explanation.Limitations}}<li>{{.Text}}</li>{{end}}</ul>{{else}}<p>The explanation was not requested, is unavailable, or is outdated. Numeric results are available independently of the model.</p>{{end}}
<div class="note"><strong>Task results are not a medical diagnosis.</strong><br>Results describe task performance and do not replace medical advice.</div><footer>ZUMA · Legacy reaction and memory protocol · Numeric results are available independently of the model</footer></body></html>`))

func (a *api) reportHTML(w http.ResponseWriter, r *http.Request) {
	id, ok := key(w, r)
	if !ok {
		return
	}
	rep, err := a.loadReport(r.Context(), id)
	if err != nil {
		storageError(w, err)
		return
	}
	s, err := a.s.GetSession(r.Context(), id)
	if err != nil {
		storageError(w, err)
		return
	}
	p, err := a.s.GetProfile(r.Context(), s.ProfileID)
	if err != nil {
		storageError(w, err)
		return
	}
	var b bytes.Buffer
	if err = reportTemplate.Execute(&b, struct {
		Name   string
		Report domain.Report
		Facts  []domain.Fact
	}{p.DisplayName, rep, domain.BuildFacts(rep)}); err != nil {
		fail(w, 500, "report_error", "Could not render report.", nil)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'")
	w.WriteHeader(200)
	w.Write(b.Bytes())
}
