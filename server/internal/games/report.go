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
	"duration_ms": "Total duration", "moves": "Moves", "solved": "Board solved (1 = yes)",
	"pairs_found": "Pairs found", "attempts": "Attempts", "errors": "Errors", "accuracy_percent": "Accuracy", "active_ms": "Time after card preview",
	"shown": "Questions shown", "correct": "Correct answers", "incorrect": "Incorrect answers", "skipped": "Skipped questions", "manual_skips": "Manual skips", "timeouts": "Timeouts", "answered": "Accepted answers", "mean_answer_ms": "Mean answer time", "median_answer_ms": "Median answer time", "correct_per_minute": "Correct answers per minute",
	"rounds": "Rounds started", "successful_rounds": "Successful rounds", "failed_rounds": "Failed rounds", "max_completed_count": "Maximum successfully recalled number count", "mean_preview_ms": "Mean preview time before first selection", "mean_selection_ms": "Mean successful round time after first selection",
}

func Unit(key string) string {
	switch key {
	case "duration_ms", "active_ms", "mean_answer_ms", "median_answer_ms", "mean_preview_ms", "mean_selection_ms":
		return "ms"
	case "accuracy_percent":
		return "%"
	case "correct_per_minute":
		return "answers/min"
	default:
		return "count"
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
	b, _ := json.Marshal(struct {
		Report Report        `json:"report"`
		Facts  []domain.Fact `json:"facts"`
	}{r, Facts(r)})
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:])
}
func Facts(r Report) []domain.Fact {
	facts := []domain.Fact{{ID: "run_outcome", Category: "observations", Text: fmt.Sprintf("Game %s; difficulty %s; outcome %s, reason %s.", r.GameID, r.Difficulty, r.Status, r.FinishReason)}}
	if domain.ValidSurvey(r.Survey) {
		facts = append(facts, domain.Fact{ID: "survey", Category: "observations", Text: fmt.Sprintf("Saved survey: sleep %.2f h; fatigue %.2f/10; stress %.2f/10; mood %.2f/10 (higher is better).", *r.Survey.SleepHours, *r.Survey.Fatigue, *r.Survey.Stress, *r.Survey.Mood)})
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
					unit = "pp"
				}
				facts = append(facts, domain.Fact{ID: "delta_" + key, Category: "comparisons", Text: fmt.Sprintf("Change in %s from the previous comparable run: %+.2f %s.", labels[key], *value, unit)})
			}
		}
	}
	texts := map[string]string{"not_medical": "Task results are not a medical diagnosis.", "client_timing": "Times come from the local client; the server checks event consistency, not measurement authenticity.", "survey_timing": "The survey was copied from a saved draft; its completion time is unknown and may differ from the game time.", "synthetic": "These are synthetic demonstration data.", "incomplete": "The run was aborted; partial metrics are not compared with completed runs.", "no_baseline": "There is no previous comparable run; comparison is unavailable."}
	for _, key := range r.Limitations {
		facts = append(facts, domain.Fact{ID: key, Category: "limitations", Text: texts[key]})
	}
	for _, key := range keys {
		if r.Metrics[key] == nil {
			facts = append(facts, domain.Fact{ID: "missing_" + key, Category: "limitations", Text: fmt.Sprintf("%s is unavailable: insufficient eligible events.", labels[key])})
		}
	}
	return facts
}
