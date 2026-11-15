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

func wait_for_text(value: String) -> bool:
	for i in range(100):
		if contains_text(app, value):
			return true
		await create_timer(0.05).timeout
	return false

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	app = load("res://scenes/main_menu/main.tscn").instantiate()
	app.api_url = OS.get_environment("ZUMA_TEST_API")
	app.queue_path = OS.get_environment("ZUMA_TEST_QUEUE_DIR").path_join("history_pending")
	app.draft_path = OS.get_environment("ZUMA_TEST_QUEUE_DIR").path_join("history_survey.json")
	root.add_child(app)
	check(await wait_for_text("Server connected"), "profile loaded")
	await app.request(HTTPClient.METHOD_GET, "/test/paged_history")
	app.show_history()
	check(await wait_for_text("Records 1–10 of 23"), "first page")
	await process_frame
	app.content_scroll.scroll_vertical = 150
	check(app.content_scroll.scroll_vertical > 0, "long history can scroll")
	app.show_history_page(10)
	check(app.content_scroll.scroll_vertical == 0, "navigation resets scroll position")
	check(await wait_for_text("Records 11–20 of 23"), "second page")
	app.show_history_page(20)
	check(await wait_for_text("Records 21–23 of 23"), "last partial page")
	app.show_report("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
	check(await wait_for_text("Change in self-reported values"), "survey comparison shown")
	app.show_history()
	check(await wait_for_text("Records 21–23 of 23"), "return to same page")
	app.show_history_page(0)
	app.show_history_page(10)
	check(await wait_for_text("Records 11–20 of 23"), "newer request wins")
	app.select_profile(1)
	check(app.history_offset == 0, "profile change resets history offset")
	if not failed:
		print("HISTORY PAGINATION TEST PASSED")
	quit(1 if failed else 0)
