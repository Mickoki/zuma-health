extends SceneTree

const View = preload("res://addons/zuma_minigames/game_view.gd")
var failed := false

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func key(view, code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	view._unhandled_key_input(event)

func run() -> void:
	create_timer(10).timeout.connect(func(): quit(2))
	for game in ["fifteen", "pairs", "math", "chimp"]:
		var view = View.new()
		view.game_id = game
		root.add_child(view)
		await process_frame
		var count := [0]
		view.run_finished.connect(func(_payload): count[0] += 1)
		view._start()
		view.cancel("focus_lost")
		view.cancel("focus_lost")
		check(count[0] == 1, game + ": focus loss emitted twice")
		var overlay = view.get("interruption_overlay")
		check(overlay != null and overlay.visible, game + ": no interruption overlay")
		if not view.has_method("_unhandled_key_input"):
			check(false, "missing keyboard controls")
		else:
			var previous: String = view.session.client_run_id
			key(view, KEY_R)
			check(not view.session.done and view.session.client_run_id != previous, game + ": R did not restart")
			check(not overlay.visible, game + ": overlay still covers restarted game")
			if game == "math":
				key(view, KEY_1)
				check(view.session.question_index == 1, "math1 did not answer")
			key(view, KEY_ESCAPE)
			check(view.session.done, game + ": Escape did not abort")
			var retained_id: String = view.session.client_run_id
			root.remove_child(view)
			var hidden_parent := Control.new()
			root.add_child(hidden_parent)
			hidden_parent.add_child(view)
			hidden_parent.hide()
			var event := InputEventKey.new()
			event.keycode = KEY_R
			event.pressed = true
			Input.parse_input_event(event)
			Input.flush_buffered_events()
			await process_frame
			check(view.session.client_run_id == retained_id and view.session.done, game + ": hidden ancestor still accepts R")
			hidden_parent.queue_free()
		if is_instance_valid(view) and view.get_parent() == root:
			view.queue_free()
		await process_frame
	if not failed:
		print("REDESIGN_INPUT PASS all four games; focus overlay, one finish, R/Esc/1")
	quit(1 if failed else 0)
