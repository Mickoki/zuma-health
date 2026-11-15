package httpapi

import (
	_ "embed"
	"fmt"
	"html/template"
	"strings"
)

//go:embed print_style.css
var printStyle string

var printFunctions = template.FuncMap{
	"deltaUnit": func(key, unit string) string {
		if key == "accuracy_percent" {
			return "п.п."
		}
		return unit
	},
	"gameTitle": func(id string) string {
		return map[string]string{"fifteen": "Пятнашки", "pairs": "Найди пару", "math": "Математика на скорость", "chimp": "Запомни числа"}[id]
	},
	"sourceTitle": func(source string) string {
		if source == "synthetic" {
			return "Синтетические данные"
		}
		return "Локальное прохождение"
	},
	"difficultyTitle": func(level string) string {
		return map[string]string{"easy": "Легко", "normal": "Обычно", "hard": "Сложно"}[level]
	},
	"outcomeTitle": func(reason string) string {
		return map[string]string{"solved": "Задача решена", "questions_done": "Все примеры пройдены", "time_limit": "Время вышло", "target_reached": "Целевой уровень достигнут", "mistake_limit": "Лимит ошибок", "focus_lost": "Окно потеряло фокус", "user_exit": "Выход из игры", "host_removed": "Модуль закрыт", "recording_limit": "Достигнут предел записи"}[reason]
	},
	"metricTitle": func(key string) string {
		titles := map[string]string{
			"duration_ms": "Длительность", "moves": "Ходы", "solved": "Поле решено (1 — да)",
			"pairs_found": "Найденные пары", "attempts": "Попытки", "errors": "Ошибки", "accuracy_percent": "Точность",
			"active_ms": "Время поиска пар", "shown": "Показанные примеры", "correct": "Правильные ответы",
			"incorrect": "Неправильные ответы", "skipped": "Пропуски", "manual_skips": "Ручные пропуски",
			"timeouts": "Истечения времени", "answered": "Принятые ответы", "mean_answer_ms": "Среднее время ответа",
			"successful_rounds": "Успешные раунды", "max_completed_count": "Максимум пройденных чисел",
			"median_answer_ms": "Медиана времени ответа", "correct_per_minute": "Правильные ответы в минуту",
			"rounds": "Начатые раунды", "failed_rounds": "Ошибочные раунды",
			"mean_preview_ms":   "Среднее время просмотра до первого выбора",
			"mean_selection_ms": "Среднее время выполнения успешного раунда после первого выбора",
		}
		if title, ok := titles[key]; ok {
			return title
		}
		return strings.ReplaceAll(key, "_", " ")
	},
	"number": func(value *float64) string {
		if value == nil {
			return "—"
		}
		return fmt.Sprintf("%.2f", *value)
	},
	"delta": func(value *float64) string {
		if value == nil {
			return "—"
		}
		return fmt.Sprintf("%+.2f", *value)
	},
}
