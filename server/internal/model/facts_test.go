package model

import (
	"context"
	"github.com/Mickoki/zuma-health/server/internal/domain"
	"testing"
)

func TestExplainFactsSharesValidation(t *testing.T) {
	c, close := fake(t, `{"observations":["duration_ms"],"comparisons":[],"limitations":[]}`)
	defer close()
	facts := []domain.Fact{{ID: "duration_ms", Category: "observations", Text: "Duration: 200 ms"}, {ID: "not_medical", Category: "limitations", Text: "Not medical"}}
	v, e := c.ExplainFacts(context.Background(), facts)
	if e != nil || v.Status != "ready" || v.Observations[0].Text != "Duration: 200 ms" || len(v.Limitations) != 1 {
		t.Fatal(v, e)
	}
}
