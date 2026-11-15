package model

import (
	"encoding/json"
	"errors"
	"github.com/Mickoki/zuma-health/server/internal/domain"
	"io"
	"strings"
)

func selectionSchema(facts []domain.Fact) map[string]any {
	properties := map[string]any{}
	for _, category := range []string{"observations", "comparisons", "limitations"} {
		ids := []string{}
		for _, f := range facts {
			if f.Category == category {
				ids = append(ids, f.ID)
			}
		}
		item := map[string]any{"type": "string"}
		if len(ids) > 0 {
			item["enum"] = ids
		}
		min := 0
		if category == "observations" {
			min = 1
		}
		properties[category] = map[string]any{"type": "array", "items": item, "minItems": min, "maxItems": len(ids), "uniqueItems": true}
	}
	return map[string]any{"type": "object", "properties": properties, "required": []string{"observations", "comparisons", "limitations"}, "additionalProperties": false}
}
func validateSelection(content string, facts []domain.Fact) (map[string][]domain.Fact, error) {
	var selected struct {
		Observations []string `json:"observations"`
		Comparisons  []string `json:"comparisons"`
		Limitations  []string `json:"limitations"`
	}
	dec := json.NewDecoder(strings.NewReader(content))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&selected); err != nil {
		return nil, err
	}
	if dec.Decode(new(any)) != io.EOF {
		return nil, errors.New("extra JSON value")
	}
	if len(selected.Observations) == 0 || selected.Comparisons == nil || selected.Limitations == nil {
		return nil, errors.New("required arrays missing")
	}
	byID := map[string]domain.Fact{}
	for _, f := range facts {
		byID[f.ID] = f
	}
	result := map[string][]domain.Fact{"observations": {}, "comparisons": {}, "limitations": {}}
	seen := map[string]bool{}
	for category, ids := range map[string][]string{"observations": selected.Observations, "comparisons": selected.Comparisons, "limitations": selected.Limitations} {
		if len(ids) > len(facts) {
			return nil, errors.New("too many facts")
		}
		for _, id := range ids {
			f, ok := byID[id]
			if !ok || f.Category != category || seen[id] {
				return nil, errors.New("invalid fact selection")
			}
			seen[id] = true
			result[category] = append(result[category], f)
		}
	}
	for _, f := range facts {
		if f.Category == "limitations" && !seen[f.ID] {
			result["limitations"] = append(result["limitations"], f)
		}
	}
	return result, nil
}
