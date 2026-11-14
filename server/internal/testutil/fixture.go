// Package testutil provides synthetic fixtures for tests only.
package testutil

import (
	"encoding/json"
	"github.com/Mickoki/zuma-health/server/internal/domain"
)

const SessionJSON = `{"client_session_id":"123e4567-e89b-42d3-a456-426614174000","performed_at":"2026-01-02T12:00:00Z","protocol_version":"reaction-memory-v1","source":"synthetic","survey":{"sleep_hours":8,"fatigue":0,"stress":2,"mood":7},"reaction":{"trials":[{"outcome":"valid","reaction_ms":200},{"outcome":"valid","reaction_ms":300},{"outcome":"missed"}]},"memory":{"correct":3,"total":4}}`

func Input() domain.SessionInput {
	var s domain.SessionInput
	if err := json.Unmarshal([]byte(SessionJSON), &s); err != nil {
		panic(err)
	}
	return s
}
