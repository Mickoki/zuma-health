package testutil

import (
	"encoding/json"
	"fmt"
	"github.com/Mickoki/zuma-health/server/internal/games"
	"time"
)

func P[T any](v T) *T { return &v }
func GameInput(game string) games.Input {
	config, _ := games.Defaults(game, "easy")
	v := games.Input{ClientRunID: "123e4567-e89b-42d3-a456-426614174000", GameID: game, RulesVersion: P(1), Difficulty: "easy", Config: config, Source: "synthetic", PerformedAt: time.Date(2026, 1, 2, 12, 0, 0, 0, time.UTC), Status: "completed"}
	add := func(kind string, t int64, index *int, positions []int) {
		v.Events = append(v.Events, games.Event{Kind: kind, TMS: P(t), Index: index, Positions: positions})
	}
	var initial any
	switch game {
	case "fifteen":
		board := make([]int, 16)
		for i := 0; i < 15; i++ {
			board[i] = i + 1
		}
		blank := 15
		path := []int{14, 13, 12, 8, 4, 0, 1, 2, 3, 7, 11, 15}
		scramble := []int{}
		reverse := []int{}
		for i := 0; i < 30; i++ {
			next := path[i%12]
			scramble = append(scramble, next)
			reverse = append(reverse, blank)
			board[blank], board[next] = board[next], board[blank]
			blank = next
		}
		initial = map[string]any{"board": board, "scramble": scramble}
		for i := 29; i >= 0; i-- {
			add("move", int64(30-i)*100, P(reverse[i]), nil)
		}
		v.FinishReason = "solved"
		v.DurationMS = P(int64(3001))
	case "pairs":
		cards := []int{}
		for i := 0; i < 9; i++ {
			cards = append(cards, i, i)
		}
		initial = map[string]any{"cards": cards}
		for i := 0; i < 18; i++ {
			add("flip", 5000+int64(i)*10, P(i), nil)
		}
		v.FinishReason = "solved"
		v.DurationMS = P(int64(5200))
	case "math":
		questions := []map[string]any{}
		for i := 0; i < 20; i++ {
			op := "add"
			if i >= 10 {
				op = "sub"
			}
			a := i % 10
			questions = append(questions, map[string]any{"op": op, "a": a, "b": 0, "options": []int{a, a + 1, a + 2, a + 3}})
			add("show", int64(i)*1000, P(i), nil)
			add("answer", int64(i)*1000+500, P(0), nil)
		}
		initial = map[string]any{"questions": questions}
		v.FinishReason = "questions_done"
		v.DurationMS = P(int64(20000))
	case "chimp":
		initial = map[string]any{}
		var t int64
		for n := 5; n <= 12; n++ {
			positions := make([]int, n)
			for i := range positions {
				positions[i] = i
			}
			add("show", t, nil, positions)
			for i := 0; i < n; i++ {
				t += 100
				add("click", t, P(i), nil)
			}
			t += 100
		}
		v.FinishReason = "target_reached"
		v.DurationMS = P(t)
	default:
		panic(fmt.Sprintf("unknown game %s", game))
	}
	v.Initial, _ = json.Marshal(initial)
	add("finish", *v.DurationMS, nil, nil)
	return v
}
