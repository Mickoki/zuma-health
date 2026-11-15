extends SceneTree

var failed := false

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for size in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = size
		root.content_scale_size = size
		var app = load("res://scenes/main_menu/main.tscn").instantiate()
		app.api_url = "http://127.0.0.1:1"
		app.draft_path = "res://.godot/english/no-user-draft.json"
		app.queue_path = "res://.godot/english/layout-queue"
		root.add_child(app)
		await process_frame
		await process_frame
		var footer: Control = app.root_column.get_child(app.root_column.get_child_count() - 1)
		if footer.get_global_rect().end.y > size.y:
			failed = true
			push_error("English disclaimer is outside the window at " + str(size))
		for button in app.navigation_buttons.values():
			if button.get_global_rect().end.y > size.y:
				failed = true
				push_error("Navigation is outside the window: " + button.text)
		if TranslationServer.get_locale() != "en":
			failed = true
			push_error("The application locale is not English")
		app.queue_free()
		await process_frame
	if not failed:
		print("ENGLISH_LAYOUT PASS navigation, disclaimer and locale at960/1280/1920")
	quit(1 if failed else 0)
