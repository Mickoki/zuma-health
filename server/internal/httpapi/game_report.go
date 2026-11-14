package httpapi

import (
	"bytes"
	"github.com/Mickoki/zuma-health/server/internal/domain"
	"github.com/Mickoki/zuma-health/server/internal/games"
	"html/template"
	"net/http"
)

var gameTemplate = template.Must(template.New("game").Parse(`<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Zuma — игровое прохождение</title><style>body{font:16px/1.5 system-ui;max-width:900px;margin:40px auto;padding:0 20px;color:#172638}li{margin:8px 0}.meta{overflow-wrap:anywhere;color:#506079}@media print{body{margin:0}}</style></head><body>
<h1>Zuma — отчёт игры {{.Report.GameID}}</h1><p>Профиль: {{.Name}}</p><p class="meta">Прохождение: {{.Report.RunID}}<br>Начало: {{.Report.PerformedAt}}<br>Сложность: {{.Report.Difficulty}}; правила: {{.Report.RulesVersion}}; расчёты: {{.Report.CalculationVersion}}<br>Конфигурация: {{.Report.Config}}<br>Источник: {{.Report.Source}}<br>Исход: {{.Report.Status}} / {{.Report.FinishReason}}{{if .Report.BaselineRunID}}<br>Предыдущее сопоставимое прохождение: {{.Report.BaselineRunID}}{{end}}</p>
<h2>Сохранённый опрос</h2>{{if .Report.Survey}}<p>Сон: {{.Report.Survey.SleepHours}} ч; усталость: {{.Report.Survey.Fatigue}}/10; стресс: {{.Report.Survey.Stress}}/10; настроение: {{.Report.Survey.Mood}}/10.</p><p>Это копия сохранённого опроса, выбранная при запуске игры; время заполнения не записано.</p>{{else}}<p>Опрос к этому прохождению не привязан.</p>{{end}}
<h2>Показатели и сравнение</h2><ul>{{range .Facts}}{{if and (ne .Category "limitations") (ne .ID "survey")}}<li>{{.Text}}</li>{{end}}{{end}}</ul><h2>Ограничения</h2><ul>{{range .Facts}}{{if eq .Category "limitations"}}<li>{{.Text}}</li>{{end}}{{end}}</ul>
<h2>Что можно сделать дальше</h2><p>Проверьте, актуален ли опрос, и посмотрите историю сопоставимых прохождений. При беспокоящих симптомах или вопросах следуйте протоколу миссии и свяжитесь с медицинским специалистом. Игровые показатели не задают пороги для лечения.</p>
<h2>Объяснение модели</h2>{{if .Report.Explanation}}<p>{{.Report.Explanation.Model}} выбрала проверенные факты; текст сформировал Go.</p><ul>{{range .Report.Explanation.Observations}}<li>{{.Text}}</li>{{end}}{{range .Report.Explanation.Comparisons}}<li>{{.Text}}</li>{{end}}{{range .Report.Explanation.Limitations}}<li>{{.Text}}</li>{{end}}</ul>{{else}}<p>Объяснение не запрошено, недоступно или устарело. Показатели доступны независимо от модели.</p>{{end}}</body></html>`))

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
