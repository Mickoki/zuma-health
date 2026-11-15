package games

import (
	"bytes"
	"encoding/json"
	"fmt"
	"github.com/Mickoki/zuma-health/server/internal/domain"
	"io"
	"reflect"
	"regexp"
	"strings"
	"time"
)

var uuid = regexp.MustCompile(`(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)

func Defaults(game, difficulty string) (map[string]int, error) {
	level := map[string]int{"easy": 0, "normal": 1, "hard": 2}
	n, ok := level[difficulty]
	if !ok {
		return nil, fmt.Errorf("unknown difficulty")
	}
	switch game {
	case "fifteen":
		return map[string]int{"shuffle_moves": []int{30, 90, 180}[n]}, nil
	case "pairs":
		return map[string]int{"pairs": []int{9, 12, 18}[n], "preview_ms": []int{5000, 4000, 3000}[n], "mismatch_ms": 700}, nil
	case "math":
		return map[string]int{"question_count": 20, "time_limit_ms": 60000, "question_limit_ms": []int{8000, 6000, 4000}[n]}, nil
	case "chimp":
		return map[string]int{"columns": 8, "rows": 5, "start_count": []int{5, 6, 9}[n], "target_count": []int{12, 18, 24}[n], "mistake_limit": []int{4, 3, 2}[n]}, nil
	}
	return nil, fmt.Errorf("unknown game_id")
}
func decodeInitial(data []byte, target any) error {
	if len(data) == 0 || bytes.Equal(bytes.TrimSpace(data), []byte("null")) {
		return fmt.Errorf("initial object required")
	}
	d := json.NewDecoder(bytes.NewReader(data))
	d.DisallowUnknownFields()
	if e := d.Decode(target); e != nil {
		return e
	}
	if d.Decode(new(any)) != io.EOF {
		return fmt.Errorf("extra JSON")
	}
	return nil
}
func shape(e Event, index, positions bool) bool {
	return (index && e.Index != nil || !index && e.Index == nil && !e.hasIndex) && (positions && e.Positions != nil || !positions && e.Positions == nil && !e.hasPositions)
}
func val(v float64) *float64 { return &v }
func Validate(v Input, now time.Time) (Metrics, error) {
	if v.Survey != nil && !domain.ValidSurvey(v.Survey) {
		return nil, fmt.Errorf("invalid survey")
	}
	config, err := Defaults(v.GameID, v.Difficulty)
	if err != nil {
		return nil, err
	}
	if !uuid.MatchString(v.ClientRunID) || v.RulesVersion == nil || *v.RulesVersion != 1 || !reflect.DeepEqual(v.Config, config) {
		return nil, fmt.Errorf("invalid identity, rules_version or config")
	}
	if v.Source != "observed" && v.Source != "synthetic" {
		return nil, fmt.Errorf("invalid source")
	}
	if v.PerformedAt.IsZero() || v.PerformedAt.After(now.Add(5*time.Minute)) {
		return nil, fmt.Errorf("invalid performed_at")
	}
	if v.DurationMS == nil || *v.DurationMS < 0 || *v.DurationMS > 86400000 || len(v.Events) == 0 || len(v.Events) > 10000 {
		return nil, fmt.Errorf("invalid duration or event count")
	}
	var last int64
	for i, e := range v.Events {
		if e.TMS == nil || *e.TMS < last || *e.TMS > *v.DurationMS {
			return nil, fmt.Errorf("event %d has invalid t_ms", i)
		}
		last = *e.TMS
		if e.Kind == "finish" && (i != len(v.Events)-1 || !shape(e, false, false)) {
			return nil, fmt.Errorf("invalid finish event")
		}
	}
	end := v.Events[len(v.Events)-1]
	if end.Kind != "finish" || *end.TMS != *v.DurationMS {
		return nil, fmt.Errorf("final finish must equal duration_ms")
	}
	var m Metrics
	var terminal string
	switch v.GameID {
	case "fifteen":
		m, terminal, err = replayFifteen(v)
	case "pairs":
		m, terminal, err = replayPairs(v)
	case "math":
		m, terminal, err = replayMath(v)
	case "chimp":
		m, terminal, err = replayChimp(v)
	}
	if err != nil {
		return nil, err
	}
	if v.Status == "aborted" {
		if terminal != "" {
			return nil, fmt.Errorf("cannot abort a terminal game")
		}
		switch v.FinishReason {
		case "user_exit", "focus_lost", "host_removed", "recording_limit":
		default:
			return nil, fmt.Errorf("invalid abort reason")
		}
	} else {
		expected := "completed"
		if terminal == "mistake_limit" {
			expected = "failed"
		}
		if terminal == "" || v.Status != expected || v.FinishReason != terminal {
			return nil, fmt.Errorf("status/finish_reason contradict replay")
		}
	}
	m["duration_ms"] = val(float64(*v.DurationMS))
	return m, nil
}
func Canonical(v Input) ([]byte, error) {
	v.PerformedAt = v.PerformedAt.UTC()
	v.ClientRunID = strings.ToLower(v.ClientRunID)
	var raw any
	if e := json.Unmarshal(v.Initial, &raw); e != nil {
		return nil, e
	}
	v.Initial, _ = json.Marshal(raw)
	return json.Marshal(v)
}
func ComparisonKey(v Input) string {
	class := ""
	if v.Status == "completed" {
		class = v.FinishReason
		if v.GameID == "math" {
			class = "completed"
		}
	} else if v.GameID == "chimp" && v.Status == "failed" && v.FinishReason == "mistake_limit" {
		class = "mistake_limit"
	}
	if class == "" {
		return ""
	}
	b, _ := json.Marshal(v.Config)
	return fmt.Sprintf("%s|%d|%s|%s|%s|%s", v.GameID, *v.RulesVersion, v.Difficulty, v.Source, class, b)
}
