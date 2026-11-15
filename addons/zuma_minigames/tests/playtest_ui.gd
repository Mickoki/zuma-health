extends SceneTree
## Rendered QA uses actual GUI mouse events. All generated runs are synthetic.
const Demo = preload("res://addons/zuma_minigames/demo.tscn")
const Generator = preload("res://addons/zuma_minigames/core/generator.gd")
const Rules = preload("res://addons/zuma_minigames/core/rules.gd")
var output: String
var demo
var results: Array = []

func _initialize() -> void:
	call_deferred("run_test")

func click(button: Button) -> void:
	assert(not button.disabled and button.is_visible_in_tree(), "button is unavailable: " + button.name)
	var point: Vector2 = button.get_global_rect().get_center()
	assert(point.x >= 0 and point.y >= 0 and point.x < 960 and point.y < 540, "button outside viewport: " + str(point))
	if not button.has_meta("qa_clicks"):
		button.set_meta("qa_clicks", 0)
		button.pressed.connect(func(): button.set_meta("qa_clicks", button.get_meta("qa_clicks") + 1))
	var before: int = button.get_meta("qa_clicks")
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await process_frame
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = point
	down.global_position = point
	down.pressed = true
	Input.parse_input_event(down)
	Input.flush_buffered_events()
	await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = point
	up.global_position = point
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	await process_frame
	assert(button.get_meta("qa_clicks") == before + 1, "GUI did not receive exactly one click: " + button.name)

func snapshot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	assert(image.get_width() == 960 and image.get_height() == 540)
	assert(image.save_png(output.path_join(name + ".png")) == OK)

func run_test() -> void:
	Input.use_accumulated_input = false
	create_timer(300 if OS.get_cmdline_user_args().has("walkthrough") else 90).timeout.connect(func(): push_error("UI PLAYTEST TIMEOUT"); quit(2))
	root.size = Vector2i(960, 540)
	root.content_scale_size = Vector2i(960, 540)
	root.title = "Zuma — four-game playtest"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var walkthrough: bool = args.size() > 1 and args[1] == "walkthrough"
	output = args[0] if not args.is_empty() else "user://minigames_screenshots"
	DirAccess.make_dir_recursive_absolute(output)
	demo = Demo.instantiate()
	root.add_child(demo)
	var storage: String = output.path_join("outbox-" + Rules.uuid())
	assert(demo.module.configure({"storage_dir": storage, "owner_key": "qa-ui", "auto_upload": false, "source": "synthetic"}) == OK)
	var manifest := FileAccess.open(output.path_join("outbox-path.txt"), FileAccess.WRITE)
	manifest.store_string(storage)
	manifest.close()
	demo.module.run_finished.connect(func(payload: Dictionary): results.append(payload))
	await process_frame
	await snapshot("00-menu")
	for game in ["fifteen", "pairs", "math", "chimp"]:
		demo.difficulty_picker.select(1 if walkthrough else 2)
		await click(demo.find_child("Game_" + game, true, false))
		await snapshot(game + "-instructions")
		var view = demo.module.view
		await click(view.start_button)
		var session = view.session
		await snapshot(game + "-active")
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
					await click(view.grid.get_child(index))
			"pairs":
				while view.elapsed() < session.config.preview_ms + 20:
					await process_frame
				await snapshot("pairs-hidden")
				for symbol in range(session.config.pairs):
					var first: int = session.cards.find(symbol)
					var second: int = session.cards.find(symbol, first + 1)
					await click(view.grid.get_child(first))
					await click(view.grid.get_child(second))
			"math":
				while not session.done:
					var q: Dictionary = session.initial.questions[session.question_index]
					await click(view.grid.get_child(q.options.find(Generator.answer(q))))
			"chimp":
				var first_round: bool = true
				while not session.done:
					for cell in session.positions.duplicate():
						await click(view.grid.get_child(cell))
						if first_round and session.chimp_next == 1:
							for position in session.positions.slice(1):
								assert(view.grid.get_child(position).text.is_empty(), "number still visible")
							await snapshot("chimp-hidden")
							first_round = false
					if not session.done:
						await click(view.next_button)
		assert(session.done and session.result.status == "completed", game + ": " + str(session.result))
		await snapshot(game + "-result")
		var file := FileAccess.open(output.path_join(game + ".json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(session.result))
		file.close()
		var back: Button
		for candidate in view.find_children("*", "Button", true, false):
			if candidate.text == "Back" and candidate.is_visible_in_tree():
				back = candidate
		await click(back)
		assert(demo.menu.visible)
	assert(results.size() == 4)
	print("RENDERED_UI PASS four completed ", "normal walkthrough" if walkthrough else "hard games", " at960x540; output=", output)
	demo.queue_free()
	await process_frame
	quit(0)
