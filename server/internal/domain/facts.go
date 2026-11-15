package domain

import "fmt"

func BuildFacts(r Report) []Fact {
	facts := []Fact{}
	add := func(id, category, text string) { facts = append(facts, Fact{ID: id, Category: category, Text: text}) }
	add("reaction_counts", "observations", fmt.Sprintf("Reaction: valid attempts — %d, premature attempts — %d, missed attempts — %d.", r.Reaction.Valid, r.Reaction.Premature, r.Reaction.Missed))
	if r.Reaction.MedianMS != nil {
		add("reaction_median", "observations", fmt.Sprintf("Median reaction time: %.2f ms.", *r.Reaction.MedianMS))
		add("reaction_mean", "observations", fmt.Sprintf("Mean reaction time: %.2f ms.", *r.Reaction.MeanMS))
	}
	add("memory_accuracy", "observations", fmt.Sprintf("Memory task accuracy: %.2f%%.", r.MemoryPercent))
	add("survey", "observations", fmt.Sprintf("Self-assessment: sleep %.2f h; fatigue %.2f/10; stress %.2f/10; mood %.2f/10 (higher is better).", *r.Survey.SleepHours, *r.Survey.Fatigue, *r.Survey.Stress, *r.Survey.Mood))
	if r.Comparison != nil {
		c := r.Comparison
		add("memory_change", "comparisons", fmt.Sprintf("Change in accuracy from the previous comparable session: %+.2f percentage points.", c.MemoryDeltaPP))
		if c.ReactionDeltaMS != nil {
			add("reaction_change", "comparisons", fmt.Sprintf("Change in median reaction time: %+.2f ms (%+.2f%%).", *c.ReactionDeltaMS, *c.ReactionDeltaPercent))
		}
		add("survey_change", "comparisons", fmt.Sprintf("Change in self-assessment: sleep %+.2f h, fatigue %+.2f, stress %+.2f, mood %+.2f.", *c.SurveyDelta.SleepHours, *c.SurveyDelta.Fatigue, *c.SurveyDelta.Stress, *c.SurveyDelta.Mood))
	}
	texts := map[string]string{"not_medical": "Task results are not a medical diagnosis.", "synthetic": "This session contains synthetic demonstration data.", "no_valid_reaction": "There are no valid reaction attempts; mean and median are unavailable.", "no_baseline": "There is no previous comparable session; comparison is unavailable."}
	for _, id := range r.Limitations {
		add(id, "limitations", texts[id])
	}
	if r.Comparison != nil && r.Comparison.ReactionDeltaMS == nil {
		add("reaction_comparison_unavailable", "limitations", "Reaction time comparison is unavailable: one session has no valid attempts.")
	}
	return facts
}
