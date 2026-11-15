extends SceneTree

var app: Control
var failed := false

func check(condition: bool, message: String) -> void:
	if not condition:
		push_error("TEST FAILED: " + message)
		failed = true

func contains(node: Node, value: String) -> bool:
	if (node is Label or node is Button) and value in node.text:
		return true
	for child in node.get_children():
		if contains(child, value):
			return true
	return false

func wait_text(node: Node, value: String) -> bool:
	for i in range(100):
		if contains(node, value):
			return true
		await create_timer(0.05).timeout
	return false

func find_button(node: Node, value: String) -> Button:
	if node is Button and value in node.text:
		return node
	for child in node.get_children():
		var found := find_button(child, value)
		if found != null:
			return found
	return null

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	app = load("res://scenes/main_menu/main.tscn").instantiate()
	app.api_url = OS.get_environment("ZUMA_TEST_API")
	app.queue_path = OS.get_environment("ZUMA_TEST_QUEUE_DIR").path_join("game_overview_sessions")
	app.draft_path = OS.get_environment("ZUMA_TEST_QUEUE_DIR").path_join("game_overview_drafts.json")
	root.add_child(app)
	for i in range(100):
		if not app.selected_profile.is_empty():
			break
		await create_timer(0.05).timeout
	await app.request(HTTPClient.METHOD_GET, "/test/game_data")
	app.show_home()
	check(await wait_text(app.home_game_latest_section, "Find the Pair"), "latest game appears on overview")
	check(contains(app.home_game_latest_section, "completed"), "outcome displayed")
	app.show_trends()
	for i in range(100):
		if is_instance_valid(app.trend_protocol) and app.trend_protocol.is_inside_tree():
			break
		await create_timer(0.05).timeout
	var index := -1
	for i in range(app.trend_protocol.item_count):
		if app.trend_protocol.get_item_metadata(i) == "zuma-game/pairs/normal/v1":
			index = i
	check(index >= 0, "game protocol selectable")
	if index >= 0:
		app.trend_protocol.select(index)
		app.trend_protocol.item_selected.emit(index)
		check(app.trend_chart.points.size() == 11, "game values separated by source and difficulty")
		check(app.trend_chart.points.back().value == 8, "latest saved survey shown")
		check("timestamp refers to the game" in app.trend_hint.text, "survey timing is explained")
		check("Missing values: 1" in app.trend_summary.text, "missing survey remains a gap")
		app.trend_metric.select(4)
		app.trend_metric.item_selected.emit(4)
		check(app.trend_chart.points.back().value == null and not is_instance_valid(app.trend_loader), "legacy game metric is not fabricated")
	app.show_minigames()
	var host = app.minigames_host
	check(is_instance_valid(host) and host.visible, "history accessible without saved survey")
	if is_instance_valid(host):
		check(await wait_text(host.history, "1–10 of 13"), "first game history page")
		host._launch("pairs")
		check(not host.game_area.visible and "save a survey" in host.status.text, "game requires a saved survey")
		var next := find_button(host.history, "Next")
		check(next != null and not next.disabled, "next page available")
		if next != null:
			next.pressed.emit()
			check(await wait_text(host.history, "11–13 of 13"), "second game history page")
	if not failed:
		print("GAME OVERVIEW TRENDS PASSED")
	quit(1 if failed else 0)
