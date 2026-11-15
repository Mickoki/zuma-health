package httpapi

import (
	"bytes"
	"github.com/Mickoki/zuma-health/server/internal/domain"
	"github.com/Mickoki/zuma-health/server/internal/games"
	"html/template"
	"net/http"
)

var gameTemplate = template.Must(template.New("game").Funcs(printFunctions).Parse(`<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Zuma — игровое прохождение</title><style>` + printStyle + `</style></head><body>
<header><div class="wordmark">ZUMA / MISSION HEALTH</div><h1>{{gameTitle .Report.GameID}} — отчёт прохождения</h1><span class="badge" data-source="{{.Report.Source}}">{{sourceTitle .Report.Source}}</span></header><p>Профиль: {{.Name}}</p><p class="meta">Прохождение: {{.Report.RunID}}<br>Начало: {{.Report.PerformedAt}}<br>Сложность: {{difficultyTitle .Report.Difficulty}}; правила: {{.Report.RulesVersion}}; расчёты: {{.Report.CalculationVersion}}<br>Исход: {{outcomeTitle .Report.FinishReason}}{{if .Report.BaselineRunID}}<br>Предыдущее сопоставимое прохождение: {{.Report.BaselineRunID}}{{end}}</p>
<h2>Сохранённый опрос</h2>{{if .Report.Survey}}<p>Сон: {{.Report.Survey.SleepHours}} ч; усталость: {{.Report.Survey.Fatigue}}/10; стресс: {{.Report.Survey.Stress}}/10; настроение: {{.Report.Survey.Mood}}/10.</p><p>Это копия сохранённого опроса, выбранная при запуске игры; время заполнения не записано.</p>{{else}}<p>Опрос к этому прохождению не привязан.</p>{{end}}
<h2>Показатели и сравнение</h2><p class="meta">Динамика рассчитана относительно предыдущего сопоставимого прохождения. Прочерк означает, что сравнение или показатель недоступен.</p><table><thead><tr><th>Показатель</th><th>Значение</th><th>Единица</th><th>Динамика</th></tr></thead><tbody>{{range $key, $value := .Report.Metrics}}<tr><td>{{metricTitle $key}}</td><td class="value">{{number $value}}</td><td>{{index $.Report.Units $key}}</td><td class="value">{{delta (index $.Report.Deltas $key)}}{{if ne (index $.Report.Deltas $key) nil}} {{deltaUnit $key (index $.Report.Units $key)}}{{end}}</td></tr>{{end}}</tbody></table><h2>Ограничения</h2><ul>{{range .Facts}}{{if eq .Category "limitations"}}<li>{{.Text}}</li>{{end}}{{end}}</ul>
<h2>Что можно сделать дальше</h2><p>Проверьте, актуален ли опрос, и посмотрите историю сопоставимых прохождений. При беспокоящих симптомах или вопросах следуйте протоколу миссии и свяжитесь с медицинским специалистом. Игровые показатели не задают пороги для лечения.</p>
<h2>Объяснение модели</h2>{{if .Report.Explanation}}<p>{{.Report.Explanation.Model}} выбрала проверенные факты; текст сформировал Go.</p><ul>{{range .Report.Explanation.Observations}}<li>{{.Text}}</li>{{end}}{{range .Report.Explanation.Comparisons}}<li>{{.Text}}</li>{{end}}{{range .Report.Explanation.Limitations}}<li>{{.Text}}</li>{{end}}</ul>{{else}}<p>Объяснение не запрошено, недоступно или устарело. Показатели доступны независимо от модели.</p>{{end}}<div class="note"><strong>Показатели заданий не являются медицинским диагнозом.</strong><br>Результаты описывают выполнение задания и не заменяют медицинскую консультацию.</div><footer>ZUMA · Расчёты выполнены сервером · В этом отчёте только текущее игровое прохождение; другие задания доступны в их отдельных отчётах.</footer></body></html>`))

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
