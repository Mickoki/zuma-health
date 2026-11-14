extends SceneTree

var app: Control
var failed := false

func check(condition: bool, message: String) -> void:
	if not condition:
		push_error("TEST FAILED: " + message)
		failed = true

func contains_text(node: Node, text: String) -> bool:
	if (node is Label or node is Button) and text in node.text:
		return true
	for child in node.get_children():
		if contains_text(child, text):
			return true
	return false

func wait_for_text(text: String) -> bool:
	for i in range(100):
		if contains_text(app, text):
			return true
		await create_timer(0.05).timeout
	return false

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	app = load("res://scenes/main_menu/main.tscn").instantiate()
	app.api_url = OS.get_environment("ZUMA_TEST_API")
	app.queue_path = OS.get_environment("ZUMA_TEST_QUEUE_DIR").path_join("client_pending")
	app.draft_path = OS.get_environment("ZUMA_TEST_QUEUE_DIR").path_join("client_survey.json")
	DirAccess.remove_absolute(app.draft_path)
	root.add_child(app)
	check(await wait_for_text("Сервер подключён"), "profiles load over HTTP")
	check(app.profiles.size() == 1, "one profile returned")
	app.set_connection_status("Сервер недоступен • запустите Go API")
	await process_frame
	check(app.status_label.get_parent().size.y < 60, "long connection status does not expand header")
	check(app.status_label.tooltip_text == app.status_label.text, "full status available in tooltip")
	check("Конфликт" in app.pending_error_message({"error": "request_failed", "status": 409}), "conflict has actionable message")
	check("Сервер сохранил" in app.pending_error_message({"error": "saved_but_local_removal_failed"}), "saved session is not reported as failed")
	app.show_survey()
	check(app.survey_inputs.sleep_hours.text == "", "new survey starts empty")
	app.save_survey()
	check(not FileAccess.file_exists(app.draft_path), "incomplete survey is not saved")
	app.survey_inputs.sleep_hours.text = "8,5"
	app.survey_inputs.fatigue.text = "0"
	app.survey_inputs.stress.text = "2"
	app.survey_inputs.mood.text = "7"
	app.save_survey()
	check(FileAccess.file_exists(app.draft_path), "complete survey saved")
	check(app.drafts[app.selected_profile.id].sleep_hours == 8.5, "decimal comma parsed")
	app.show_survey()
	check(app.survey_inputs.sleep_hours.text == "8.5", "draft restored")
	app.survey_inputs.sleep_hours.text = "9"
	check(app.save_survey(), "existing draft replaced")
	check(app.drafts[app.selected_profile.id].sleep_hours == 9.0, "replacement saved")
	app.survey_inputs.sleep_hours.text = "10"
	app.survey_inputs.sleep_hours.text_changed.emit("10")
	app.refresh_profiles(app.selected_profile.id)
	await create_timer(0.3).timeout
	check(app.survey_inputs.sleep_hours.text == "10", "profile refresh preserves unsaved input")
	app.show_home()
	app.show_survey()
	check(app.survey_inputs.sleep_hours.text == "10", "navigation preserves unsaved input in memory")
	app.show_history()
	check(await wait_for_text("Открыть отчёт"), "history loaded")
	check(contains_text(app, "Память: 3 из 4"), "history shows raw memory result")
	var session_id := OS.get_environment("ZUMA_TEST_SESSION_ID")
	if session_id.is_empty():
		session_id = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
	app.show_report(session_id)
	check(await wait_for_text("Память:"), "report loaded")
	check(contains_text(app, "Изменение памяти"), "baseline comparison shown")
	var loaded: Dictionary = await app.request(HTTPClient.METHOD_GET, "/api/v1/sessions/%s/report" % session_id)
	check(loaded.ok and loaded.data.get("baseline_session_id") != null, "baseline available")
	if loaded.ok and loaded.data.get("baseline_session_id") != null:
		app.open_baseline(session_id, str(loaded.data.baseline_session_id))
		check(await wait_for_text("Память:"), "baseline report loaded")
		check(app.report_trail.size() == 1, "report trail records origin")
		app.back_to_report()
		check(await wait_for_text("Изменение памяти"), "returned to original report")
		check(app.report_trail.is_empty(), "return removes trail entry")
	var revision: int = app.page_revision
	var message := Label.new()
	app.content.add_child(message)
	app.generate_explanation(session_id, revision, message)
	check(await wait_for_text("Локальная модель недоступна"), "unavailable explanation shown")
	app.profiles.append({"id": "cccccccccccccccccccccccccccccccc", "display_name": "Another crew"})
	app.select_profile(1)
	check(app.current_page == "history", "switching profile closes report")
	DirAccess.remove_absolute(app.draft_path)
	if not failed:
		print("CLIENT INTEGRATION TEST PASSED")
	quit(1 if failed else 0)
