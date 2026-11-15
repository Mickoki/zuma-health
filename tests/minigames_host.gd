extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var app = load("res://scenes/main_menu/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var nav: Control = app.profile_picker.get_parent()
	assert(app.profile_picker.get_global_rect().end.x <= nav.get_global_rect().end.x + 1, "navigation exceeds available width")
	app.selected_profile = {"id": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "display_name": "Test"}
	app.drafts[app.selected_profile.id] = {"sleep_hours": 8.0, "fatigue": 0.0, "stress": 2.0, "mood": 7.0}
	app.show_minigames()
	var host = app.minigames_host
	assert(host.visible and host.profile_id == app.selected_profile.id)
	assert(host.module.options.owner_key == "profile:" + app.selected_profile.id)
	assert(host.module.configure({"storage_dir": "user://host-test/" + str(Time.get_ticks_usec()), "auto_upload": false}) == OK)
	for game in ["fifteen", "pairs", "math", "chimp"]:
		host._launch(game)
		await process_frame
		assert(host.game_area.visible and host.module.view.game_id == game)
		host.module.view.start_button.pressed.emit()
		host.module.cancel_game()
		host._back_to_menu()
	assert(host.module.pending_count() == 4)
	for record in host.module.outbox.pending():
		assert(record.payload.survey.sleep_hours == 8 and record.payload.survey.fatigue == 0 and record.payload.survey.stress == 2 and record.payload.survey.mood == 7)
	host._close()
	assert(not host.visible and host.module.pending_count() == 4)
	app.queue_free()
	await process_frame
	print("MINIGAMES_HOST PASS")
	quit()
