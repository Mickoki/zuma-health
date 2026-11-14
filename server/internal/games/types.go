package games

import (
	"bytes"
	"encoding/json"
	"fmt"
	"github.com/Mickoki/zuma-health/server/internal/domain"
	"time"
)

type Input struct {
	ClientRunID  string          `json:"client_run_id"`
	GameID       string          `json:"game_id"`
	RulesVersion *int            `json:"rules_version"`
	Difficulty   string          `json:"difficulty"`
	Config       map[string]int  `json:"config"`
	Source       string          `json:"source"`
	PerformedAt  time.Time       `json:"performed_at"`
	Status       string          `json:"status"`
	FinishReason string          `json:"finish_reason"`
	DurationMS   *int64          `json:"duration_ms"`
	Initial      json.RawMessage `json:"initial"`
	Events       []Event         `json:"events"`
}
type Event struct {
	Kind                   string `json:"kind"`
	TMS                    *int64 `json:"t_ms"`
	Index                  *int   `json:"index,omitempty"`
	Positions              []int  `json:"positions,omitempty"`
	hasIndex, hasPositions bool
}

func (e *Event) UnmarshalJSON(data []byte) error {
	type wire Event
	var v wire
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&v); err != nil {
		return err
	}
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(data, &fields); err != nil {
		return err
	}
	for key := range fields {
		switch key {
		case "kind", "t_ms", "index", "positions":
		default:
			return fmt.Errorf("unknown event field %q", key)
		}
	}
	_, v.hasIndex = fields["index"]
	_, v.hasPositions = fields["positions"]
	*e = Event(v)
	return nil
}

type Run struct {
	ID                 string    `json:"id"`
	ProfileID          string    `json:"profile_id"`
	ReceivedAt         time.Time `json:"received_at"`
	CalculationVersion string    `json:"calculation_version"`
	Input
}
type Metrics map[string]*float64
type Report struct {
	RunID              string              `json:"run_id"`
	GameID             string              `json:"game_id"`
	RulesVersion       int                 `json:"rules_version"`
	CalculationVersion string              `json:"calculation_version"`
	Difficulty         string              `json:"difficulty"`
	Config             map[string]int      `json:"config"`
	Source             string              `json:"source"`
	Status             string              `json:"status"`
	FinishReason       string              `json:"finish_reason"`
	PerformedAt        time.Time           `json:"performed_at"`
	Metrics            Metrics             `json:"metrics"`
	Units              map[string]string   `json:"units"`
	BaselineRunID      *string             `json:"baseline_run_id"`
	Deltas             Metrics             `json:"deltas"`
	Limitations        []string            `json:"limitations"`
	Explanation        *domain.Explanation `json:"explanation"`
}
