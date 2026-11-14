extends SceneTree

var failed := false
var app: Control

func check(condition: bool, message: String) -> void:
	if not condition:
		push_error("TEST FAILED: " + message)
		failed = true

func wait_for_profile() -> void:
	for i in range(100):
		if not app.selected_profile.is_empty():
			return
		await create_timer(0.05).timeout

func fixture() -> Node:
	return app.content.get_node_or_null("FakeGame")

func find_button(node: Node, title: String) -> Button:
	if node is Button and node.text == title:
		return node
	for child in node.get_children():
		var found := find_button(child, title)
		if found != null:
			return found
	return null

func find_name_input(node: Node) -> LineEdit:
	if node is LineEdit and node.placeholder_text == "Имя участника":
		return node
	for child in node.get_children():
		var found := find_name_input(child)
		if found != null:
			return found
	return null

func wait_for_page(page: String) -> bool:
	for i in range(100):
		if app.current_page == page and not app.sending_pending:
			return true
		await create_timer(0.05).timeout
	return false

func wait_for_send() -> void:
	for i in range(100):
		if not app.sending_pending:
			return
		await create_timer(0.05).timeout

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	app = load("res://scenes/main_menu/main.tscn").instantiate()
	app.api_url = OS.get_environment("ZUMA_TEST_API")
	app.queue_path = OS.get_environment("ZUMA_TEST_QUEUE_DIR").path_join("pending")
	app.draft_path = OS.get_environment("ZUMA_TEST_QUEUE_DIR").path_join("survey.json")
	app.game_scene_paths = {"reaction": "res://tests/fixtures/fake_game.tscn", "memory": "res://tests/fixtures/fake_game.tscn"}
	root.add_child(app)
	app.session_queue.queue_dir = OS.get_environment("ZUMA_TEST_QUEUE_DIR").path_join("pending")
	await wait_for_profile()
	check(not app.selected_profile.is_empty(), "profile loaded")
	app.show_survey()
	app.survey_inputs.sleep_hours.text = "8"
	app.survey_inputs.fatigue.text = "0"
	app.survey_inputs.stress.text = "2"
	app.survey_inputs.mood.text = "7"
	app.start_game_run()
	check(app.current_page == "game" and fixture() != null, "reaction scene launched")
	check(app.profile_picker.disabled and app.navigation_buttons.home.disabled and app.navigation_buttons.history.disabled and app.navigation_buttons.help.disabled, "navigation disabled during game")
	await process_frame
	await process_frame
	check(fixture().size.y >= 360 and fixture().size.x > 0, "plain Control game receives visible area")
	fixture().cancelled.emit()
	await process_frame
	check(app.current_page == "survey" and app.session_queue.pending(app.selected_profile.id).is_empty(), "cancellation does not create a session")
	check(not app.profile_picker.disabled and not app.navigation_buttons.home.disabled, "navigation restored after cancellation")
	app.game_scene_paths.reaction = "res://tests/fixtures/tall_game.tscn"
	app.start_game_run()
	await process_frame
	await process_frame
	check(fixture().size.y >= 620, "larger game minimum height is preserved")
	fixture().cancelled.emit()
	await process_frame
	app.game_scene_paths.reaction = "res://tests/fixtures/fake_game.tscn"
	app.start_game_run()
	await process_frame
	await process_frame
	var target: Button = fixture().get_node("TestAction")
	var point := target.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	var mouse_down := InputEventMouseButton.new()
	mouse_down.button_index = MOUSE_BUTTON_LEFT
	mouse_down.position = point
	mouse_down.global_position = point
	mouse_down.pressed = true
	root.push_input(mouse_down, true)
	var mouse_up := InputEventMouseButton.new()
	mouse_up.button_index = MOUSE_BUTTON_LEFT
	mouse_up.position = point
	mouse_up.global_position = point
	mouse_up.pressed = false
	root.push_input(mouse_up, true)
	await process_frame
	check(app.current_page == "game" and app.active_run.has("reaction"), "mouse input reaches embedded game")
	fixture().cancelled.emit()
	await process_frame
	app.start_game_run()
	fixture().completed.emit({"protocol_version": "other", "trials": [{"outcome": "valid", "reaction_ms": 250}]})
	await process_frame
	check(app.current_page == "game_result" and app.session_queue.pending(app.selected_profile.id).is_empty(), "incompatible protocol rejected")
	app.show_survey()
	app.start_game_run()
	fixture().completed.emit({"protocol_version": "reaction-memory-v1", "trials": [{"outcome": "valid", "reaction_ms": 250}]})
	await process_frame
	check(app.current_page == "game" and app.active_run.has("reaction"), "memory scene follows reaction")
	app.profiles.append({"id": "cccccccccccccccccccccccccccccccc", "display_name": "Another crew"})
	app.select_profile(1)
	check(app.current_page == "game" and app.active_run.has("reaction") and app.selected_profile.id == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "profile cannot change during run")
	await app.request(HTTPClient.METHOD_GET, "/test/slow_profiles")
	app.refresh_profiles("cccccccccccccccccccccccccccccccc")
	await create_timer(0.6).timeout
	check(app.current_page == "game" and app.active_run.has("reaction") and app.selected_profile.id == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "late profile refresh does not interrupt run")
	fixture().cancelled.emit()
	await process_frame
	app.select_profile(1)
	check(app.current_page == "survey" and app.selected_profile.id == "cccccccccccccccccccccccccccccccc", "profile can change after cancellation")
	app.select_profile(0)
	app.start_game_run()
	fixture().completed.emit({"protocol_version": "reaction-memory-v1", "trials": [{"outcome": "valid", "reaction_ms": 250}]})
	await process_frame
	var actual_queue: Node = app.session_queue
	var failing_queue = load("res://tests/fixtures/failing_queue.gd").new()
	app.add_child(failing_queue)
	app.session_queue = failing_queue
	fixture().completed.emit({"protocol_version": "reaction-memory-v1", "correct": 3, "total": 4})
	await process_frame
	check(app.current_page == "game_result" and not app.active_run.is_empty(), "storage failure retains completed results in memory")
	check(app.profile_picker.disabled and app.navigation_buttons.home.disabled, "storage failure protects unsaved results")
	var retry_save := find_button(app.content, "Повторить сохранение")
	check(retry_save != null, "storage failure offers retry")
	app.session_queue = actual_queue
	failing_queue.queue_free()
	retry_save.pressed.emit()
	await process_frame
	var pending: Array = app.session_queue.pending(app.selected_profile.id)
	check(app.current_page == "game_result" and pending.size() == 1, "complete run enters queue")
	check(not app.profile_picker.disabled and not app.navigation_buttons.home.disabled, "navigation restored after completed result is queued")
	if pending.size() == 1:
		check(pending[0].payload.survey.sleep_hours == 8 and pending[0].payload.reaction.trials[0].reaction_ms == 250, "queue contains captured results")
	var send_button := find_button(app.content, "Отправить и открыть отчёт")
	check(send_button != null, "completion screen offers direct report")
	await app.request(HTTPClient.METHOD_GET, "/test/fail_next_send")
	send_button.pressed.emit()
	await wait_for_send()
	check(app.current_page == "game_result" and app.session_queue.pending(app.selected_profile.id).size() == 1, "failed send keeps result and retry screen")
	send_button.pressed.emit()
	check(await wait_for_page("report"), "successful retry opens report")
	check(app.session_queue.pending(app.selected_profile.id).is_empty(), "successful retry removes queued record")
	app.show_survey()
	app.game_scene_paths.reaction = "res://tests/fixtures/instant_reaction.tscn"
	app.start_game_run()
	await process_frame
	check(app.current_page == "game" and fixture() != null and app.active_run.has("reaction"), "completion emitted in ready safely advances to memory")
	fixture().cancelled.emit()
	await process_frame
	check(app.session_queue.pending(app.selected_profile.id).is_empty(), "cancel after immediate result does not add session")
	app.game_scene_paths.reaction = "res://tests/fixtures/fake_game.tscn"
	app.start_game_run()
	fixture().completed.emit({"protocol_version": "reaction-memory-v1", "trials": [{"outcome": "valid", "reaction_ms": 250}]})
	await process_frame
	fixture().completed.emit({"protocol_version": "reaction-memory-v1", "correct": 3, "total": 4})
	await process_frame
	await app.request(HTTPClient.METHOD_GET, "/test/delay_next_send")
	find_button(app.content, "Отправить и открыть отчёт").pressed.emit()
	app.show_home()
	var name_input := find_name_input(app.content)
	name_input.text = "Новый участник"
	check(find_button(app.content, "Отправить сохранённые проверки") != null, "pending item initially shown")
	await wait_for_send()
	check(app.current_page == "home", "late send response does not change current screen")
	check(app.session_queue.pending(app.selected_profile.id).is_empty(), "send completes after navigation")
	check(find_button(app.content, "Отправить сохранённые проверки") == null, "pending display updated after send")
	check(is_instance_valid(name_input) and name_input.text == "Новый участник", "pending refresh preserves profile input")
	if not failed:
		print("GAME FLOW TEST PASSED")
	quit(1 if failed else 0)
