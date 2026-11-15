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
			return "pp"
		}
		return unit
	},
	"gameTitle": func(id string) string {
		return map[string]string{"fifteen": "Fifteen Puzzle", "pairs": "Find the Pair", "math": "Speed Math", "chimp": "Remember the Numbers"}[id]
	},
	"sourceTitle": func(source string) string {
		if source == "synthetic" {
			return "Synthetic data"
		}
		return "Local run"
	},
	"difficultyTitle": func(level string) string {
		return map[string]string{"easy": "Easy", "normal": "Normal", "hard": "Hard"}[level]
	},
	"outcomeTitle": func(reason string) string {
		return map[string]string{"solved": "Puzzle solved", "questions_done": "All questions completed", "time_limit": "Time limit reached", "target_reached": "Target reached", "mistake_limit": "Mistake limit reached", "focus_lost": "Window lost focus", "user_exit": "Exited game", "host_removed": "Module closed", "recording_limit": "Recording limit reached"}[reason]
	},
	"metricTitle": func(key string) string {
		titles := map[string]string{
			"duration_ms": "Duration", "moves": "Moves", "solved": "Board solved (1 = yes)",
			"pairs_found": "Pairs found", "attempts": "Attempts", "errors": "Errors", "accuracy_percent": "Accuracy",
			"active_ms": "Pair search time", "shown": "Questions shown", "correct": "Correct answers",
			"incorrect": "Incorrect answers", "skipped": "Skipped questions", "manual_skips": "Manual skips",
			"timeouts": "Timeouts", "answered": "Accepted answers", "mean_answer_ms": "Mean answer time",
			"successful_rounds": "Successful rounds", "max_completed_count": "Maximum completed number count",
			"median_answer_ms": "Median answer time", "correct_per_minute": "Correct answers per minute",
			"rounds": "Rounds started", "failed_rounds": "Failed rounds",
			"mean_preview_ms":   "Mean preview time before first selection",
			"mean_selection_ms": "Mean successful round time after first selection",
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
