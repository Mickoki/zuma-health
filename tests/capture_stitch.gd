extends SceneTree

var folder: String
var shots: int = 0

func _initialize() -> void:
	call_deferred("capture")

func shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(folder.path_join(name + ".png")) == OK)
	shots += 1

func capture() -> void:
	create_timer(60).timeout.connect(func(): quit(2))
	folder = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(folder)
	for size in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = size
		root.content_scale_size = size
		var tag := str(size.x)
		var app = load("res://scenes/main_menu/main.tscn").instantiate()
		app.api_url = "http://127.0.0.1:1"
		app.queue_path = folder.path_join("sessions-" + tag)
		app.draft_path = folder.path_join("drafts-" + tag + ".json")
		root.add_child(app)
		await process_frame
		await shot("home-" + tag)
		app.selected_profile = {"id": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "display_name": "Демонстрация дизайна"}
		app.drafts[app.selected_profile.id] = {"sleep_hours": 8.0, "fatigue": 0.0, "stress": 2.0, "mood": 7.0}
		app.show_survey()
		await shot("survey-" + tag)
		app.show_help()
		await shot("help-" + tag)
		app.show_minigames()
		var host = app.minigames_host
		assert(host.module.configure({"storage_dir": folder.path_join("games-" + tag), "source": "synthetic", "auto_upload": false}) == OK)
		await shot("hub-" + tag)
		host.level.select(2)
		for game in ["fifteen", "pairs", "math", "chimp"]:
			host._launch(game)
			await process_frame
			var view = host.module.view
			await shot(game + "-instructions-" + tag)
			view.start_button.pressed.emit()
			await shot(game + "-active-" + tag)
			for button in view.find_children("*", "Button", true, false):
				if button.is_visible_in_tree():
					var box: Rect2 = button.get_global_rect()
					assert(box.position.x >= 0 and box.position.y >= 0 and box.end.x <= size.x and box.end.y <= size.y, game + " clipped control " + str(box))
			view._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
			assert(view.interruption_overlay.visible and view.session.result.finish_reason == "focus_lost")
			await shot(game + "-interrupted-" + tag)
			host._back_to_menu()
		app.queue_free()
		await process_frame
	print("STITCH_VISUAL PASS ", shots, " screenshots at960/1280/1920; all hard controls visible")
	quit(0)
