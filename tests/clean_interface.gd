extends SceneTree

func find_button(node: Node, title: String) -> Button:
	if node is Button and node.text == title:
		return node
	for child in node.get_children():
		var found := find_button(child, title)
		if found != null:
			return found
	return null

func find_name_field(node: Node) -> LineEdit:
	if node is LineEdit and node.placeholder_text == "Crew member name":
		return node
	for child in node.get_children():
		var found := find_name_field(child)
		if found != null:
			return found
	return null

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(5).timeout.connect(func(): quit(2))
	var view = load("res://addons/zuma_minigames/game_view.gd").new()
	root.add_child(view)
	await process_frame
	assert(view.help_label.visible, "Rules must be visible before Start")
	view._start()
	assert(not view.help_label.visible, "Repeated instructions clutter active play")
	view.cancel("user_exit")
	assert(not view.stats.visible, "Final counters must not duplicate the summary")
	view._restart()
	assert(view.stats.visible, "Restart must restore live counters")
	view.cancel("focus_lost")
	assert(view.interruption_overlay.visible)
	view.queue_free()
	await process_frame
	var app = load("res://scenes/main_menu/main.tscn").instantiate()
	app.api_url = "http://127.0.0.1:1"
	app.queue_path = "res://.godot/clean-ui/test-queue"
	app.draft_path = "res://.godot/clean-ui/test-draft.json"
	root.add_child(app)
	app.selected_profile = {"id": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "display_name": "Test"}
	app.show_home()
	await process_frame
	var name_field := find_name_field(app)
	assert(name_field != null and not name_field.is_visible_in_tree())
	find_button(app, "Manage profiles").pressed.emit()
	assert(name_field.is_visible_in_tree(), "Profile controls must stay accessible")
	assert(find_button(app, "Check local storage") == null, "Diagnostics should not clutter Overview")
	app.show_help()
	assert(find_button(app, "Check local storage") != null, "Diagnostics must remain accessible in Help")
	app.queue_free()
	await process_frame
	print("CLEAN_INTERFACE PASS rules, live counters, results and interruption")
	quit(0)
