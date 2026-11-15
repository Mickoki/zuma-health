extends RefCounted

const Generator = preload("res://addons/zuma_minigames/core/generator.gd")
var generator
var rng := RandomNumberGenerator.new()
var game_id: String
var difficulty: String
var config: Dictionary
var initial: Dictionary
var events: Array = []
var source: String = "observed"
var performed_at: String
var client_run_id: String
var done: bool = false
var result: Dictionary = {}
var last_time: int = 0
var board: Array = []
var moves: int = 0
var cards: Array = []
var found: Dictionary = {}
var open_first: int = -1
var open_second: int = -1
var locked_until: int = 0
var pairs_found: int = 0
var attempts: int = 0
var pair_errors: int = 0
var question_index: int = -1
var question_open: bool = false
var question_started: int = 0
var deadline: int = 0
var correct: int = 0
var incorrect: int = 0
var skipped: int = 0
var positions: Array = []
var chimp_count: int = 0
var chimp_next: int = 0
var hidden: bool = false
var round_pending: bool = false
var chimp_errors: int = 0
var chimp_success: int = 0
var max_completed_count: int = 0

func _init(game: String, level: String, scoped_generator = null, fixed_seed: int = -1) -> void:
	game_id = game
	difficulty = level
	generator = scoped_generator if scoped_generator != null else Generator.new()
	config = generator.defaults(game_id, difficulty)
	initial = generator.generate(game_id, difficulty, fixed_seed)
	if fixed_seed >= 0:
		rng.seed = fixed_seed
	else:
		rng.randomize()
	performed_at = Time.get_datetime_string_from_system(true) + "Z"
	client_run_id = uuid()
	match game_id:
		"fifteen": board = initial.board.duplicate()
		"pairs":
			cards = initial.cards.duplicate()
			locked_until = config.preview_ms
		"math": _show_question(0)
		"chimp":
			chimp_count = config.start_count
			next_round(0)

static func uuid() -> String:
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 15) | 64
	bytes[8] = (bytes[8] & 63) | 128
	var text: String = bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [text.substr(0, 8), text.substr(8, 4), text.substr(12, 4), text.substr(16, 4), text.substr(20, 12)]

func _record(kind: String, t: int, index: int = -1, cells: Array = []) -> void:
	var event: Dictionary = {"kind": kind, "t_ms": t}
	if index >= 0:
		event["index"] = index
	if not cells.is_empty():
		event["positions"] = cells.duplicate()
	events.append(event)

func _finish(status: String, reason: String, t: int) -> void:
	if done:
		return
	done = true
	last_time = t
	_record("finish", t)
	result = {"client_run_id": client_run_id, "game_id": game_id, "rules_version": 1,
		"difficulty": difficulty, "config": config.duplicate(true), "source": source,
		"performed_at": performed_at, "status": status, "finish_reason": reason,
		"duration_ms": t, "initial": initial.duplicate(true), "events": events.duplicate(true)}

func advance(t: int) -> void:
	if done or t < last_time:
		return
	if t > 86400000 or events.size() >= 9996:
		_finish("aborted", "recording_limit", mini(t, 86400000))
		return
	last_time = t
	if game_id == "pairs" and open_second >= 0 and t >= locked_until:
		open_first = -1
		open_second = -1
	if game_id == "math" and question_open and t >= deadline:
		_record("timeout", t)
		skipped += 1
		question_open = false
		_after_question(t)

func abort(reason: String, t: int) -> void:
	advance(t)
	if not done:
		_finish("aborted", reason, t)

func act(index: int, t: int) -> bool:
	var before_question: int = question_index
	advance(t)
	if done or t < last_time:
		return false
	match game_id:
		"fifteen":
			if index < 0 or index >= 16 or board[index] == 0:
				return false
			var blank: int = board.find(0)
			if abs(index / 4 - blank / 4) + abs(index % 4 - blank % 4) != 1:
				return false
			board[blank] = board[index]
			board[index] = 0
			moves += 1
			_record("move", t, index)
			if Generator.is_solved(board):
				_finish("completed", "solved", t)
		"pairs":
			if t < locked_until or index < 0 or index >= cards.size() or found.has(index) or open_first == index:
				return false
			_record("flip", t, index)
			if open_first < 0:
				open_first = index
			else:
				attempts += 1
				if cards[open_first] == cards[index]:
					found[open_first] = true
					found[index] = true
					pairs_found += 1
					open_first = -1
					if pairs_found == config.pairs:
						_finish("completed", "solved", t)
				else:
					pair_errors += 1
					open_second = index
					locked_until = t + config.mismatch_ms
		"math":
			if before_question != question_index or not question_open or index < 0 or index > 3:
				return false
			var question: Dictionary = initial.questions[question_index]
			_record("answer", t, index)
			if question.options[index] == Generator.answer(question):
				correct += 1
			else:
				incorrect += 1
			question_open = false
			_after_question(t)
		"chimp":
			if round_pending or positions.is_empty():
				return false
			var number: int = positions.find(index)
			if number < chimp_next:
				return false
			_record("click", t, index)
			if number != chimp_next:
				chimp_errors += 1
				round_pending = true
				if chimp_errors >= config.mistake_limit:
					_finish("failed", "mistake_limit", t)
			else:
				chimp_next += 1
				hidden = true
				if chimp_next == chimp_count:
					chimp_success += 1
					max_completed_count = chimp_count
					round_pending = true
					if chimp_count == config.target_count:
						_finish("completed", "target_reached", t)
					else:
						chimp_count += 1
		_:
			return false
	return true

func _show_question(t: int) -> void:
	question_index += 1
	question_open = true
	question_started = t
	deadline = mini(60000, t + config.question_limit_ms)
	_record("show", t, question_index)

func _after_question(t: int) -> void:
	if question_index == 19:
		_finish("completed", "questions_done", t)
	elif t >= 60000:
		_finish("completed", "time_limit", t)
	else:
		_show_question(t)

func skip(t: int) -> void:
	var previous: int = question_index
	advance(t)
	if done or game_id != "math" or not question_open or previous != question_index:
		return
	_record("skip", t)
	skipped += 1
	question_open = false
	_after_question(t)

func next_round(t: int) -> void:
	advance(t)
	if done or game_id != "chimp" or not positions.is_empty() and not round_pending:
		return
	positions = generator.positions(chimp_count, rng)
	chimp_next = 0
	hidden = false
	round_pending = false
	_record("show", t, -1, positions)

func summary() -> Dictionary:
	var data: Dictionary = {"Duration, ms": last_time}
	match game_id:
		"fifteen": data["Moves"] = moves
		"pairs":
			data["Pairs found"] = pairs_found
			data["Attempts"] = attempts
			data["Errors"] = pair_errors
		"math":
			data["Correct"] = correct
			data["Errors"] = incorrect
			data["Skipped"] = skipped
		"chimp":
			data["Successful rounds"] = chimp_success
			data["Errors"] = chimp_errors
			data["Maximum numbers"] = max_completed_count
	return data
