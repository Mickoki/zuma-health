extends SceneTree

const Module = preload("res://addons/zuma_minigames/module.gd")
var results: Array = []

func _initialize() -> void:
	call_deferred("run_tests")

func run_tests() -> void:
	var module = Module.new()
	root.add_child(module)
	assert(module.configure({"storage_dir": "user://module_tests/" + str(Time.get_ticks_usec()), "source": "synthetic", "auto_upload": false}) == OK)
	module.run_finished.connect(func(payload: Dictionary): results.append(payload))
	for game in ["fifteen", "pairs", "math", "chimp"]:
		assert(module.start_game(game, "easy") == OK)
		await process_frame
		assert(module.view.session == null)
		module.view.start_button.pressed.emit()
		assert(module.view.session != null)
		assert(module.view.grid.get_child_count() == {"fifteen": 16, "pairs": 18, "math": 4, "chimp": 40}[game])
		module.cancel_game()
		assert(results.size() == ["fifteen", "pairs", "math", "chimp"].find(game) + 1)
		assert(results.back().status == "aborted")
	module.start_game("pairs", "hard")
	await process_frame
	module.view.start_button.pressed.emit()
	assert(module.view.grid.get_child_count() == 36)
	module.view.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	assert(results.size() == 5 and results.back().finish_reason == "focus_lost")
	module.cancel_game()
	assert(results.size() == 5)
	module.queue_free()
	await process_frame
	print("MINIGAMES_MODULE PASS")
	quit(0)
