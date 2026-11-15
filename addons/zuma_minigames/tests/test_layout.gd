extends SceneTree
const Demo = preload("res://addons/zuma_minigames/demo.tscn")

func _initialize() -> void:
	call_deferred("run_test")

func run_test() -> void:
	create_timer(5).timeout.connect(func(): quit(2))
	root.size = Vector2i(960, 540)
	root.content_scale_size = Vector2i(960, 540)
	var demo = Demo.instantiate()
	root.add_child(demo)
	demo.module.configure({"auto_upload": false, "source": "synthetic", "storage_dir": "user://layout_tests/" + str(Time.get_ticks_usec())})
	for game in ["pairs", "fifteen", "math", "chimp"]:
		demo.difficulty_picker.select(2)
		demo._launch(game)
		await process_frame
		demo.module.view.start_button.pressed.emit()
		await process_frame
		await process_frame
		for button in demo.module.view.find_children("*", "Button", true, false):
			if button.is_visible_in_tree():
				var box: Rect2 = button.get_global_rect()
				assert(box.position.y >= 0 and box.end.y <= 540 and box.position.x >= 0 and box.end.x <= 960, game + " clipped button: " + button.text + " " + str(box))
		demo.module.cancel_game()
	demo.queue_free()
	await process_frame
	print("MINIGAMES_LAYOUT PASS all hard game controls fit960x540")
	quit(0)
