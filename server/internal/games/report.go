package games

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"github.com/Mickoki/zuma-health/server/internal/domain"
	"sort"
	"time"
)

var labels = map[string]string{
	"duration_ms": "Полная длительность", "moves": "Ходы", "solved": "Поле решено (1 — да)",
	"pairs_found": "Найденные пары", "attempts": "Попытки", "errors": "Ошибки", "accuracy_percent": "Точность", "active_ms": "Время после показа карточек",
	"shown": "Показанные примеры", "correct": "Правильные ответы", "incorrect": "Неправильные ответы", "skipped": "Пропуски", "manual_skips": "Ручные пропуски", "timeouts": "Пропуски по времени", "answered": "Принятые ответы", "mean_answer_ms": "Среднее время ответа", "median_answer_ms": "Медиана времени ответа", "correct_per_minute": "Правильные ответы в минуту",
	"rounds": "Начатые раунды", "successful_rounds": "Успешные раунды", "failed_rounds": "Ошибочные раунды", "max_completed_count": "Максимум успешно запомненных чисел", "mean_preview_ms": "Среднее время просмотра до первого выбора", "mean_selection_ms": "Среднее время выполнения успешного раунда после первого выбора",
}

func Unit(key string) string {
	switch key {
	case "duration_ms", "active_ms", "mean_answer_ms", "median_answer_ms", "mean_preview_ms", "mean_selection_ms":
		return "мс"
	case "accuracy_percent":
		return "%"
	case "correct_per_minute":
		return "ответов/мин"
	default:
		return "шт."
	}
}
func Calculate(r Run, b *Run) (Report, error) {
	metrics, err := Validate(r.Input, time.Now())
	if err != nil {
		return Report{}, err
	}
	p := Report{RunID: r.ID, GameID: r.GameID, RulesVersion: *r.RulesVersion, CalculationVersion: "v1", Difficulty: r.Difficulty, Config: r.Config, Source: r.Source, Survey: r.Survey, Status: r.Status, FinishReason: r.FinishReason, PerformedAt: r.PerformedAt, Metrics: metrics, Units: map[string]string{}, Limitations: []string{"not_medical", "client_timing"}}
	if r.Survey != nil {
		p.Limitations = append(p.Limitations, "survey_timing")
	}
	for key := range metrics {
		p.Units[key] = Unit(key)
	}
	if r.Source == "synthetic" {
		p.Limitations = append(p.Limitations, "synthetic")
	}
	if r.Status == "aborted" {
		p.Limitations = append(p.Limitations, "incomplete")
	}
	key := ComparisonKey(r.Input)
	if b == nil || key == "" || ComparisonKey(b.Input) != key || b.ProfileID != r.ProfileID || !b.PerformedAt.Before(r.PerformedAt) {
		p.Limitations = append(p.Limitations, "no_baseline")
		return p, nil
	}
	old, err := Validate(b.Input, time.Now())
	if err != nil {
		return Report{}, err
	}
	p.BaselineRunID = &b.ID
	p.Deltas = Metrics{}
	for k, n := range metrics {
		if n != nil && old[k] != nil {
			p.Deltas[k] = val(*n - *old[k])
		} else {
			p.Deltas[k] = nil
		}
	}
	return p, nil
}
func Fingerprint(r Report) string {
	r.Explanation = nil
	b, _ := json.Marshal(r)
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:])
}
func Facts(r Report) []domain.Fact {
	facts := []domain.Fact{{ID: "run_outcome", Category: "observations", Text: fmt.Sprintf("Игра %s; сложность %s; исход %s, причина %s.", r.GameID, r.Difficulty, r.Status, r.FinishReason)}}
	if domain.ValidSurvey(r.Survey) {
		facts = append(facts, domain.Fact{ID: "survey", Category: "observations", Text: fmt.Sprintf("Сохранённый опрос: сон %.2f ч; усталость %.2f/10; стресс %.2f/10; настроение %.2f/10 (выше — лучше).", *r.Survey.SleepHours, *r.Survey.Fatigue, *r.Survey.Stress, *r.Survey.Mood)})
	}
	keys := []string{}
	for key := range r.Metrics {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	for _, key := range keys {
		if value := r.Metrics[key]; value != nil {
			facts = append(facts, domain.Fact{ID: key, Category: "observations", Text: fmt.Sprintf("%s: %.2f %s.", labels[key], *value, Unit(key))})
		}
	}
	if r.Deltas != nil {
		for _, key := range keys {
			if value := r.Deltas[key]; value != nil {
				unit := Unit(key)
				if key == "accuracy_percent" {
					unit = "п.п."
				}
				facts = append(facts, domain.Fact{ID: "delta_" + key, Category: "comparisons", Text: fmt.Sprintf("Изменение «%s» относительно предыдущего сопоставимого прохождения: %+.2f %s.", labels[key], *value, unit)})
			}
		}
	}
	texts := map[string]string{"not_medical": "Игровые показатели не являются диагнозом или медицинской консультацией.", "client_timing": "Времена получены от локального клиента; сервер проверяет согласованность событий, а не подлинность измерений.", "survey_timing": "Опрос скопирован из сохранённого черновика; время его заполнения неизвестно и не обязательно совпадает со временем игры.", "synthetic": "Это синтетические демонстрационные данные.", "incomplete": "Прохождение прервано; частичные показатели не сравниваются с завершёнными.", "no_baseline": "Предыдущего сопоставимого прохождения нет; сравнение отсутствует."}
	for _, key := range r.Limitations {
		facts = append(facts, domain.Fact{ID: key, Category: "limitations", Text: texts[key]})
	}
	for _, key := range keys {
		if r.Metrics[key] == nil {
			facts = append(facts, domain.Fact{ID: "missing_" + key, Category: "limitations", Text: fmt.Sprintf("%s не рассчитан: недостаточно подходящих событий.", labels[key])})
		}
	}
	return facts
}
