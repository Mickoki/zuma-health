extends SceneTree

var app: Control
var failed := false

func check(condition: bool, message: String) -> void:
	if not condition:
		push_error("TEST FAILED: " + message)
		failed = true

func find_button(node: Node, title: String) -> Button:
	if node is Button and node.text == title:
		return node
	for child in node.get_children():
		var found := find_button(child, title)
		if found != null:
			return found
	return null

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
	app.queue_path = OS.get_environment("ZUMA_TEST_QUEUE_DIR").path_join("help_pending")
	app.draft_path = OS.get_environment("ZUMA_TEST_QUEUE_DIR").path_join("help_survey.json")
	root.add_child(app)
	for i in range(100):
		if app.profiles.size() >= 2:
			break
		await create_timer(0.05).timeout
	check(app.profiles.size() >= 2, "profiles loaded")
	app.show_survey()
	app.survey_inputs.sleep_hours.text = "7,5"
	app.survey_inputs.sleep_hours.text_changed.emit("7,5")
	find_button(app.content, "How do I complete the survey?").pressed.emit()
	check(app.current_page == "help", "survey opens contextual guide")
	check(contains_text(app, "does not store the sleep period separately"), "guide explains sleep-period limitation")
	check(contains_text(app, "have not undergone confirmed clinical validation"), "guide describes validation limit")
	check(contains_text(app, "copy is attached to every new game"), "guide describes survey and game flow")
	check(contains_text(app, "mission protocol"), "guide offers a next step without prescribing treatment")
	check(find_button(app.content, "[1] NASA: sleep and performance ↗") != null, "NASA sleep source provided")
	find_button(app.content, "Return").pressed.emit()
	check(app.current_page == "survey" and app.survey_inputs.sleep_hours.text == "7,5", "return preserves unsaved survey")
	app.show_report("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
	check(await wait_for_text("How do I read the results?"), "report loaded")
	find_button(app.content, "How do I read the results?").pressed.emit()
	check(app.current_page == "help", "report opens guide")
	find_button(app.content, "Return").pressed.emit()
	check(await wait_for_text("How do I read the results?"), "guide returns to report")
	find_button(app.content, "How do I read the results?").pressed.emit()
	app.select_profile(1)
	find_button(app.content, "Return").pressed.emit()
	check(app.current_page == "home", "profile change prevents return to another profile report")
	if not failed:
		print("HELP PAGE TEST PASSED")
	quit(1 if failed else 0)
