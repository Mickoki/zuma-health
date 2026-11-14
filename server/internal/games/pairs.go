package games

import "fmt"

func replayPairs(v Input) (Metrics, string, error) {
	var initial struct {
		Cards Ints `json:"cards"`
	}
	if e := decodeInitial(v.Initial, &initial); e != nil {
		return nil, "", e
	}
	n := v.Config["pairs"]
	if len(initial.Cards) != n*2 {
		return nil, "", fmt.Errorf("invalid card count")
	}
	counts := make([]int, n)
	for _, card := range initial.Cards {
		if card < 0 || card >= n {
			return nil, "", fmt.Errorf("invalid card symbol")
		}
		counts[card]++
	}
	for _, count := range counts {
		if count != 2 {
			return nil, "", fmt.Errorf("each symbol requires two cards")
		}
	}
	found := map[int]bool{}
	first := -1
	attempts, errors, pairs := 0, 0, 0
	locked := int64(v.Config["preview_ms"])
	for _, e := range v.Events[:len(v.Events)-1] {
		if e.Kind != "flip" || !shape(e, true, false) || *e.TMS < locked || pairs == n {
			return nil, "", fmt.Errorf("invalid flip timing/state")
		}
		i := *e.Index
		if i < 0 || i >= len(initial.Cards) || found[i] || first == i {
			return nil, "", fmt.Errorf("card cannot be selected")
		}
		if first < 0 {
			first = i
			continue
		}
		attempts++
		if initial.Cards[first] == initial.Cards[i] {
			found[first] = true
			found[i] = true
			pairs++
		} else {
			errors++
			locked = *e.TMS + int64(v.Config["mismatch_ms"])
		}
		first = -1
	}
	terminal := ""
	if pairs == n {
		terminal = "solved"
	}
	active := *v.DurationMS - int64(v.Config["preview_ms"])
	if active < 0 {
		active = 0
	}
	m := Metrics{"pairs_found": val(float64(pairs)), "attempts": val(float64(attempts)), "errors": val(float64(errors)), "accuracy_percent": nil, "active_ms": val(float64(active))}
	if attempts > 0 {
		m["accuracy_percent"] = val(float64(pairs) / float64(attempts) * 100)
	}
	return m, terminal, nil
}
