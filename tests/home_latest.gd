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
	app.queue_path = OS.get_environment("ZUMA_TEST_QUEUE_DIR").path_join("latest_pending")
	app.draft_path = OS.get_environment("ZUMA_TEST_QUEUE_DIR").path_join("latest_survey.json")
	root.add_child(app)
	check(await wait_for_text("Server connected"), "profiles loaded")
	await app.request(HTTPClient.METHOD_GET, "/test/latest_race")
	app.show_home()
	app.select_profile(1)
	check(await wait_for_text("There are no saved check-ins for this profile yet"), "empty state for second profile")
	await create_timer(0.7).timeout
	check(not contains_text(app, "Memory: 3 of 4"), "late response from first profile is ignored")
	app.select_profile(0)
	check(await wait_for_text("Memory: 3 of 4"), "latest session appears for first profile")
	check(contains_text(app, "Demonstration data"), "synthetic source is visible")
	check(contains_text(app, "Open latest check-in report"), "latest report action available")
	if not failed:
		print("HOME LATEST TEST PASSED")
	quit(1 if failed else 0)
