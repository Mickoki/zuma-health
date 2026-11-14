package domain

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"sort"
)

func number(v float64) *float64 { return &v }
func reactionMetrics(r *Reaction) ReactionMetrics {
	m := ReactionMetrics{}
	values := []float64{}
	sum := 0.0
	for _, t := range r.Trials {
		switch t.Outcome {
		case "valid":
			m.Valid++
			values = append(values, *t.ReactionMS)
			sum += *t.ReactionMS
		case "premature":
			m.Premature++
		case "missed":
			m.Missed++
		}
	}
	if len(values) > 0 {
		sort.Float64s(values)
		n := len(values)
		median := values[n/2]
		if n%2 == 0 {
			median = (values[n/2-1] + median) / 2
		}
		m.MeanMS = number(sum / float64(n))
		m.MedianMS = number(median)
	}
	return m
}
func Calculate(s Session, baseline *Session) Report {
	r := Report{SessionID: s.ID, ProtocolVersion: s.ProtocolVersion, CalculationVersion: "v1", Source: s.Source, PerformedAt: s.PerformedAt,
		Reaction: reactionMetrics(s.Reaction), MemoryPercent: float64(*s.Memory.Correct) / float64(*s.Memory.Total) * 100, Survey: *s.Survey,
		SurveyScales: map[string]string{"sleep_hours": "hours, 0–24", "fatigue": "0–10, higher = more fatigue", "stress": "0–10, higher = more stress", "mood": "0–10, higher = better mood"}, Limitations: []string{"not_medical"}}
	if s.Source == "synthetic" {
		r.Limitations = append(r.Limitations, "synthetic")
	}
	if r.Reaction.Valid == 0 {
		r.Limitations = append(r.Limitations, "no_valid_reaction")
	}
	if baseline == nil || baseline.ProfileID != s.ProfileID || baseline.Source != s.Source || baseline.ProtocolVersion != s.ProtocolVersion || !baseline.PerformedAt.Before(s.PerformedAt) {
		r.Limitations = append(r.Limitations, "no_baseline")
		return r
	}
	b := Calculate(*baseline, nil)
	r.BaselineSessionID = &baseline.ID
	c := Comparison{MemoryDeltaPP: r.MemoryPercent - b.MemoryPercent, SurveyDelta: Survey{SleepHours: number(*s.Survey.SleepHours - *baseline.Survey.SleepHours), Fatigue: number(*s.Survey.Fatigue - *baseline.Survey.Fatigue), Stress: number(*s.Survey.Stress - *baseline.Survey.Stress), Mood: number(*s.Survey.Mood - *baseline.Survey.Mood)}}
	if r.Reaction.MedianMS != nil && b.Reaction.MedianMS != nil {
		d := *r.Reaction.MedianMS - *b.Reaction.MedianMS
		c.ReactionDeltaMS = &d
		c.ReactionDeltaPercent = number(d / *b.Reaction.MedianMS * 100)
	}
	r.Comparison = &c
	return r
}

// Fingerprint excludes cached explanation and includes baseline identity and all calculated inputs.
func Fingerprint(r Report) string {
	r.Explanation = nil
	b, _ := json.Marshal(r)
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:])
}
