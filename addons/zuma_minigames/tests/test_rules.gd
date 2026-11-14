extends SceneTree

const Generator = preload("res://addons/zuma_minigames/core/generator.gd")
const Session = preload("res://addons/zuma_minigames/core/rules.gd")
var failures: int = 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run_tests")

func run_tests() -> void:
	var generator = Generator.new()
	for game in ["fifteen", "pairs", "math", "chimp"]:
		for difficulty in ["easy", "normal", "hard"]:
			var first: Dictionary = generator.generate(game, difficulty, 42)
			var second: Dictionary = generator.generate(game, difficulty, 42)
			if game != "chimp":
				check(JSON.stringify(first) != JSON.stringify(second), "immediate repeat: " + game)
		var session = Session.new(game, "easy", generator, 17)
		check(not session.done, "started completed")
		session.abort("user_exit", 0)
		check(session.result.status == "aborted", "abort not recorded")
		var before: String = JSON.stringify(session.result)
		session.abort("user_exit", 10)
		check(JSON.stringify(session.result) == before, "duplicate finish mutated result")
	var pairs = Session.new("pairs", "easy", generator, 123)
	check(not pairs.act(0, 0), "pairs accepted click during preview")
	var card: int = pairs.initial.cards[0]
	var match_index: int = pairs.initial.cards.find(card, 1)
	check(pairs.act(0, 5000), "first flip rejected")
	check(not pairs.act(0, 5001), "same card selected twice")
	check(pairs.act(match_index, 5002), "matching flip rejected")
	check(pairs.pairs_found == 1, "pair not found")
	var math = Session.new("math", "easy", generator, 10)
	math.advance(8000)
	check(math.skipped == 1, "deadline did not skip question")
	var chimp = Session.new("chimp", "easy", generator, 23)
	check(not chimp.hidden, "chimp hidden before first click")
	chimp.act(chimp.positions[0], 100)
	check(chimp.hidden, "chimp numbers did not hide")
	for i in range(1, 5):
		chimp.act(chimp.positions[i], 100 + i * 100)
	check(chimp.round_pending and chimp.chimp_count == 6, "chimp did not advance")
	chimp.next_round(700)
	check(not chimp.hidden and chimp.positions.size() == 6, "next chimp layout wrong")
	var counts: Dictionary = generator.pool_sizes()
	check(counts == {"easy": 992, "normal": 6042, "hard": 23880}, "math pool sizes wrong")
	print("MINIGAMES_RULES failures=", failures)
	quit(1 if failures else 0)
