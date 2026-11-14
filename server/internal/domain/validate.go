package domain

import (
	"fmt"
	"math"
	"regexp"
	"strings"
	"time"
	"unicode/utf8"
)

var uuid = regexp.MustCompile(`(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)
var serverID = regexp.MustCompile(`^[0-9a-f]{32}$`)

func ValidID(id string) bool { return serverID.MatchString(id) }
func ValidName(name string) bool {
	n := utf8.RuneCountInString(strings.TrimSpace(name))
	return n >= 1 && n <= 100
}

func ValidateSession(s SessionInput, now time.Time) map[string]string {
	e := map[string]string{}
	if !uuid.MatchString(s.ClientSessionID) {
		e["client_session_id"] = "must be a UUID"
	}
	if s.PerformedAt.IsZero() || s.PerformedAt.After(now.Add(5*time.Minute)) {
		e["performed_at"] = "required RFC3339 timestamp, no more than 5 minutes in future"
	}
	if s.ProtocolVersion != "reaction-memory-v1" {
		e["protocol_version"] = "must be reaction-memory-v1"
	}
	if s.Source != "observed" && s.Source != "synthetic" {
		e["source"] = "must be observed or synthetic"
	}
	check := func(key string, v *float64, max float64) {
		if v == nil || math.IsNaN(*v) || math.IsInf(*v, 0) || *v < 0 || *v > max {
			e[key] = fmt.Sprintf("required finite number between 0 and %g", max)
		}
	}
	if s.Survey == nil {
		e["survey"] = "required"
	} else {
		check("survey.sleep_hours", s.Survey.SleepHours, 24)
		check("survey.fatigue", s.Survey.Fatigue, 10)
		check("survey.stress", s.Survey.Stress, 10)
		check("survey.mood", s.Survey.Mood, 10)
	}
	if s.Reaction == nil || len(s.Reaction.Trials) < 1 || len(s.Reaction.Trials) > 200 {
		e["reaction.trials"] = "requires 1 to 200 trials"
	} else {
		for i, t := range s.Reaction.Trials {
			key := fmt.Sprintf("reaction.trials.%d", i)
			switch t.Outcome {
			case "valid":
				if t.ReactionMS == nil || math.IsNaN(*t.ReactionMS) || math.IsInf(*t.ReactionMS, 0) || *t.ReactionMS < 1 || *t.ReactionMS > 10000 {
					e[key+".reaction_ms"] = "required number between 1 and 10000"
				}
			case "premature", "missed":
				if t.ReactionMS != nil || t.reactionMSProvided {
					e[key+".reaction_ms"] = "must be absent for this outcome"
				}
			default:
				e[key+".outcome"] = "must be valid, premature or missed"
			}
		}
	}
	if s.Memory == nil {
		e["memory"] = "required"
	} else if s.Memory.Correct == nil || s.Memory.Total == nil || *s.Memory.Total < 1 || *s.Memory.Total > 1000 || *s.Memory.Correct < 0 || *s.Memory.Correct > *s.Memory.Total {
		e["memory"] = "required integers: 1 <= total <= 1000 and 0 <= correct <= total"
	}
	return e
}
