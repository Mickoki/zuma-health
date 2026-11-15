package games

import "fmt"

func solved(board []int) bool {
	for i := 0; i < 15; i++ {
		if board[i] != i+1 {
			return false
		}
	}
	return board[15] == 0
}
func move(board []int, index int) bool {
	if index < 0 || index >= 16 || board[index] == 0 {
		return false
	}
	blank := 0
	for i, n := range board {
		if n == 0 {
			blank = i
			break
		}
	}
	distance := abs(index/4-blank/4) + abs(index%4-blank%4)
	if distance != 1 {
		return false
	}
	board[index], board[blank] = board[blank], board[index]
	return true
}
func abs(n int) int {
	if n < 0 {
		return -n
	}
	return n
}
func replayFifteen(v Input) (Metrics, string, error) {
	var initial struct {
		Board    Ints `json:"board"`
		Scramble Ints `json:"scramble"`
	}
	if e := decodeInitial(v.Initial, &initial); e != nil {
		return nil, "", e
	}
	if len(initial.Board) != 16 || len(initial.Scramble) != v.Config["shuffle_moves"] {
		return nil, "", fmt.Errorf("invalid board/scramble length")
	}
	seen := map[int]bool{}
	for _, n := range initial.Board {
		if n < 0 || n > 15 || seen[n] {
			return nil, "", fmt.Errorf("board must be permutation 0–15")
		}
		seen[n] = true
	}
	board := make([]int, 16)
	for i := 0; i < 15; i++ {
		board[i] = i + 1
	}
	previousBlank := -1
	blank := 15
	for _, index := range initial.Scramble {
		if index == previousBlank || !move(board, index) {
			return nil, "", fmt.Errorf("invalid scramble")
		}
		previousBlank, blank = blank, index
	}
	for i, n := range board {
		if initial.Board[i] != n {
			return nil, "", fmt.Errorf("initial board differs from scramble")
		}
	}
	if solved(board) {
		return nil, "", fmt.Errorf("scramble already solved")
	}
	count := 0
	for _, e := range v.Events[:len(v.Events)-1] {
		if e.Kind != "move" || !shape(e, true, false) || solved(board) || !move(board, *e.Index) {
			return nil, "", fmt.Errorf("illegal tile move")
		}
		count++
	}
	terminal := ""
	done := 0.0
	if solved(board) {
		terminal = "solved"
		done = 1
	}
	return Metrics{"moves": val(float64(count)), "solved": val(done)}, terminal, nil
}
