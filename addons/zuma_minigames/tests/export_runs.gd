extends SceneTree

const Generator = preload("res://addons/zuma_minigames/core/generator.gd")
const Session = preload("res://addons/zuma_minigames/core/rules.gd")

func _initialize() -> void:
	call_deferred("export_runs")

func export_runs() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var folder: String = args[0] if not args.is_empty() else "user://minigames_test_runs"
	DirAccess.make_dir_recursive_absolute(folder)
	var generator = Generator.new()
	for game in ["fifteen", "pairs", "math", "chimp"]:
		for difficulty in ["easy", "normal", "hard"]:
			var session = Session.new(game, difficulty, generator, 52)
			session.source = "synthetic"
			var t: int = 0
			match game:
				"fifteen":
					var blank: int = 15
					var solution: Array = []
					for index in session.initial.scramble:
						solution.append(blank)
						blank = index
					solution.reverse()
					for index in solution:
						if session.done:
							break
						t += 100
						assert(session.act(index, t))
				"pairs":
					t = session.config.preview_ms
					for symbol in range(session.config.pairs):
						var first: int = session.cards.find(symbol)
						var second: int = session.cards.find(symbol, first + 1)
						t += 100
						assert(session.act(first, t))
						t += 100
						assert(session.act(second, t))
				"math":
					while not session.done:
						var q: Dictionary = session.initial.questions[session.question_index]
						t += 100
						assert(session.act(q.options.find(Generator.answer(q)), t))
				"chimp":
					while not session.done:
						for cell in session.positions.duplicate():
							t += 100
							assert(session.act(cell, t))
						if not session.done:
							t += 100
							session.next_round(t)
			assert(session.done and session.result.status == "completed", game)
			var file := FileAccess.open(folder.path_join(game + "-" + difficulty + ".json"), FileAccess.WRITE)
			assert(file != null)
			file.store_string(JSON.stringify(session.result))
			file.close()
	print("EXPORTED 12 synthetic Godot runs to ", folder)
	quit(0)
