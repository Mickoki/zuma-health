extends SceneTree

var app: Control
var failed := false

func check(condition: bool, message: String) -> void:
	if not condition:
		push_error("TEST FAILED: " + message)
		failed = true

func contains_text(node: Node, value: String) -> bool:
	if (node is Label or node is Button) and value in node.text:
		return true
	for child in node.get_children():
		if contains_text(child, value):
			return true
	return false

func write_text(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(value)
	file.close()

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var temp_dir := OS.get_environment("ZUMA_TEST_QUEUE_DIR")
	app = load("res://scenes/main_menu/main.tscn").instantiate()
	app.api_url = OS.get_environment("ZUMA_TEST_API")
	app.queue_path = temp_dir.path_join("health_pending")
	app.draft_path = temp_dir.path_join("health_survey.json")
	root.add_child(app)
	for i in range(100):
		if not app.selected_profile.is_empty():
			break
		await create_timer(0.05).timeout
	check(not app.selected_profile.is_empty(), "profile loaded")
	var queue: Node = app.session_queue
	var empty: Dictionary = queue.inspect_queue(app.selected_profile.id)
	check(not empty.directory_error and empty.problem_count == 0, "new queue is healthy")
	var survey := {"sleep_hours": 8, "fatigue": 0, "stress": 2, "mood": 7}
	var reaction := {"protocol_version": "reaction-memory-v1", "trials": [{"outcome": "valid", "reaction_ms": 230}]}
	var memory := {"protocol_version": "reaction-memory-v1", "correct": 3, "total": 4}
	check(queue.enqueue(app.selected_profile.id, survey, reaction, memory).ok, "first profile record queued")
	check(queue.enqueue("cccccccccccccccccccccccccccccccc", survey, reaction, memory).ok, "second profile record queued")
	var broken_path: String = app.queue_path.path_join("broken.json")
	var temp_path: String = app.queue_path.path_join("interrupted.json.tmp")
	var incomplete_path: String = app.queue_path.path_join("123e4567-e89b-42d3-a456-426614174000.json")
	write_text(broken_path, "{bad json")
	write_text(temp_path, "partial data")
	write_text(incomplete_path, JSON.stringify({"profile_id": app.selected_profile.id, "payload": {"client_session_id": "123e4567-e89b-42d3-a456-426614174000", "performed_at": "2026-01-02T12:00:00Z", "source": "observed"}}))
	var audit: Dictionary = queue.inspect_queue(app.selected_profile.id)
	check(audit.problem_count == 3 and audit.records.size() == 1, "unreadable, incomplete and interrupted files reported; other profile kept separate")
	app.show_home()
	check(contains_text(app.home_queue_warning, "не удалось проверить: 3"), "warning shown on overview")
	await app.request(HTTPClient.METHOD_GET, "/test/malformed_next_send")
	await app.send_pending()
	check(queue.pending(app.selected_profile.id).size() == 1, "malformed success response preserves queued record")
	await app.send_pending()
	check(queue.pending(app.selected_profile.id).is_empty(), "valid record can be retried and sent")
	check(queue.pending("cccccccccccccccccccccccccccccccc").size() == 1, "other profile record remains")
	check("непроверенные" in app.status_label.text, "success does not hide queue warning")
	check(FileAccess.get_file_as_string(broken_path) == "{bad json" and FileAccess.get_file_as_string(temp_path) == "partial data", "problem files remain unchanged")
	app.selected_profile = {}
	app.show_home()
	check(contains_text(app.home_queue_warning, "не удалось проверить: 3"), "warning visible without a selected profile")
	var blocked_path := temp_dir.path_join("queue_is_file")
	write_text(blocked_path, "keep")
	var original_dir: String = queue.queue_dir
	queue.queue_dir = blocked_path
	check(queue.inspect_queue("").directory_error, "unavailable queue directory is reported")
	queue.queue_dir = original_dir
	check(FileAccess.get_file_as_string(blocked_path) == "keep", "unavailable path is not modified")
	if not failed:
		print("QUEUE HEALTH TEST PASSED")
	quit(1 if failed else 0)
