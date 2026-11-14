package httpapi

import (
	"bytes"
	"github.com/Mickoki/zuma-health/server/internal/domain"
	"html/template"
	"net/http"
)

var reportTemplate = template.Must(template.New("report").Parse(`<!doctype html>
<html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Zuma — отчёт</title>
<style>body{font:16px/1.5 system-ui,sans-serif;max-width:860px;margin:40px auto;padding:0 20px;color:#172638}h1,h2{color:#16395b}.meta{color:#465971;overflow-wrap:anywhere}li{margin:8px 0}.note{padding:16px;background:#eef3f7;border-left:4px solid #56728f}@media print{body{margin:0;max-width:none}.note{background:none}}</style></head>
<body><h1>Zuma — отчёт сессии</h1><p>Профиль: {{.Name}}</p><p class="meta">Сессия: {{.Report.SessionID}}<br>Время: {{.Report.PerformedAt}}<br>Источник: {{.Report.Source}}<br>Протокол: {{.Report.ProtocolVersion}}; расчёты: {{.Report.CalculationVersion}}{{if .Report.BaselineSessionID}}<br>Предыдущая сессия: {{.Report.BaselineSessionID}}{{end}}</p>
<h2>Результаты и сравнение</h2><ul>{{range .Facts}}{{if ne .Category "limitations"}}<li>{{.Text}}</li>{{end}}{{end}}</ul>
<h2>Ограничения</h2><div class="note"><ul>{{range .Facts}}{{if eq .Category "limitations"}}<li>{{.Text}}</li>{{end}}{{end}}</ul></div>
<h2>Объяснение модели</h2>{{if .Report.Explanation}}<p>Модель {{.Report.Explanation.Model}} выбрала и упорядочила проверенные факты; текст сформирован сервером. Это не медицинская консультация.</p><ul>{{range .Report.Explanation.Observations}}<li>{{.Text}}</li>{{end}}{{range .Report.Explanation.Comparisons}}<li>{{.Text}}</li>{{end}}{{range .Report.Explanation.Limitations}}<li>{{.Text}}</li>{{end}}</ul>{{else}}<p>Объяснение не запрошено, недоступно или устарело. Числовые результаты доступны независимо от модели.</p>{{end}}
</body></html>`))

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
