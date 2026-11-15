extends SceneTree

var app: Control
var failed := false

func check(condition: bool, message: String) -> void:
	if not condition:
		push_error("TEST FAILED: " + message)
		failed = true

func find_name_input(node: Node) -> LineEdit:
	if node is LineEdit and node.placeholder_text == "Crew member name":
		return node
	for child in node.get_children():
		var found := find_name_input(child)
		if found != null:
			return found
	return null

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	app = load("res://scenes/main_menu/main.tscn").instantiate()
	app.api_url = OS.get_environment("ZUMA_TEST_API")
	app.queue_path = OS.get_environment("ZUMA_TEST_QUEUE_DIR").path_join("race_pending")
	app.draft_path = OS.get_environment("ZUMA_TEST_QUEUE_DIR").path_join("profile_race_survey.json")
	root.add_child(app)
	for i in range(100):
		if not app.selected_profile.is_empty():
			break
		await create_timer(0.05).timeout
	check(not app.selected_profile.is_empty(), "initial profile loaded")
	app.profiles.append({"id": "cccccccccccccccccccccccccccccccc", "display_name": "Another crew"})
	await app.request(HTTPClient.METHOD_GET, "/test/slow_profiles")
	app.refresh_profiles(app.selected_profile.id)
	app.select_profile(1)
	app.show_survey()
	app.survey_inputs.sleep_hours.text = "6"
	app.survey_inputs.sleep_hours.text_changed.emit("6")
	await create_timer(0.6).timeout
	check(app.selected_profile.id == "cccccccccccccccccccccccccccccccc", "late refresh preserves newer selection")
	check(app.survey_inputs.sleep_hours.text == "6", "late refresh preserves input on selected profile")
	app.show_home()
	app.refresh_profiles(app.selected_profile.id)
	var name_input := find_name_input(app.content)
	name_input.text = "New name"
	await create_timer(0.6).timeout
	check(is_instance_valid(name_input) and name_input.text == "New name", "refresh preserves profile name input")
	if not failed:
		print("PROFILE RACE TEST PASSED")
	quit(1 if failed else 0)
