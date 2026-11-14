package games

import (
	"fmt"
	"sort"
)

type Question struct {
	Op      string `json:"op"`
	A       *int   `json:"a"`
	B       *int   `json:"b"`
	Options Ints   `json:"options"`
}

func mathAnswer(q Question, difficulty string) (int, string, error) {
	if q.A == nil || q.B == nil || len(q.Options) != 4 {
		return 0, "", fmt.Errorf("incomplete question")
	}
	a, b := *q.A, *q.B
	max := map[string]int{"easy": 30, "normal": 75, "hard": 150}[difficulty]
	result := 0
	lo, hi := a, b
	switch q.Op {
	case "add", "sub":
		if a < 0 || b < 0 || a > max || b > max || q.Op == "sub" && a < b {
			return 0, "", fmt.Errorf("operands outside range")
		}
		result = a + b
		if q.Op == "sub" {
			result = a - b
		} else if lo > hi {
			lo, hi = hi, lo
		}
	case "mul":
		min, mmax := 0, 18
		if difficulty == "hard" {
			min, mmax = 2, 30
		}
		if difficulty == "easy" || a < min || b < min || a > mmax || b > mmax {
			return 0, "", fmt.Errorf("invalid multiplication")
		}
		result = a * b
		if lo > hi {
			lo, hi = hi, lo
		}
	case "div":
		if difficulty != "hard" || b < 2 || b > 18 || a%b != 0 || a/b < 2 || a/b > 30 {
			return 0, "", fmt.Errorf("invalid division")
		}
		result = a / b
	default:
		return 0, "", fmt.Errorf("unknown operator")
	}
	seen := map[int]bool{}
	correct := 0
	for _, option := range q.Options {
		if option < -1000 || option > 1000 || seen[option] {
			return 0, "", fmt.Errorf("invalid options")
		}
		seen[option] = true
		if option == result {
			correct++
		}
	}
	if correct != 1 {
		return 0, "", fmt.Errorf("exactly one correct option required")
	}
	return result, fmt.Sprintf("%s:%d:%d", q.Op, lo, hi), nil
}
func averageMedian(values []float64) (*float64, *float64) {
	if len(values) == 0 {
		return nil, nil
	}
	sort.Float64s(values)
	sum := 0.0
	for _, n := range values {
		sum += n
	}
	mid := values[len(values)/2]
	if len(values)%2 == 0 {
		mid = (mid + values[len(values)/2-1]) / 2
	}
	return val(sum / float64(len(values))), val(mid)
}
func replayMath(v Input) (Metrics, string, error) {
	var initial struct {
		Questions []Question `json:"questions"`
	}
	if e := decodeInitial(v.Initial, &initial); e != nil {
		return nil, "", e
	}
	if len(initial.Questions) != 20 {
		return nil, "", fmt.Errorf("20 questions required")
	}
	results := []int{}
	keys := map[string]bool{}
	counts := map[string]int{}
	for _, q := range initial.Questions {
		answer, key, e := mathAnswer(q, v.Difficulty)
		if e != nil {
			return nil, "", e
		}
		if keys[key] {
			return nil, "", fmt.Errorf("duplicate expression")
		}
		keys[key] = true
		counts[q.Op]++
		results = append(results, answer)
	}
	expected := map[string]int{"add": 10, "sub": 10}
	if v.Difficulty == "normal" {
		expected = map[string]int{"add": 7, "sub": 7, "mul": 6}
	}
	if v.Difficulty == "hard" {
		expected = map[string]int{"add": 5, "sub": 5, "mul": 5, "div": 5}
	}
	for op, n := range expected {
		if counts[op] != n {
			return nil, "", fmt.Errorf("invalid operation quota")
		}
	}
	shown, correct, wrong, skipped, manual, timed := 0, 0, 0, 0, 0, 0
	active := false
	var opened, deadline int64
	times := []float64{}
	for _, e := range v.Events[:len(v.Events)-1] {
		t := *e.TMS
		switch e.Kind {
		case "show":
			if !shape(e, true, false) || active || shown >= 20 || *e.Index != shown || t >= 60000 || shown == 0 && t != 0 {
				return nil, "", fmt.Errorf("invalid question show")
			}
			shown++
			active = true
			opened = t
			deadline = t + int64(v.Config["question_limit_ms"])
			if deadline > 60000 {
				deadline = 60000
			}
		case "answer":
			if !shape(e, true, false) || !active || t >= deadline || *e.Index < 0 || *e.Index > 3 {
				return nil, "", fmt.Errorf("invalid/late answer")
			}
			if initial.Questions[shown-1].Options[*e.Index] == results[shown-1] {
				correct++
			} else {
				wrong++
			}
			times = append(times, float64(t-opened))
			active = false
		case "skip":
			if !shape(e, false, false) || !active || t >= deadline {
				return nil, "", fmt.Errorf("invalid skip")
			}
			skipped++
			manual++
			active = false
		case "timeout":
			if !shape(e, false, false) || !active || t < deadline {
				return nil, "", fmt.Errorf("invalid timeout")
			}
			skipped++
			timed++
			active = false
		default:
			return nil, "", fmt.Errorf("invalid math event")
		}
	}
	if active && *v.DurationMS >= deadline {
		return nil, "", fmt.Errorf("overdue question requires timeout before finish")
	}
	terminal := ""
	if !active && shown == 20 {
		terminal = "questions_done"
	} else if !active && shown > 0 && *v.DurationMS >= 60000 {
		terminal = "time_limit"
	}
	mean, median := averageMedian(times)
	m := Metrics{"shown": val(float64(shown)), "correct": val(float64(correct)), "incorrect": val(float64(wrong)), "skipped": val(float64(skipped)), "manual_skips": val(float64(manual)), "timeouts": val(float64(timed)), "answered": val(float64(correct + wrong)), "accuracy_percent": nil, "mean_answer_ms": mean, "median_answer_ms": median, "correct_per_minute": nil}
	if correct+wrong > 0 {
		m["accuracy_percent"] = val(float64(correct) / float64(correct+wrong) * 100)
	}
	if *v.DurationMS > 0 {
		m["correct_per_minute"] = val(float64(correct) * 60000 / float64(*v.DurationMS))
	}
	return m, terminal, nil
}
