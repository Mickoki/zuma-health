package games

import "fmt"

func replayChimp(v Input) (Metrics, string, error) {
	if e := decodeInitial(v.Initial, &struct{}{}); e != nil {
		return nil, "", e
	}
	n := v.Config["start_count"]
	target := v.Config["target_count"]
	positions := []int(nil)
	next := 0
	errors, success, rounds := 0, 0, 0
	maxCount := 0
	var shownAt, hiddenAt int64
	previewTimes, selectionTimes := []float64{}, []float64{}
	terminal := ""
	for _, e := range v.Events[:len(v.Events)-1] {
		if terminal != "" {
			return nil, "", fmt.Errorf("events after terminal round")
		}
		t := *e.TMS
		switch e.Kind {
		case "show":
			if !shape(e, false, true) || positions != nil || len(e.Positions) != n || rounds == 0 && t != 0 {
				return nil, "", fmt.Errorf("invalid round show")
			}
			seen := map[int]bool{}
			for _, p := range e.Positions {
				if p < 0 || p >= 40 || seen[p] {
					return nil, "", fmt.Errorf("invalid cell layout")
				}
				seen[p] = true
			}
			positions = e.Positions
			next = 0
			shownAt = t
			rounds++
		case "click":
			if !shape(e, true, false) || positions == nil {
				return nil, "", fmt.Errorf("click without round")
			}
			index := *e.Index
			number := -1
			for i, p := range positions {
				if p == index {
					number = i
					break
				}
			}
			if number < next || number < 0 {
				return nil, "", fmt.Errorf("cell is not selectable")
			}
			if number != next {
				errors++
				positions = nil
				if errors == v.Config["mistake_limit"] {
					terminal = "mistake_limit"
				}
				continue
			}
			if next == 0 {
				hiddenAt = t
				previewTimes = append(previewTimes, float64(t-shownAt))
			}
			next++
			if next == n {
				success++
				maxCount = n
				selectionTimes = append(selectionTimes, float64(t-hiddenAt))
				positions = nil
				if n == target {
					terminal = "target_reached"
				} else {
					n++
				}
			}
		default:
			return nil, "", fmt.Errorf("invalid chimp event")
		}
	}
	preview, _ := averageMedian(previewTimes)
	selection, _ := averageMedian(selectionTimes)
	m := Metrics{"rounds": val(float64(rounds)), "successful_rounds": val(float64(success)), "failed_rounds": val(float64(errors)), "errors": val(float64(errors)), "max_completed_count": nil, "mean_preview_ms": preview, "mean_selection_ms": selection}
	if maxCount > 0 {
		m["max_completed_count"] = val(float64(maxCount))
	}
	return m, terminal, nil
}
