package domain

import "fmt"

func BuildFacts(r Report) []Fact {
	facts := []Fact{}
	add := func(id, category, text string) { facts = append(facts, Fact{ID: id, Category: category, Text: text}) }
	add("reaction_counts", "observations", fmt.Sprintf("Реакция: корректных попыток — %d, преждевременных — %d, пропусков — %d.", r.Reaction.Valid, r.Reaction.Premature, r.Reaction.Missed))
	if r.Reaction.MedianMS != nil {
		add("reaction_median", "observations", fmt.Sprintf("Медиана времени реакции: %.2f мс.", *r.Reaction.MedianMS))
		add("reaction_mean", "observations", fmt.Sprintf("Среднее время реакции: %.2f мс.", *r.Reaction.MeanMS))
	}
	add("memory_accuracy", "observations", fmt.Sprintf("Доля правильных ответов в задании на память: %.2f%%.", r.MemoryPercent))
	add("survey", "observations", fmt.Sprintf("Самооценка: сон %.2f ч; усталость %.2f/10; стресс %.2f/10; настроение %.2f/10 (выше — лучше).", *r.Survey.SleepHours, *r.Survey.Fatigue, *r.Survey.Stress, *r.Survey.Mood))
	if r.Comparison != nil {
		c := r.Comparison
		add("memory_change", "comparisons", fmt.Sprintf("Изменение доли правильных ответов относительно предыдущей сопоставимой сессии: %+.2f процентных пункта.", c.MemoryDeltaPP))
		if c.ReactionDeltaMS != nil {
			add("reaction_change", "comparisons", fmt.Sprintf("Изменение медианы времени реакции: %+.2f мс (%+.2f%%).", *c.ReactionDeltaMS, *c.ReactionDeltaPercent))
		}
		add("survey_change", "comparisons", fmt.Sprintf("Изменение самооценки: сон %+.2f ч, усталость %+.2f, стресс %+.2f, настроение %+.2f.", *c.SurveyDelta.SleepHours, *c.SurveyDelta.Fatigue, *c.SurveyDelta.Stress, *c.SurveyDelta.Mood))
	}
	texts := map[string]string{"not_medical": "Результаты заданий и продуктового опроса не являются диагнозом или медицинской консультацией.", "synthetic": "Сессия содержит синтетические демонстрационные данные.", "no_valid_reaction": "Корректных попыток реакции нет; среднее и медиана не рассчитаны.", "no_baseline": "Предыдущей сопоставимой сессии нет; сравнение не рассчитано."}
	for _, id := range r.Limitations {
		add(id, "limitations", texts[id])
	}
	if r.Comparison != nil && r.Comparison.ReactionDeltaMS == nil {
		add("reaction_comparison_unavailable", "limitations", "Сравнение времени реакции недоступно: в одной из сессий нет корректных попыток.")
	}
	return facts
}
