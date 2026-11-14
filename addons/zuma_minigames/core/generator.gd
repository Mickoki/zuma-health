extends RefCounted
## Scoped randomness; no global random seed or host settings are modified.

var last_layouts: Dictionary = {}
var math_pools: Dictionary = {}

func defaults(game: String, difficulty: String) -> Dictionary:
	var level: int = ["easy", "normal", "hard"].find(difficulty)
	if level < 0:
		return {}
	match game:
		"fifteen": return {"shuffle_moves": [30, 90, 180][level]}
		"pairs": return {"pairs": [9, 12, 18][level], "preview_ms": [5000, 4000, 3000][level], "mismatch_ms": 700}
		"math": return {"question_count": 20, "time_limit_ms": 60000, "question_limit_ms": [8000, 6000, 4000][level]}
		"chimp": return {"columns": 8, "rows": 5, "start_count": [5, 6, 9][level], "target_count": [12, 18, 24][level], "mistake_limit": [4, 3, 2][level]}
	return {}

func shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for i in range(values.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var old: Variant = values[i]
		values[i] = values[j]
		values[j] = old

func generate(game: String, difficulty: String, fixed_seed: int = -1) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	if fixed_seed >= 0:
		rng.seed = fixed_seed
	else:
		rng.randomize()
	var config: Dictionary = defaults(game, difficulty)
	assert(not config.is_empty(), "Unknown game or difficulty")
	if game == "chimp":
		return {}
	var key: String = game + ":" + difficulty
	while true:
		var data: Dictionary = {}
		match game:
			"fifteen":
				var board: Array = range(1, 16)
				board.append(0)
				var blank: int = 15
				var previous: int = -1
				var scramble: Array = []
				for step in range(config.shuffle_moves):
					var choices: Array = []
					for index in range(16):
						if index != previous and abs(index / 4 - blank / 4) + abs(index % 4 - blank % 4) == 1:
							choices.append(index)
					var next: int = choices[rng.randi_range(0, choices.size() - 1)]
					board[blank] = board[next]
					board[next] = 0
					previous = blank
					blank = next
					scramble.append(next)
				if is_solved(board):
					continue
				data = {"board": board, "scramble": scramble}
			"pairs":
				var cards: Array = []
				for symbol in range(config.pairs):
					cards.append(symbol)
					cards.append(symbol)
				shuffle(cards, rng)
				data = {"cards": cards}
			"math":
				data = {"questions": questions(difficulty, rng)}
		var signature: String = JSON.stringify(data.board if game == "fifteen" else data)
		if signature != last_layouts.get(key, ""):
			last_layouts[key] = signature
			return data
	return {}

func positions(count: int, rng: RandomNumberGenerator) -> Array:
	var key: String = "chimp:" + str(count)
	while true:
		var cells: Array = range(40)
		shuffle(cells, rng)
		cells = cells.slice(0, count)
		var signature: String = JSON.stringify(cells)
		if signature != last_layouts.get(key, ""):
			last_layouts[key] = signature
			return cells
	return []

static func is_solved(board: Array) -> bool:
	for i in range(15):
		if board[i] != i + 1:
			return false
	return board[15] == 0

func pools(difficulty: String) -> Dictionary:
	if math_pools.has(difficulty):
		return math_pools[difficulty]
	var maximum: int = {"easy": 30, "normal": 75, "hard": 150}[difficulty]
	var data: Dictionary = {"add": [], "sub": [], "mul": [], "div": []}
	for a in range(maximum + 1):
		for b in range(a, maximum + 1):
			data.add.append({"op": "add", "a": a, "b": b})
		for b in range(a + 1):
			data.sub.append({"op": "sub", "a": a, "b": b})
	if difficulty != "easy":
		var lower: int = 2 if difficulty == "hard" else 0
		var upper: int = 30 if difficulty == "hard" else 18
		for a in range(lower, upper + 1):
			for b in range(a, upper + 1):
				data.mul.append({"op": "mul", "a": a, "b": b})
	if difficulty == "hard":
		for divisor in range(2, 19):
			for quotient in range(2, 31):
				data.div.append({"op": "div", "a": divisor * quotient, "b": divisor})
	math_pools[difficulty] = data
	return data

func pool_sizes() -> Dictionary:
	var counts: Dictionary = {}
	for difficulty in ["easy", "normal", "hard"]:
		var count: int = 0
		for pool in pools(difficulty).values():
			count += pool.size()
		counts[difficulty] = count
	return counts

static func answer(question: Dictionary) -> int:
	match question.op:
		"add": return question.a + question.b
		"sub": return question.a - question.b
		"mul": return question.a * question.b
		"div": return int(question.a / question.b)
	return 0

func questions(difficulty: String, rng: RandomNumberGenerator) -> Array:
	var quotas: Dictionary = {"add": 10, "sub": 10}
	if difficulty == "normal":
		quotas = {"add": 7, "sub": 7, "mul": 6}
	if difficulty == "hard":
		quotas = {"add": 5, "sub": 5, "mul": 5, "div": 5}
	var source: Dictionary = pools(difficulty)
	var selected: Array = []
	for op in quotas:
		var pool: Array = source[op].duplicate()
		shuffle(pool, rng)
		for i in range(quotas[op]):
			var q: Dictionary = pool[i].duplicate(true)
			var correct: int = answer(q)
			var options: Array = [correct]
			while options.size() < 4:
				var wrong: int = clampi(correct + rng.randi_range(-maxi(6, absi(correct) / 5), maxi(6, absi(correct) / 5)), -1000, 1000)
				if not options.has(wrong):
					options.append(wrong)
			shuffle(options, rng)
			q["options"] = options
			selected.append(q)
	shuffle(selected, rng)
	return selected
