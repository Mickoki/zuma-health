extends Control

signal closed

const Module = preload("res://addons/zuma_minigames/module.gd")
var module
var menu: Control
var game_area: Control
var status: Label
var level: OptionButton
var history: VBoxContainer
var footer: Label
var profile_id := ""
var base_url := ""
var history_revision := 0
var history_offset := 0
const HISTORY_PAGE_SIZE := 10

func _ready() -> void:
	theme = preload("res://addons/zuma_minigames/theme.tres")
	add_child(preload("res://addons/zuma_minigames/ui/orbit_background.gd").new())
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	menu = VBoxContainer.new()
	menu.add_theme_constant_override("separation", 12)
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(menu)
	_add_label(menu, "Games", 26)
	level = OptionButton.new()
	level.tooltip_text = "Difficulty. Your saved survey is attached to each run."
	for title in ["Easy", "Normal", "Hard"]:
		level.add_item(title)
	level.select(1)
	menu.add_child(level)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	menu.add_child(grid)
	for item in [["fifteen", "Fifteen Puzzle"], ["pairs", "Find the Pair"], ["math", "Speed Math"], ["chimp", "Remember the Numbers"]]:
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(card)
		var card_column := VBoxContainer.new()
		card.add_child(card_column)
		var launch := _add_button(card_column, item[1], _launch.bind(item[0]))
		launch.icon = load("res://assets/icons/%s.svg" % item[0])
		launch.add_theme_constant_override("h_separation", 14)
		launch.custom_minimum_size.y = 64
		_add_label(card_column, {"fifteen": "Solve the 4×4 board", "pairs": "Memorize the cards", "math": "Beat the timer", "chimp": "Recall the order"}[item[0]], 15)
	var actions := HBoxContainer.new()
	menu.add_child(actions)
	_add_button(actions, "Retry upload", func(): module.retry_pending())
	_add_button(actions, "Refresh history", _load_history)
	_add_button(actions, "Back to app", _close)
	status = _add_label(menu, "", 15)
	history = VBoxContainer.new()
	menu.add_child(history)
	game_area = Control.new()
	game_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	game_area.visible = false
	column.add_child(game_area)
	module = Module.new()
	game_area.add_child(module)
	module.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	module.module_exit_requested.connect(_back_to_menu)
	module.delivery_changed.connect(_delivery)
	footer = _footer()
	column.add_child(footer)

func _footer() -> Label:
	var footer := Label.new()
	footer.text = "Task results are not a medical diagnosis."
	footer.add_theme_font_size_override("font_size", 12)
	return footer

func open_for_profile(profile: Dictionary, url: String, survey: Dictionary) -> bool:
	var id: String = profile.get("id", "")
	var error: Error = module.configure({"profile_id": id, "owner_key": "profile:" + id, "base_url": url, "survey": survey})
	if error != OK:
		visible = false
		return false
	profile_id = id
	base_url = url
	history_offset = 0
	visible = true
	_back_to_menu()
	if survey.is_empty():
		_update_status("To start a game, return to the app and save a survey. History remains available.")
	else:
		var pending: int = module.pending_count()
		_update_status("Profile: " + str(profile.get("display_name", "")) + (" · %d pending" % pending if pending > 0 else ""))
	return true

func _launch(game: String) -> void:
	if module.options.survey.is_empty():
		_update_status("To start a game, return to the app and save a survey for this profile.")
		return
	var error: Error = module.start_game(game, ["easy", "normal", "hard"][level.selected])
	if error != OK:
		_update_status("Could not open the game: %d" % error)
		return
	menu.get_parent().visible = false
	game_area.visible = true
	footer.visible = false

func _back_to_menu() -> void:
	game_area.visible = false
	menu.get_parent().visible = true
	footer.visible = true
	_load_history()

func _close() -> void:
	visible = false
	closed.emit()

func _delivery(_id: String, _state: String, message: String) -> void:
	_update_status(message + " • Total queued: %d" % module.pending_count())
	if _state == "sent" and visible and not game_area.visible:
		_load_history()

func _update_status(message: String) -> void:
	if is_instance_valid(status):
		status.text = message

func _load_history() -> void:
	if profile_id.is_empty():
		return
	history_revision += 1
	var revision := history_revision
	var id := profile_id
	var offset := history_offset
	var response: Dictionary = await module.transport.request(base_url, "/api/v1/profiles/%s/game-runs?limit=%d&offset=%d" % [id, HISTORY_PAGE_SIZE, offset], HTTPClient.METHOD_GET, null, 3.0)
	if revision != history_revision or id != profile_id:
		return
	for child in history.get_children():
		history.remove_child(child)
		child.queue_free()
	_add_label(history, "Game run history", 20)
	if not response.ok:
		_add_label(history, "History is unavailable: check the server connection. Saved results can be uploaded later.", 15)
		return
	var items: Array = response.data.get("items", [])
	if items.is_empty():
		_add_label(history, "No uploaded game runs yet.", 15)
	var titles := {"fifteen": "Fifteen Puzzle", "pairs": "Find the Pair", "math": "Speed Math", "chimp": "Remember the Numbers"}
	var levels := {"easy": "easy", "normal": "normal", "hard": "hard"}
	var statuses := {"completed": "completed", "failed": "mistake limit", "aborted": "interrupted"}
	for item in items:
		var run_id: String = item.get("id", "")
		var title := "%s • %s • %s\n%s • %s" % [titles.get(item.get("game_id", ""), "Game"), levels.get(item.get("difficulty", ""), "unknown"), statuses.get(item.get("status", ""), "unknown"), "demo" if item.get("source") == "synthetic" else "run", str(item.get("performed_at", "")).replace("T", " ").replace("Z", " UTC")]
		var row := HBoxContainer.new()
		history.add_child(row)
		_add_button(row, title + " — report", func(): OS.shell_open(base_url + "/api/v1/game-runs/" + run_id + "/report.html"))
		_add_button(row, "Explain", _explain.bind(run_id, profile_id))
	var total := int(response.data.get("total", 0))
	if total > HISTORY_PAGE_SIZE:
		var navigation := HBoxContainer.new()
		history.add_child(navigation)
		var previous := _add_button(navigation, "← Previous", func(): history_offset = maxi(0, offset - HISTORY_PAGE_SIZE); _load_history())
		previous.disabled = offset == 0
		_add_label(navigation, "%d–%d of %d" % [offset + 1, mini(offset + items.size(), total), total], 15)
		var next := _add_button(navigation, "Next →", func(): history_offset = offset + HISTORY_PAGE_SIZE; _load_history())
		next.disabled = offset + items.size() >= total

func _explain(run_id: String, owner_id: String) -> void:
	_update_status("Requesting a model explanation; this may take up to two minutes.")
	var response: Dictionary = await module.transport.request(base_url, "/api/v1/game-runs/%s/explanation" % run_id, HTTPClient.METHOD_POST, null, 140.0)
	if profile_id != owner_id:
		return
	if not response.ok:
		_update_status("No explanation received: " + str(response.get("error", response.status)))
	elif response.data.get("status") == "ready":
		_update_status("Explanation ready. Open this run's report.")
	else:
		_update_status("The explanation is unavailable or failed validation. The numerical report is available without the model.")

func _add_label(parent: Node, value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label

func _add_button(parent: Node, title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(0, 48)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
