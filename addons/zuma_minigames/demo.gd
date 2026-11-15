extends Control

const Module = preload("res://addons/zuma_minigames/module.gd")
const Rules = preload("res://addons/zuma_minigames/core/rules.gd")
var module
var menu: ScrollContainer
var status: Label
var queue_label: Label
var profile_picker: OptionButton
var profile_name: LineEdit
var difficulty_picker: OptionButton
var profiles: Array = []
var selected_profile: String = ""
var _local_owner: String = "demo-local"

func _ready() -> void:
	TranslationServer.set_locale("en")
	theme = preload("res://addons/zuma_minigames/theme.tres")
	add_child(preload("res://addons/zuma_minigames/ui/orbit_background.gd").new())
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 14)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var brand := Label.new()
	brand.text = "ZUMA / MINI-GAMES"
	brand.add_theme_font_size_override("font_size", 24)
	header.add_child(brand)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	queue_label = Label.new()
	header.add_child(queue_label)
	menu = ScrollContainer.new()
	menu.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(menu)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	menu.add_child(content)
	var intro := Label.new()
	intro.text = "Choose a game"
	intro.tooltip_text = "Games work offline. Unsent results are saved locally."
	intro.add_theme_font_size_override("font_size", 23)
	content.add_child(intro)
	var level_row := HBoxContainer.new()
	content.add_child(level_row)
	var level_label := Label.new()
	level_label.text = "Difficulty: "
	level_row.add_child(level_label)
	difficulty_picker = OptionButton.new()
	for title in ["Easy", "Normal", "Hard"]:
		difficulty_picker.add_item(title)
	difficulty_picker.select(1)
	level_row.add_child(difficulty_picker)
	var games := GridContainer.new()
	games.columns = 2
	games.add_theme_constant_override("h_separation", 12)
	games.add_theme_constant_override("v_separation", 12)
	content.add_child(games)
	for item in [["fifteen", "Fifteen Puzzle\nSolve the 4×4 board"], ["pairs", "Find the Pair\nMemorize the cards"], ["math", "Speed Math\nBeat the timer"], ["chimp", "Remember the Numbers\nRecall the order"]]:
		var game_button := Button.new()
		game_button.name = "Game_" + item[0]
		game_button.text = item[1]
		game_button.custom_minimum_size = Vector2(310, 72)
		game_button.pressed.connect(_launch.bind(item[0]))
		games.add_child(game_button)
	var profile_row := HBoxContainer.new()
	content.add_child(profile_row)
	profile_picker = OptionButton.new()
	profile_picker.custom_minimum_size.x = 230
	profile_picker.add_item("No server profile")
	profile_picker.item_selected.connect(_select_profile)
	profile_row.add_child(profile_picker)
	profile_name = LineEdit.new()
	profile_name.placeholder_text = "New profile name"
	profile_name.max_length = 100
	profile_name.custom_minimum_size.x = 210
	profile_row.add_child(profile_name)
	_button(profile_row, "Create profile", _create_profile)
	_button(profile_row, "Refresh", _load_profiles)
	var delivery_row := HBoxContainer.new()
	content.add_child(delivery_row)
	_button(delivery_row, "Link local results", _bind_local)
	_button(delivery_row, "Retry upload", func(): module.retry_pending())
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", 15)
	status.text = ""
	status.tooltip_text = "Select a profile for new games. Earlier local results are linked using a separate button."
	content.add_child(status)
	var note := Label.new()
	note.text = "Task results are not a medical diagnosis."
	note.add_theme_font_size_override("font_size", 14)
	content.add_child(note)
	module = Module.new()
	module.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(module)
	module.visible = false
	module.delivery_changed.connect(_delivery)
	module.module_exit_requested.connect(_show_menu)
	module.run_finished.connect(func(_payload): _refresh_count())
	_prepare_local_owner()
	module.configure({"owner_key": _local_owner})
	_refresh_count()
	_load_profiles()

func _launch(game: String) -> void:
	var displayed: String = "" if profile_picker.selected <= 0 else profiles[profile_picker.selected - 1].id
	if displayed != module.options.profile_id:
		_restore_selection()
		status.text = "The selected profile was not applied. Select it again before playing."
		return
	var error: Error = module.start_game(game, ["easy", "normal", "hard"][difficulty_picker.selected])
	if error != OK:
		status.text = "Could not open the game: " + str(error)
		return
	menu.visible = false
	module.visible = true

func _show_menu() -> void:
	module.visible = false
	menu.visible = true
	_refresh_count()

func _load_profiles() -> void:
	var response: Dictionary = await module.transport.request(module.options.base_url, "/api/v1/profiles?limit=100", HTTPClient.METHOD_GET, null, 3.0)
	if not response.ok:
		status.text = "Server unavailable. Games still work and results are saved locally."
		return
	profiles = response.data.get("items", [])
	profile_picker.clear()
	profile_picker.add_item("No server profile")
	for profile in profiles:
		profile_picker.add_item(profile.display_name)
	_restore_selection()
	status.text = "Server available. Select a profile for new games."

func _select_profile(index: int) -> void:
	var profile: String = "" if index == 0 else profiles[index - 1].id
	if profile.is_empty():
		_prepare_local_owner()
	var owner: String = _local_owner if profile.is_empty() else "profile:" + profile
	var error: Error = module.configure({"owner_key": owner, "profile_id": profile})
	if error != OK:
		_restore_selection()
		status.text = "Could not switch profiles (code %d). Wait for the upload or resolve the write error." % error
		return
	selected_profile = profile
	status.text = "Profile selected for new games. Existing records were not reassigned."

func _create_profile() -> void:
	if profile_name.text.strip_edges().is_empty():
		status.text = "Enter a profile name."
		return
	var response: Dictionary = await module.transport.request(module.options.base_url, "/api/v1/profiles", HTTPClient.METHOD_POST, {"display_name": profile_name.text.strip_edges()}, 3.0)
	if not response.ok:
		status.text = "Profile not created: " + str(response.get("error", "error"))
		return
	var created_id: String = response.data.id
	var error: Error = module.configure({"owner_key": "profile:" + created_id, "profile_id": created_id})
	if error == OK:
		selected_profile = created_id
	else:
		_restore_selection()
	await _load_profiles()
	status.text = "Profile created and selected." if error == OK else "Profile created but not selected (code %d). The previous profile remains active." % error

func _bind_local() -> void:
	if selected_profile.is_empty():
		status.text = "Select a server profile first."
		return
	var error: Error = module.bind_owner(_local_owner, selected_profile)
	if error != OK:
		status.text = "The local owner is already linked to another profile or the queue is unavailable (code %d)." % error
		return
	status.text = "Local records were explicitly linked to the selected profile."
	_prepare_local_owner() # Future no-profile runs must never inherit this binding.
	module.retry_pending()

func _restore_selection() -> void:
	selected_profile = module.options.profile_id
	profile_picker.select(0)
	if selected_profile.is_empty():
		return
	for i in range(profiles.size()):
		if profiles[i].id == selected_profile:
			profile_picker.select(i + 1)
			return
	profiles.append({"id": selected_profile, "display_name": "Current profile " + selected_profile.left(8)})
	profile_picker.add_item(profiles.back().display_name)
	profile_picker.select(profiles.size())

func _prepare_local_owner() -> void:
	var path: String = module.outbox.root_dir.path_join("demo-owner.json")
	var saved: Dictionary = module.outbox.read_dict(path)
	if saved.get("owner_key") is String and saved.owner_key.begins_with("demo-local") and saved.owner_key.length() <= 128:
		_local_owner = saved.owner_key
	if module.outbox.bindings.has(_local_owner):
		_local_owner = "demo-local:" + Rules.uuid()
	var error: Error = module.outbox._write(path, {"owner_key": _local_owner}, true)
	if error != OK and status != null:
		status.text = "Could not save the local owner. Results will not be reassigned."

func _delivery(_id: String, state: String, message: String) -> void:
	status.text = message.left(250)
	queue_label.tooltip_text = state + ": " + message
	_refresh_count()

func _refresh_count() -> void:
	queue_label.text = "Pending uploads: %d" % module.pending_count()
	queue_label.visible = module.pending_count() > 0

func _button(parent: Node, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
