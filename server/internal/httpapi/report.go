package httpapi

import (
	"bytes"
	"github.com/Mickoki/zuma-health/server/internal/domain"
	"html/template"
	"net/http"
)

var reportTemplate = template.Must(template.New("report").Funcs(printFunctions).Parse(`<!doctype html>
<html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Zuma — отчёт</title>
<style>` + printStyle + `</style></head>
<body><header><div class="wordmark">ZUMA / MISSION HEALTH</div><h1>Zuma — отчёт сессии</h1><span class="badge" data-source="{{.Report.Source}}">{{sourceTitle .Report.Source}}</span></header><p>Профиль: {{.Name}}</p><p class="meta">Сессия: {{.Report.SessionID}}<br>Время: {{.Report.PerformedAt}}<br>Источник: {{.Report.Source}}<br>Протокол: {{.Report.ProtocolVersion}}; расчёты: {{.Report.CalculationVersion}}{{if .Report.BaselineSessionID}}<br>Предыдущая сессия: {{.Report.BaselineSessionID}}{{end}}</p>
<h2>Результаты и сравнение</h2><table><thead><tr><th>Раздел</th><th>Показатель и динамика</th></tr></thead><tbody>{{range .Facts}}{{if ne .Category "limitations"}}<tr><td>{{if eq .Category "comparisons"}}Динамика{{else}}Результат{{end}}</td><td>{{.Text}}</td></tr>{{end}}{{end}}</tbody></table>
<h2>Ограничения</h2><div class="note"><ul>{{range .Facts}}{{if eq .Category "limitations"}}<li>{{.Text}}</li>{{end}}{{end}}</ul></div>
<h2>Объяснение модели</h2>{{if .Report.Explanation}}<p>Модель {{.Report.Explanation.Model}} выбрала и упорядочила проверенные факты; текст сформирован сервером. Это не медицинская консультация.</p><ul>{{range .Report.Explanation.Observations}}<li>{{.Text}}</li>{{end}}{{range .Report.Explanation.Comparisons}}<li>{{.Text}}</li>{{end}}{{range .Report.Explanation.Limitations}}<li>{{.Text}}</li>{{end}}</ul>{{else}}<p>Объяснение не запрошено, недоступно или устарело. Числовые результаты доступны независимо от модели.</p>{{end}}
<div class="note"><strong>Показатели заданий не являются медицинским диагнозом.</strong><br>Результаты описывают выполнение заданий и не заменяют медицинскую консультацию.</div><footer>ZUMA · Прежний протокол реакции и памяти · Числовые результаты доступны независимо от модели</footer></body></html>`))

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
