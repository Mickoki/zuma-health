extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var app = load("res://scenes/main_menu/main.tscn").instantiate()
	app.api_url = OS.get_environment("ZUMA_TEST_API")
	if app.api_url.is_empty():
		app.api_url = "http://127.0.0.1:1"
	app.draft_path = "user://capture-drafts.json"
	app.queue_path = "user://capture-sessions"
	root.add_child(app)
	await create_timer(0.3).timeout
	app.selected_profile = {"id": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "display_name": "Тестовый участник"}
	app.drafts[app.selected_profile.id] = {"sleep_hours": 8.0, "fatigue": 0.0, "stress": 2.0, "mood": 7.0}
	app.show_minigames()
	var host = app.minigames_host
	var kind := OS.get_environment("ZUMA_CAPTURE_GAME")
	if not kind.is_empty():
		host._launch(kind)
		await process_frame
		host.module.view.start_button.pressed.emit()
	await create_timer(1.0).timeout
	RenderingServer.force_draw()
	await process_frame
	var img := root.get_texture().get_image()
	if img == null:
		push_error("Screenshot unavailable")
		quit(1)
		return
	var error := img.save_png(OS.get_environment("ZUMA_CAPTURE_PATH"))
	quit(0 if error == OK else 1)
