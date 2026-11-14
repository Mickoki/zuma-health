extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var app = load("res://scenes/main_menu/main.tscn").instantiate()
	var mock_api := OS.get_environment("ZUMA_TEST_API")
	app.api_url = mock_api if not mock_api.is_empty() else "http://127.0.0.1:1"
	app.queue_path = ProjectSettings.globalize_path("res://.godot/capture_pending")
	app.draft_path = ProjectSettings.globalize_path("res://.godot/nonexistent_capture_draft.json")
	root.add_child(app)
	await create_timer(0.8).timeout
	var page := OS.get_environment("ZUMA_CAPTURE_PAGE")
	var warning_test_file := ""
	if mock_api.is_empty():
		app.set_connection_status("Сервер недоступен • запустите Go API")
	if page in ["survey", "game"]:
		app.profiles = [{"id": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "display_name": "Участник экипажа"}]
		app.selected_profile = app.profiles[0]
		app.profile_picker.clear()
		app.profile_picker.add_item("Участник экипажа")
		app.show_survey()
		if page == "game":
			app.game_scene_paths = {"reaction": "res://tests/fixtures/fake_game.tscn", "memory": "res://tests/fixtures/fake_game.tscn"}
			app.survey_inputs.sleep_hours.text = "8"
			app.survey_inputs.fatigue.text = "0"
			app.survey_inputs.stress.text = "2"
			app.survey_inputs.mood.text = "7"
			app.start_game_run()
	elif page == "history":
		app.show_history()
	elif page == "report":
		app.show_report("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
	elif page in ["trends", "trend-reaction", "trend-memory"]:
		app.show_trends()
		for i in range(100):
			if is_instance_valid(app.trend_metric) and app.trend_metric.is_inside_tree():
				break
			await create_timer(0.05).timeout
		if page in ["trend-reaction", "trend-memory"]:
			var metric_index := 5 if page == "trend-reaction" else 4
			app.trend_metric.select(metric_index)
			app.trend_metric.item_selected.emit(metric_index)
			for i in range(100):
				if not is_instance_valid(app.trend_loader):
					break
				await create_timer(0.05).timeout
	elif page == "queue_warning":
		warning_test_file = app.queue_path.path_join("capture-" + str(Time.get_ticks_usec()) + ".json.tmp")
		var file := FileAccess.open(warning_test_file, FileAccess.WRITE)
		file.store_string("test fixture")
		file.close()
		app.refresh_home_pending()
	await create_timer(0.8).timeout
	var img := root.get_texture().get_image()
	if img == null:
		push_error("Screenshot unavailable")
		quit(1)
		return
	var error := img.save_png(OS.get_environment("ZUMA_CAPTURE_PATH"))
	if page == "game":
		DirAccess.remove_absolute(app.draft_path)
	if not warning_test_file.is_empty():
		DirAccess.remove_absolute(warning_test_file)
	quit(0 if error == OK else 1)
