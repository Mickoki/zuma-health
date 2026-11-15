package domain

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"time"
)

type Profile struct {
	ID          string    `json:"id"`
	DisplayName string    `json:"display_name"`
	CreatedAt   time.Time `json:"created_at"`
}
type Survey struct {
	SleepHours *float64 `json:"sleep_hours"`
	Fatigue    *float64 `json:"fatigue"`
	Stress     *float64 `json:"stress"`
	Mood       *float64 `json:"mood"`
}
type Trial struct {
	Outcome            string   `json:"outcome"`
	ReactionMS         *float64 `json:"reaction_ms,omitempty"`
	reactionMSProvided bool
}

// UnmarshalJSON retains presence: null is different from omitting reaction_ms.
func (t *Trial) UnmarshalJSON(data []byte) error {
	type wire Trial
	var value wire
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&value); err != nil {
		return err
	}
	if dec.Decode(new(any)) != io.EOF {
		return errors.New("extra JSON")
	}
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(data, &fields); err != nil {
		return err
	}
	_, value.reactionMSProvided = fields["reaction_ms"]
	*t = Trial(value)
	return nil
}

type Reaction struct {
	Trials []Trial `json:"trials"`
}
type Memory struct {
	Correct *int `json:"correct"`
	Total   *int `json:"total"`
}
type SessionInput struct {
	ClientSessionID string    `json:"client_session_id"`
	PerformedAt     time.Time `json:"performed_at"`
	ProtocolVersion string    `json:"protocol_version"`
	Source          string    `json:"source"`
	Survey          *Survey   `json:"survey"`
	Reaction        *Reaction `json:"reaction"`
	Memory          *Memory   `json:"memory"`
}
type Session struct {
	ID                 string    `json:"id"`
	ProfileID          string    `json:"profile_id"`
	ReceivedAt         time.Time `json:"received_at"`
	CalculationVersion string    `json:"calculation_version"`
	SessionInput
}
type ReactionMetrics struct {
	Valid     int      `json:"valid"`
	Premature int      `json:"premature"`
	Missed    int      `json:"missed"`
	MeanMS    *float64 `json:"mean_ms"`
	MedianMS  *float64 `json:"median_ms"`
}
type Comparison struct {
	ReactionDeltaMS      *float64 `json:"reaction_delta_ms"`
	ReactionDeltaPercent *float64 `json:"reaction_delta_percent"`
	MemoryDeltaPP        float64  `json:"memory_delta_pp"`
	SurveyDelta          Survey   `json:"survey_delta"`
}
type Report struct {
	SessionID          string            `json:"session_id"`
	ProtocolVersion    string            `json:"protocol_version"`
	CalculationVersion string            `json:"calculation_version"`
	Source             string            `json:"source"`
	PerformedAt        time.Time         `json:"performed_at"`
	BaselineSessionID  *string           `json:"baseline_session_id"`
	Reaction           ReactionMetrics   `json:"reaction"`
	MemoryPercent      float64           `json:"memory_percent"`
	Survey             Survey            `json:"survey"`
	SurveyScales       map[string]string `json:"survey_scales"`
	Comparison         *Comparison       `json:"comparison"`
	Limitations        []string          `json:"limitations"`
	Explanation        *Explanation      `json:"explanation"`
}
type Fact struct {
	ID       string `json:"id"`
	Category string `json:"category"`
	Text     string `json:"text"`
}
type Explanation struct {
	Status       string    `json:"status"`
	Model        string    `json:"model"`
	GeneratedAt  time.Time `json:"generated_at"`
	Observations []Fact    `json:"observations"`
	Comparisons  []Fact    `json:"comparisons"`
	Limitations  []Fact    `json:"limitations"`
}
