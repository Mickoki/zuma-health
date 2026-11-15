extends Control

const API = "http://127.0.0.1:8080"
const DRAFT_PATH = "user://survey_drafts.json"
const BG = Color("04070f")
const PANEL = Color(0.043, 0.067, 0.125, 0.88)
const MUTED = Color("94a3b8")
const ACCENT = Color("00e5ff")
const OrbitBackground = preload("res://addons/zuma_minigames/ui/orbit_background.gd")
const HISTORY_PAGE_SIZE := 10
const NASA_SLEEP_URL := "https://www.nasa.gov/directorates/esdmd/hhp/risk-of-performance-decrements-and-adverse-health-outcomes-resulting-from-sleep-loss-circadian-desynchronization-and-work-overload/"
const NASA_BEHAVIOR_URL := "https://www.nasa.gov/directorates/esdmd/hhp/behavioral-health-risk/"
const NASA_CHALLENGE_URL := "https://www.spaceappschallenge.org/2026/challenges/health-monitoring-software/"
const SessionQueue = preload("res://scripts/session_queue.gd")
const SurveyChart = preload("res://scripts/survey_chart.gd")
const TrendReportLoader = preload("res://scripts/trend_report_loader.gd")
const MinigamesHost = preload("res://scripts/minigames_host.gd")
const TREND_METRICS := [
	{"key": "sleep_hours", "name": "Sleep", "unit": "h", "max": 24.0, "hint": "Hours of sleep reported in the survey."},
	{"key": "fatigue", "name": "Fatigue", "unit": "/10", "max": 10.0, "hint": "Higher values mean more fatigue."},
	{"key": "stress", "name": "Stress", "unit": "/10", "max": 10.0, "hint": "Higher values mean more stress."},
	{"key": "mood", "name": "Mood", "unit": "/10", "max": 10.0, "hint": "Higher values mean better mood."},
	{"key": "memory_percent", "name": "Memory", "unit": "%", "max": 100.0, "kind": "report", "hint": "Percentage of correct answers calculated by the server."},
	{"key": "reaction_median_ms", "name": "Reaction", "unit": "ms", "max": 10000.0, "kind": "report", "hint": "Median of valid trials calculated by the server."}
]

var api_url := API
var draft_path := DRAFT_PATH
var queue_path := "user://pending_sessions"
var profiles: Array = []
var selected_profile: Dictionary = {}
var drafts: Dictionary = {}
var current_page := "home"
var root_column: VBoxContainer
var content: VBoxContainer
var content_scroll: ScrollContainer
var status_label: Label
var profile_picker: OptionButton
var navigation_buttons: Dictionary = {}
var survey_inputs: Dictionary = {}
var survey_edits: Dictionary = {}
var survey_status: Label
var creating_profile := false
var page_revision := 0
var explaining := false
var profiles_request_revision := 0
var profile_selection_revision := 0
var session_queue: Node
var sending_pending := false
var home_pending_section: VBoxContainer
var home_queue_warning: VBoxContainer
var home_latest_section: VBoxContainer
var home_latest_revision := 0
var home_game_latest_section: VBoxContainer
var home_game_latest_revision := 0
var game_scene_paths := {"reaction": "res://scenes/games/reaction.tscn", "memory": "res://scenes/games/memory.tscn"}
var active_run: Dictionary = {}
var draft_load_error := false
var history_profile_id := ""
var history_offset := 0
var report_trail: Array[String] = []
var trend_sessions: Array = []
var trend_total := 0
var trend_game_total := 0
var trend_game_error := false
var trend_source: OptionButton
var trend_metric: OptionButton
var trend_protocol: OptionButton
var trend_chart: Control
var trend_hint: Label
var trend_summary: Label
var trend_dates: Label
var trend_order: Label
var trend_values: VBoxContainer
var trend_values_button: Button
var trend_retry: Button
var trend_report_cache: Dictionary = {}
var trend_loader: Node
var trend_load_revision := 0
var minigames_host: Control

func _ready() -> void:
	TranslationServer.set_locale("en")
	theme = preload("res://theme/zuma_theme.tres")
	session_queue = SessionQueue.new()
	session_queue.api_url = api_url
	session_queue.queue_dir = queue_path
	add_child(session_queue)
	load_drafts()
	build_shell()
	show_home()
	refresh_profiles()

func label(text: String, size: int = 16, color: Color = Color.WHITE) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", color)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return result

func button(text: String, action: Callable, primary: bool = false) -> Button:
	var result := Button.new()
	result.text = text
	result.custom_minimum_size = Vector2(0, 44)
	result.add_theme_font_size_override("font_size", 16)
	var normal := StyleBoxFlat.new()
	normal.bg_color = ACCENT if primary else PANEL
	normal.set_corner_radius_all(10)
	normal.set_border_width_all(1)
	normal.border_color = Color(0.58, 0.64, 0.72, 0.22)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	result.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("7cf3ff") if primary else Color("12384a")
	result.add_theme_stylebox_override("hover", hover)
	if primary:
		result.add_theme_color_override("font_color", BG)
		result.add_theme_color_override("font_hover_color", BG)
	result.pressed.connect(action)
	return result

func build_shell() -> void:
	add_child(OrbitBackground.new())
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	root_column = VBoxContainer.new()
	root_column.add_theme_constant_override("separation", 16)
	margin.add_child(root_column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	root_column.add_child(header)
	var logo := TextureRect.new()
	logo.texture = preload("res://assets/icons/zuma.svg")
	logo.custom_minimum_size = Vector2(32, 32)
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header.add_child(logo)
	var brand := label("ZUMA", 21, ACCENT)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(brand)
	status_label = label("Checking server…", 14, MUTED)
	status_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	status_label.clip_text = true
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.custom_minimum_size.x = 310
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label.mouse_filter = Control.MOUSE_FILTER_STOP
	status_label.tooltip_text = status_label.text
	header.add_child(status_label)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	root_column.add_child(body)
	var sidebar := PanelContainer.new()
	sidebar.custom_minimum_size.x = 172
	body.add_child(sidebar)
	var nav := VBoxContainer.new()
	nav.add_theme_constant_override("separation", 6)
	sidebar.add_child(nav)
	navigation_buttons = {"home": button("Overview", show_home), "survey": button("Wellbeing", show_survey), "games": button("Games", show_minigames), "history": button("History", show_history), "trends": button("Trends", show_trends), "help": button("Help", show_help)}
	for nav_button in navigation_buttons.values():
		nav_button.custom_minimum_size.y = 40
		nav.add_child(nav_button)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav.add_child(spacer)
	nav.add_child(button("Exit", func(): get_tree().quit()))
	profile_picker = OptionButton.new()
	profile_picker.custom_minimum_size = Vector2(210, 44)
	profile_picker.add_item("No profile")
	profile_picker.item_selected.connect(select_profile)
	header.add_child(profile_picker)
	content_scroll = ScrollContainer.new()
	content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(content_scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 16)
	content_scroll.add_child(content)
	root_column.add_child(label("Task results are not a medical diagnosis.", 13, MUTED))

func clear_content(page: String) -> void:
	if current_page == "trends":
		stop_trend_loader()
	if current_page in ["game", "game_result"] and page not in ["game", "game_result"]:
		active_run.clear()
	current_page = page
	update_navigation(page)
	page_revision += 1
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	content_scroll.scroll_vertical = 0

func update_navigation(page: String) -> void:
	var active := page
	var run_in_progress := page == "game" or (page == "game_result" and not active_run.is_empty())
	if page in ["game", "game_result"]:
		active = "survey"
	elif page == "report":
		active = "history"
	for key in navigation_buttons:
		var item: Button = navigation_buttons[key]
		item.disabled = run_in_progress
		var normal := item.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
		normal.bg_color = Color("12384a") if key == active else PANEL
		normal.border_color = ACCENT if key == active else Color(0.58, 0.64, 0.72, 0.22)
		item.add_theme_stylebox_override("normal", normal)
		item.add_theme_color_override("font_color", ACCENT if key == active else Color.WHITE)
	profile_picker.disabled = run_in_progress

func set_connection_status(message: String) -> void:
	status_label.text = message
	status_label.tooltip_text = message

func card() -> VBoxContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.set_corner_radius_all(10)
	style.set_border_width_all(1)
	style.border_color = Color(0.58, 0.64, 0.72, 0.22)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", style)
	content.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	return column

func show_home() -> void:
	clear_content("home")
	content.add_child(label("Overview", 34))
	home_queue_warning = VBoxContainer.new()
	home_queue_warning.add_theme_constant_override("separation", 8)
	content.add_child(home_queue_warning)
	if not selected_profile.is_empty():
		var latest := card()
		home_latest_section = VBoxContainer.new()
		home_latest_section.add_theme_constant_override("separation", 10)
		latest.add_child(button("Latest check-in", func(): home_latest_section.visible = not home_latest_section.visible))
		latest.add_child(home_latest_section)
		home_latest_section.visible = false
		var game_latest := card()
		game_latest.add_child(label("Latest game", 18, ACCENT))
		home_game_latest_section = VBoxContainer.new()
		game_latest.add_child(home_game_latest_section)
	var intro := card()
	if not selected_profile.is_empty():
		var profile_controls := VBoxContainer.new()
		profile_controls.add_theme_constant_override("separation", 10)
		var toggle := button("Manage profiles", func(): profile_controls.visible = not profile_controls.visible)
		intro.add_child(toggle)
		intro.add_child(profile_controls)
		profile_controls.visible = false
		intro = profile_controls
	else:
		intro.add_child(label("Create your profile", 21))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	intro.add_child(row)
	var name_input := LineEdit.new()
	name_input.placeholder_text = "Crew member name"
	name_input.max_length = 100
	name_input.custom_minimum_size = Vector2(260, 44)
	name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_input)
	row.add_child(button("Create profile", func() -> void: create_profile(name_input.text), true))
	intro.add_child(button("Refresh connection and profiles", func() -> void: refresh_profiles(selected_profile.get("id", ""))))
	var next := card()
	next.get_parent().visible = not selected_profile.is_empty()
	next.add_child(label("Daily check-in", 21))
	next.add_child(button("Complete survey  →", show_survey, true))
	next.add_child(button("Go to mini-games", show_minigames))
	var history := card()
	history.get_parent().visible = not selected_profile.is_empty()
	history.add_child(button("Open game history", show_minigames))
	history.add_child(button("Legacy check-in history", show_history))
	home_pending_section = VBoxContainer.new()
	home_pending_section.add_theme_constant_override("separation", 12)
	history.add_child(home_pending_section)
	refresh_home_pending()
	if not selected_profile.is_empty():
		refresh_home_latest()
		refresh_home_game_latest()

func refresh_home_game_latest() -> void:
	if current_page != "home" or selected_profile.is_empty() or not is_instance_valid(home_game_latest_section):
		return
	home_game_latest_revision += 1
	var revision := home_game_latest_revision
	var page := page_revision
	var profile_id: String = selected_profile.id
	var section := home_game_latest_section
	for child in section.get_children():
		section.remove_child(child)
		child.queue_free()
	section.add_child(label("Loading game run…", 16, MUTED))
	var response := await request(HTTPClient.METHOD_GET, "/api/v1/profiles/%s/game-runs?limit=1&offset=0" % profile_id)
	if page_revision != page or home_game_latest_revision != revision or selected_profile.get("id", "") != profile_id or not is_instance_valid(section):
		return
	for child in section.get_children():
		section.remove_child(child)
		child.queue_free()
	if not response.ok:
		section.add_child(label("Could not load game runs.", 16, MUTED))
		section.add_child(button("Reload games", refresh_home_game_latest))
		return
	if not response.data.get("items") is Array or response.data.items.is_empty():
		section.add_child(label("No uploaded games yet. Local results are available under Games.", 16, MUTED))
		return
	var run: Dictionary = response.data.items[0]
	var names := {"fifteen": "Fifteen Puzzle", "pairs": "Find the Pair", "math": "Speed Math", "chimp": "Remember the Numbers"}
	section.add_child(label("%s • %s • %s" % [names.get(run.get("game_id", ""), "Game"), str(run.get("performed_at", "")).replace("T", " ").replace("Z", " UTC"), "Demonstration data" if run.get("source") == "synthetic" else "Game result"], 16, MUTED))
	section.add_child(label("Outcome: " + {"completed": "completed", "failed": "mistake limit", "aborted": "interrupted"}.get(run.get("status", ""), "unknown"), 16, MUTED))
	var run_id: String = run.get("id", "")
	if not run_id.is_empty():
		section.add_child(button("Open latest game report ↗", func() -> void: OS.shell_open(api_url + "/api/v1/game-runs/" + run_id + "/report.html")))

func refresh_home_latest() -> void:
	if current_page != "home" or selected_profile.is_empty() or not is_instance_valid(home_latest_section):
		return
	home_latest_revision += 1
	var revision := home_latest_revision
	var page := page_revision
	var profile_id: String = selected_profile.id
	var section := home_latest_section
	for child in section.get_children():
		section.remove_child(child)
		child.queue_free()
	section.add_child(label("Loading latest check-in…", 16, MUTED))
	var response := await request(HTTPClient.METHOD_GET, "/api/v1/profiles/%s/sessions?limit=1&offset=0" % profile_id)
	if page_revision != page or home_latest_revision != revision or selected_profile.get("id", "") != profile_id or not is_instance_valid(section):
		return
	for child in section.get_children():
		section.remove_child(child)
		child.queue_free()
	if not response.ok:
		section.add_child(label("Could not load the latest check-in.", 16, MUTED))
		section.add_child(button("Reload", refresh_home_latest))
		return
	if response.data.items.is_empty():
		section.add_child(label("There are no saved check-ins for this profile yet.", 16, MUTED))
		return
	var session: Dictionary = response.data.items[0]
	section.add_child(label(str(session.performed_at).replace("T", " ").replace("Z", " UTC"), 19))
	section.add_child(label("Demonstration data" if session.source == "synthetic" else "Check-in result", 14, MUTED))
	var survey: Dictionary = session.survey
	var memory: Dictionary = session.memory
	section.add_child(label("Sleep: %s h  •  Fatigue: %s/10  •  Stress: %s/10  •  Mood: %s/10" % [survey.sleep_hours, survey.fatigue, survey.stress, survey.mood], 16, MUTED))
	section.add_child(label("Memory: %d of %d answers correct" % [int(memory.correct), int(memory.total)], 16, MUTED))
	var session_id: String = session.id
	section.add_child(button("Open latest check-in report", func() -> void: report_trail.clear(); show_report(session_id)))

func refresh_home_pending() -> void:
	if current_page != "home" or not is_instance_valid(home_pending_section):
		return
	for child in home_pending_section.get_children():
		home_pending_section.remove_child(child)
		child.queue_free()
	for child in home_queue_warning.get_children():
		home_queue_warning.remove_child(child)
		child.queue_free()
	var profile_id: String = selected_profile.get("id", "")
	var audit: Dictionary = session_queue.inspect_queue(profile_id)
	if audit.directory_error or audit.problem_count > 0:
		var warning := "Could not open the local queue folder." if audit.directory_error else "Some queue files could not be verified: %d." % audit.problem_count
		home_queue_warning.add_child(label(warning + " Files were not changed; back up the folder and contact the team.", 16, Color("ffbf8a")))
		var queue_path := LineEdit.new()
		queue_path.text = ProjectSettings.globalize_path(session_queue.queue_dir)
		queue_path.editable = false
		queue_path.custom_minimum_size.y = 42
		queue_path.add_theme_color_override("font_uneditable_color", MUTED)
		queue_path.tooltip_text = "Local queue path"
		home_queue_warning.add_child(queue_path)
	if not selected_profile.is_empty():
		var count: int = audit.records.size()
		if count > 0:
			home_pending_section.add_child(label("Pending uploads: %d" % count, 16, ACCENT))
			home_pending_section.add_child(button("Upload saved check-ins", send_pending))

func show_survey() -> void:
	clear_content("survey")
	survey_inputs.clear()
	content.add_child(label("How are you feeling?", 34))
	if selected_profile.is_empty():
		content.add_child(label("First select or create a profile on Overview.", 18, ACCENT))
		return
	var form := card()
	var draft: Dictionary = drafts.get(selected_profile.id, {})
	add_survey_field(form, "sleep_hours", "Sleep", "How many hours did you sleep?  •  0–24 hours", draft)
	add_survey_field(form, "fatigue", "Fatigue", "0 — no fatigue  •  10 — extreme fatigue", draft)
	add_survey_field(form, "stress", "Stress", "0 — no stress  •  10 — extreme stress", draft)
	add_survey_field(form, "mood", "Mood", "0 — very poor  •  10 — excellent", draft)
	survey_status = label("", 15, MUTED)
	form.add_child(survey_status)
	if survey_edits.has(selected_profile.id):
		survey_status.text = "There are unsaved changes."
	form.add_child(button("Save draft", func() -> void: save_survey(), true))
	form.add_child(button("How do I complete the survey?", func() -> void: show_help("survey")))
	if games_available():
		form.add_child(button("Start game tasks →", start_game_run))
	else:
		var next_step := label("Save your survey before playing.", 15, MUTED)
		next_step.tooltip_text = "The saved survey is attached to each new game. Update it if your wellbeing changes."
		form.add_child(next_step)

func show_minigames() -> void:
	if selected_profile.is_empty():
		clear_content("games")
		content.add_child(label("Create or select a profile on the Overview page before playing.", 20, ACCENT))
		return
	var saved_survey: Dictionary = {}
	if not draft_load_error and drafts.get(selected_profile.id) is Dictionary and not survey_edits.has(selected_profile.id):
		saved_survey = drafts[selected_profile.id]
	if not is_instance_valid(minigames_host):
		minigames_host = MinigamesHost.new()
		add_child(minigames_host)
		minigames_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		minigames_host.closed.connect(func() -> void:
			if current_page == "home":
				refresh_home_game_latest()
		)
	if not minigames_host.open_for_profile(selected_profile, api_url, saved_survey):
		set_connection_status("Games: wait for the upload or check queue access.")

func add_survey_field(parent: VBoxContainer, key: String, title: String, hint: String, draft: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	parent.add_child(row)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(label(title, 19))
	text.add_child(label(hint, 14, MUTED))
	row.add_child(text)
	var input := LineEdit.new()
	input.placeholder_text = "Enter value"
	var profile_id: String = selected_profile.id
	var edits: Dictionary = survey_edits.get(profile_id, {})
	if edits.has(key):
		input.text = str(edits[key])
	elif draft.has(key):
		input.text = str(draft[key])
	input.custom_minimum_size = Vector2(110, 42)
	row.add_child(input)
	survey_inputs[key] = input
	input.text_changed.connect(func(value: String) -> void:
		if not survey_edits.has(profile_id):
			survey_edits[profile_id] = {}
		survey_edits[profile_id][key] = value
		if is_instance_valid(survey_status):
			survey_status.text = "There are unsaved changes."
			survey_status.add_theme_color_override("font_color", MUTED)
	)

func set_survey_status(message: String, color: Color) -> void:
	if is_instance_valid(survey_status):
		survey_status.text = message
		survey_status.add_theme_color_override("font_color", color)

func save_survey() -> bool:
	if selected_profile.is_empty():
		return false
	if draft_load_error:
		set_survey_status("Could not read existing drafts. Saving is paused to avoid overwriting the file.", Color("ffadad"))
		return false
	var draft := {}
	for key in survey_inputs:
		var value_text: String = survey_inputs[key].text.strip_edges().replace(",", ".")
		if not value_text.is_valid_float():
			set_survey_status("Complete every field with a number from 0 to 10 (sleep: 0 to 24).", Color("ffadad"))
			return false
		var value := value_text.to_float()
		var maximum := 24.0 if key == "sleep_hours" else 10.0
		if not is_finite(value) or value < 0.0 or value > maximum:
			set_survey_status("Check the ranges: sleep from 0 to 24; other values from 0 to 10.", Color("ffadad"))
			return false
		draft[key] = value
	var updated := drafts.duplicate(true)
	updated[selected_profile.id] = draft
	var temp_path := draft_path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		set_survey_status("Could not save the draft on this device.", Color("ffadad"))
		return false
	file.store_string(JSON.stringify(updated))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		set_survey_status("Could not save the draft on this device.", Color("ffadad"))
		return false
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(draft_path)) != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		set_survey_status("Could not save the draft on this device.", Color("ffadad"))
		return false
	drafts = updated
	survey_edits.erase(selected_profile.id)
	set_survey_status("Draft saved on this device.", ACCENT)
	return true

func games_available() -> bool:
	return ResourceLoader.exists(game_scene_paths.reaction, "PackedScene") and ResourceLoader.exists(game_scene_paths.memory, "PackedScene")

func start_game_run() -> void:
	if not games_available() or not save_survey():
		return
	var profile_id: String = selected_profile.id
	active_run = {"profile_id": profile_id, "survey": drafts[profile_id].duplicate(true)}
	show_game("reaction")

func show_game(kind: String) -> void:
	clear_content("game")
	var revision := page_revision
	content.add_child(label("Task 1 / 2 • Reaction" if kind == "reaction" else "Task 2 / 2 • Memory", 30))
	content.add_child(label("Navigation and profile switching are available after the check-in finishes or is cancelled.", 14, MUTED))
	var scene: PackedScene = load(game_scene_paths[kind]) as PackedScene
	if scene == null:
		game_error("Could not load the game scene.")
		return
	var game := scene.instantiate()
	if not game is Control or not game.has_signal("completed") or not game.has_signal("cancelled"):
		game.free()
		game_error("The game scene does not support the required interface.")
		return
	# A plain Control has a zero minimum height in a VBoxContainer. Give every
	# game a usable drawing/input area while respecting larger scene minima.
	game.custom_minimum_size.y = maxf(game.custom_minimum_size.y, 360.0)
	game.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	game.completed.connect(func(result: Dictionary) -> void: complete_game(kind, revision, result), CONNECT_DEFERRED)
	game.cancelled.connect(func() -> void: cancel_game(revision), CONNECT_DEFERRED)
	content.add_child(button("Cancel check-in", func() -> void: cancel_game(revision)))
	content.add_child(game)

func cancel_game(revision: int) -> void:
	if current_page != "game" or page_revision != revision:
		return
	active_run.clear()
	show_survey()

func game_error(message: String) -> void:
	active_run.clear()
	clear_content("game_result")
	content.add_child(label(message, 20, Color("ffadad")))
	content.add_child(label("The check-in was not saved. Return to the survey and try again.", 16, MUTED))
	content.add_child(button("Back to survey", show_survey))

func complete_game(kind: String, revision: int, result: Dictionary) -> void:
	if current_page != "game" or page_revision != revision or active_run.is_empty():
		return
	if selected_profile.get("id", "") != active_run.profile_id or result.get("protocol_version") != session_queue.PROTOCOL:
		game_error("The task result does not match the profile or agreed protocol.")
		return
	active_run[kind] = result.duplicate(true)
	if kind == "reaction":
		show_game("memory")
	else:
		finish_game_run()

func finish_game_run() -> void:
	if active_run.is_empty() or not active_run.has("reaction") or not active_run.has("memory"):
		return
	var profile_id: String = active_run.profile_id
	var outcome: Dictionary = accept_game_results(profile_id, active_run.survey, active_run.reaction, active_run.memory)
	if outcome.ok:
		active_run.clear()
	clear_content("game_result")
	if not outcome.ok:
		content.add_child(label(game_save_error_message(str(outcome.error)), 20, Color("ffadad")))
		content.add_child(label("Results remain in memory until you leave this screen.", 16, MUTED))
		if outcome.error == "storage_unavailable":
			content.add_child(button("Retry save", finish_game_run))
		content.add_child(button("Back to survey", func() -> void: active_run.clear(); show_survey()))
		return
	content.add_child(label("Check-in saved on this device", 30, ACCENT))
	content.add_child(label("Upload it to the server to open its report. If this fails, you can retry later.", 16, MUTED))
	var send_status := label("", 16, MUTED)
	content.add_child(send_status)
	var revision := page_revision
	var queue_id: String = outcome.id
	content.add_child(button("Upload and open report", func() -> void: send_completed_session(profile_id, queue_id, revision, send_status), true))
	content.add_child(button("Go to Overview", show_home))

func game_save_error_message(code: String) -> String:
	match code:
		"storage_unavailable":
			return "Could not save the check-in on this device."
		"invalid_profile":
			return "The check-in profile was not recognized."
		"incompatible_protocol":
			return "Game versions do not match the protocol."
		"invalid_survey":
			return "Survey data does not match the required format."
		"invalid_reaction":
			return "Reaction task results have an invalid format."
		"invalid_memory":
			return "Memory task results have an invalid format."
	return "Could not save the check-in."

func send_completed_session(profile_id: String, queue_id: String, revision: int, message: Label) -> void:
	if page_revision != revision or selected_profile.get("id", "") != profile_id or not is_instance_valid(message):
		return
	if sending_pending:
		message.text = "Wait for the current upload to finish."
		return
	var record: Dictionary = {}
	var audit: Dictionary = session_queue.inspect_queue(profile_id)
	for pending_record in audit.records:
		if pending_record.payload.client_session_id == queue_id:
			record = pending_record
			break
	if record.is_empty():
		message.text = "Could not verify the local queue. Open Overview for details." if audit.directory_error or audit.problem_count > 0 else "The check-in was not found in the queue. Check History."
		return
	sending_pending = true
	message.text = "Uploading check-in…"
	var response: Dictionary = await session_queue.send(record)
	sending_pending = false
	if page_revision != revision or selected_profile.get("id", "") != profile_id or not is_instance_valid(message):
		if selected_profile.get("id", "") == profile_id:
			set_connection_status("Check-in uploaded • report available in History" if response.ok else pending_error_message(response))
			refresh_home_pending()
			if response.ok:
				refresh_home_latest()
		return
	if response.ok:
		report_trail.clear()
		show_report(response.session_id)
		return
	message.text = pending_error_message(response)
	message.add_theme_color_override("font_color", Color("ffbf8a"))
	if response.get("error") == "saved_but_local_removal_failed" and response.has("session_id"):
		var session_id: String = response.session_id
		content.add_child(button("Open saved report", func() -> void: report_trail.clear(); show_report(session_id)))

func load_drafts() -> void:
	if not FileAccess.file_exists(draft_path):
		return
	var file := FileAccess.open(draft_path, FileAccess.READ)
	if file == null:
		draft_load_error = true
		return
	var parsed: Variant = session_queue.parse_object(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		drafts = parsed
	else:
		draft_load_error = true

func request(method: HTTPClient.Method, path: String, payload: Variant = null, timeout_seconds: float = 10.0) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = timeout_seconds
	add_child(http)
	var headers := PackedStringArray()
	var body := ""
	if payload != null:
		headers.append("Content-Type: application/json")
		body = JSON.stringify(payload)
	var err := http.request(api_url + path, headers, method, body)
	if err != OK:
		http.queue_free()
		return {"ok": false}
	var response: Array = await http.request_completed
	http.queue_free()
	var parser := JSON.new()
	var data: Variant = null
	if parser.parse(response[3].get_string_from_utf8()) == OK:
		data = parser.data
	return {"ok": response[0] == HTTPRequest.RESULT_SUCCESS and response[1] >= 200 and response[1] < 300 and data is Dictionary, "data": data, "status": response[1]}

func refresh_profiles(preferred_id: String = "") -> void:
	var selection_at_start := profile_selection_revision
	profiles_request_revision += 1
	var revision := profiles_request_revision
	var response := await request(HTTPClient.METHOD_GET, "/api/v1/profiles?limit=100&offset=0")
	if revision != profiles_request_revision:
		return
	if not response.ok:
		set_connection_status("Server unavailable • start the Go API")
		status_label.add_theme_color_override("font_color", Color("ffbf8a"))
		return
	set_connection_status("Server connected")
	status_label.add_theme_color_override("font_color", ACCENT)
	if current_page == "game" or (current_page == "game_result" and not active_run.is_empty()):
		return
	var previous_profile_id: String = selected_profile.get("id", "")
	if profile_selection_revision != selection_at_start:
		preferred_id = previous_profile_id
	profiles = response.data.items
	profile_picker.clear()
	selected_profile = {}
	if profiles.is_empty():
		profile_picker.add_item("No profile")
	else:
		var chosen := 0
		for i in range(profiles.size()):
			profile_picker.add_item(profiles[i].display_name)
			if profiles[i].id == preferred_id:
				chosen = i
		profile_picker.select(chosen)
		selected_profile = profiles[chosen]
	if current_page == "history" or current_page == "report":
		show_history()
	elif current_page == "trends":
		show_trends()
	elif current_page in ["game", "game_result"] and selected_profile.get("id", "") != previous_profile_id:
		active_run.clear()
		show_survey()
	elif current_page == "survey" and selected_profile.get("id", "") != previous_profile_id:
		show_survey()
	elif current_page == "home":
		if selected_profile.get("id", "") != previous_profile_id:
			show_home()
		else:
			refresh_home_pending()
			refresh_home_latest()

func create_profile(display_name: String) -> void:
	if creating_profile:
		return
	var trimmed := display_name.strip_edges()
	if trimmed.is_empty():
		set_connection_status("Enter a profile name")
		return
	set_connection_status("Creating profile…")
	creating_profile = true
	var response := await request(HTTPClient.METHOD_POST, "/api/v1/profiles", {"display_name": trimmed})
	creating_profile = false
	if not response.ok:
		set_connection_status("Could not create the profile • check the server")
		return
	refresh_profiles(response.data.id)

func select_profile(index: int) -> void:
	if current_page == "game" or (current_page == "game_result" and not active_run.is_empty()):
		return
	if index < 0 or index >= profiles.size():
		return
	if profiles[index].id == selected_profile.get("id", ""):
		return
	profile_selection_revision += 1
	selected_profile = profiles[index]
	if current_page == "game" or current_page == "game_result":
		active_run.clear()
		show_survey()
	elif current_page == "survey":
		show_survey()
	elif current_page == "history" or current_page == "report":
		show_history()
	elif current_page == "trends":
		show_trends()
	elif current_page == "home":
		show_home()

## Games call this only after both tasks have completed for the same profile.
## The UI/integration must capture the profile and survey at the start of the run.
func accept_game_results(profile_id: String, survey: Dictionary, reaction: Dictionary, memory: Dictionary) -> Dictionary:
	return session_queue.enqueue(profile_id, survey, reaction, memory)

func send_pending() -> void:
	if sending_pending or selected_profile.is_empty():
		return
	sending_pending = true
	var profile_id: String = selected_profile.id
	var audit: Dictionary = session_queue.inspect_queue(profile_id)
	var records: Array = audit.records
	if audit.directory_error:
		sending_pending = false
		set_connection_status("Could not open the local queue • check Overview")
		refresh_home_pending()
		return
	set_connection_status("Uploading saved check-ins…")
	var failure: Dictionary = {}
	for record in records:
		var response: Dictionary = await session_queue.send(record)
		if not response.ok:
			failure = response
			break
	sending_pending = false
	audit = session_queue.inspect_queue(profile_id)
	if not failure.is_empty():
		set_connection_status(pending_error_message(failure))
		status_label.add_theme_color_override("font_color", Color("ffbf8a"))
	elif audit.directory_error or audit.problem_count > 0:
		set_connection_status("Some queue files could not be verified • check Overview")
		status_label.add_theme_color_override("font_color", Color("ffbf8a"))
	elif records.is_empty():
		set_connection_status("No check-ins to upload")
	else:
		set_connection_status("Check-ins uploaded")
		status_label.add_theme_color_override("font_color", ACCENT)
	if selected_profile.get("id", "") == profile_id:
		if current_page == "home":
			refresh_home_pending()
			if failure.is_empty():
				refresh_home_latest()
		elif current_page == "history":
			show_history()

func pending_error_message(failure: Dictionary) -> String:
	if failure.get("error") == "saved_but_local_removal_failed":
		return "The server saved the check-in, but the local copy is still queued"
	var status := int(failure.get("status", 0))
	if status == 409:
		return "Check-in ID conflict • review the data"
	if status == 400 or status == 422:
		return "Server rejected the check-in data • check the format"
	if status == 404:
		return "Profile not found on the server • check the connected database"
	return "Could not upload the check-in • try again later"

func show_help(origin: String = "", session_id: String = "") -> void:
	var profile_id: String = selected_profile.get("id", "")
	clear_content("help")
	content.add_child(label("How to use Zuma", 34))
	var why := card()
	why.add_child(label("Why these metrics?", 21, ACCENT))
	why.add_child(label("NASA studies how sleep loss and circadian disruption affect fatigue and task performance [1]. Isolation and confinement can also affect cognitive and behavioral functions [2]. These sources provide context but do not establish the medical validity of Zuma tasks.", 16, MUTED))
	var survey := card()
	survey.add_child(label("How to complete the survey", 21, ACCENT))
	survey.add_child(label("Select your profile and complete every field. Enter sleep in hours from 0 to 24; use the same reporting period agreed by the team. This prototype does not store the sleep period separately.", 16, MUTED))
	survey.add_child(label("Fatigue and stress: 0 to 10, where higher means a stronger feeling. Mood: 0 to 10, where higher means better mood. Zero is a valid answer; an empty field is not zero.", 16, MUTED))
	survey.add_child(label("The draft is stored on this device after you select Save draft. Its copy is attached to every new game. If your wellbeing changes, update the survey before the next game.", 16, MUTED))
	var results := card()
	results.add_child(label("How to read the results", 21, ACCENT))
	results.add_child(label("Reaction is the median time of valid trials in milliseconds: the middle value of a sorted list, or the average of the two middle values. It is not calculated without valid trials. Memory is the proportion of correct answers. These results describe task performance and are not a diagnosis.", 16, MUTED))
	results.add_child(label("Comparison uses the nearest earlier check-in with the same profile, protocol, and data source. No comparison is shown if none exists. Demonstration data is kept separate from real check-in results.", 16, MUTED))
	results.add_child(label("Game reports compare only runs with the same game, difficulty, rules, and source. Interrupted attempts are excluded. A game survey point is dated by the game, not by survey completion.", 16, MUTED))
	results.add_child(label("Chart spacing shows check-in order, not elapsed time. Gaps are not connected; exact dates and values are available in the list.", 16, MUTED))
	var actions := card()
	actions.add_child(label("What you can do next", 21, ACCENT))
	actions.add_child(label("Check whether your saved survey is current, then open History or Trends to review changes. If you have concerning symptoms or questions about results, follow the mission protocol and contact a medical professional. Game results do not define treatment thresholds.", 16, MUTED))
	var limits := card()
	limits.add_child(label("Limitations", 21, ACCENT))
	limits.add_child(label("The self-report scales and game tasks in this prototype have not undergone confirmed clinical validation. The app does not use sensors to measure blood pressure, heart rate, or other vital signs, and does not prescribe treatment. For health questions, follow the mission medical protocol and contact a professional according to crew procedures.", 16, MUTED))
	limits.add_child(label("When available, the local model selects server-verified facts for its explanation. Its output does not replace medical advice.", 16, MUTED))
	var sources := card()
	sources.add_child(label("NASA sources", 21, ACCENT))
	sources.add_child(label("Links open in a browser and require an internet connection.", 15, MUTED))
	sources.add_child(button("[1] NASA: sleep and performance ↗", func() -> void: OS.shell_open(NASA_SLEEP_URL)))
	sources.add_child(button("[2] NASA: behavioral and cognitive risks ↗", func() -> void: OS.shell_open(NASA_BEHAVIOR_URL)))
	sources.add_child(button("NASA Space Apps challenge ↗", func() -> void: OS.shell_open(NASA_CHALLENGE_URL)))
	var diagnostics := card()
	var storage_result := label("", 14, MUTED)
	diagnostics.add_child(button("Check local storage", func():
		var file := FileAccess.open("user://setup_check.json", FileAccess.WRITE)
		if file == null:
			storage_result.text = "Save error: %d" % FileAccess.get_open_error()
			return
		file.store_string(JSON.stringify({"setup": "ok", "time": Time.get_datetime_string_from_system(true)}))
		file.flush()
		var error := file.get_error()
		file.close()
		storage_result.text = "Record saved: setup_check.json" if error == OK else "Save error: %d" % error
	))
	diagnostics.add_child(storage_result)
	if origin in ["survey", "report", "trends"]:
		content.add_child(button("Return", func() -> void:
			if selected_profile.get("id", "") != profile_id:
				show_home()
			elif origin == "survey":
				show_survey()
			elif origin == "report":
				show_report(session_id)
			else:
				show_trends()
		))

func show_trends() -> void:
	clear_content("trends")
	var revision := page_revision
	trend_sessions.clear()
	trend_report_cache.clear()
	trend_game_total = 0
	trend_game_error = false
	content.add_child(label("Wellbeing trends", 34))
	if selected_profile.is_empty():
		content.add_child(label("Select a profile to view trends.", 17, MUTED))
		return
	var profile_id: String = selected_profile.id
	var loading := label("Loading check-ins…", 16, MUTED)
	content.add_child(loading)
	var response := await request(HTTPClient.METHOD_GET, "/api/v1/profiles/%s/sessions?limit=100&offset=0" % profile_id)
	if page_revision != revision or selected_profile.get("id", "") != profile_id or not is_instance_valid(loading):
		return
	loading.queue_free()
	if not response.ok:
		content.add_child(label("Could not load check-ins. Check the server connection.", 16, Color("ffadad")))
		content.add_child(button("Retry", show_trends))
		return
	trend_sessions = response.data.items
	trend_total = int(response.data.total)
	var games_response := await request(HTTPClient.METHOD_GET, "/api/v1/profiles/%s/game-runs?limit=100&offset=0" % profile_id)
	if page_revision != revision or selected_profile.get("id", "") != profile_id:
		return
	if games_response.ok and games_response.data.get("items") is Array:
		trend_game_total = int(games_response.data.get("total", 0))
		for item in games_response.data.items:
			if item is Dictionary and item.get("game_id") is String and item.get("difficulty") is String and session_queue.is_number(item.get("rules_version")) and float(item.rules_version) >= 1 and floorf(float(item.rules_version)) == float(item.rules_version):
				var entry: Dictionary = item.duplicate(true)
				entry["protocol_version"] = "zuma-game/%s/%s/v%d" % [entry.game_id, entry.difficulty, int(entry.rules_version)]
				entry["trend_kind"] = "game"
				trend_sessions.append(entry)
		trend_sessions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("performed_at", "")) > str(b.get("performed_at", "")))
	else:
		trend_game_error = true
	build_trend_view()

func trend_picker(parent: HBoxContainer, title: String) -> OptionButton:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	parent.add_child(column)
	column.add_child(label(title, 14, MUTED))
	var picker := OptionButton.new()
	picker.custom_minimum_size.y = 44
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(picker)
	return picker

func build_trend_view() -> void:
	var section := card()
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 14)
	section.add_child(filters)
	trend_metric = trend_picker(filters, "Metric")
	for metric in TREND_METRICS:
		trend_metric.add_item(metric.name)
	trend_metric.select(0)
	trend_source = trend_picker(filters, "Data source")
	trend_source.add_item("Check-in results")
	trend_source.set_item_metadata(0, "observed")
	trend_source.add_item("Demo")
	trend_source.set_item_metadata(1, "synthetic")
	trend_source.select(0)
	trend_protocol = trend_picker(filters, "Protocol")
	trend_hint = label("", 15, MUTED)
	section.add_child(trend_hint)
	trend_summary = label("", 15, MUTED)
	section.add_child(trend_summary)
	trend_retry = button("Reload reports", func() -> void: render_trend())
	trend_retry.visible = false
	section.add_child(trend_retry)
	trend_dates = label("", 14, MUTED)
	section.add_child(trend_dates)
	trend_order = label("Oldest → Newest", 14, MUTED)
	trend_order.tooltip_text = "Spacing shows check-in order, not elapsed time. Gaps are not connected."
	section.add_child(trend_order)
	trend_chart = SurveyChart.new()
	section.add_child(trend_chart)
	trend_values = VBoxContainer.new()
	trend_values.add_theme_constant_override("separation", 6)
	trend_values.visible = false
	trend_values_button = button("Show values", toggle_trend_values)
	section.add_child(trend_values_button)
	section.add_child(trend_values)
	section.add_child(button("How do I read the chart?", func() -> void: show_help("trends")))
	trend_source.item_selected.connect(func(_index: int) -> void: update_trend_protocols())
	trend_metric.item_selected.connect(func(_index: int) -> void: render_trend())
	trend_protocol.item_selected.connect(func(_index: int) -> void: render_trend())
	update_trend_protocols()

func update_trend_protocols() -> void:
	if current_page != "trends" or not is_instance_valid(trend_protocol):
		return
	var source: String = trend_source.get_item_metadata(trend_source.selected)
	var protocols: Dictionary = {}
	for session in trend_sessions:
		if session is Dictionary and session.get("source") == source and session.get("protocol_version") is String:
			protocols[session.protocol_version] = true
	var names := protocols.keys()
	names.sort()
	trend_protocol.clear()
	for protocol in names:
		var display: String = protocol
		if protocol.begins_with("zuma-game/"):
			var parts: PackedStringArray = str(protocol).split("/")
			if parts.size() == 4:
				var games := {"fifteen": "Fifteen Puzzle", "pairs": "Find the Pair", "math": "Speed Math", "chimp": "Remember the Numbers"}
				var levels := {"easy": "easy", "normal": "normal", "hard": "hard"}
				display = "%s • %s • %s" % [games.get(parts[1], parts[1]), levels.get(parts[2], parts[2]), parts[3]]
		trend_protocol.add_item(display)
		trend_protocol.set_item_metadata(trend_protocol.item_count - 1, protocol)
	trend_protocol.disabled = names.is_empty()
	if not names.is_empty():
		trend_protocol.select(0)
	render_trend()

func stop_trend_loader() -> void:
	trend_load_revision += 1
	if is_instance_valid(trend_loader):
		trend_loader.cancel()
		trend_loader.queue_free()
	trend_loader = null

func render_trend(load_missing: bool = true) -> void:
	if current_page != "trends" or not is_instance_valid(trend_chart):
		return
	stop_trend_loader()
	var metric: Dictionary = TREND_METRICS[trend_metric.selected]
	var source: String = trend_source.get_item_metadata(trend_source.selected)
	var protocol := "" if trend_protocol.selected < 0 else str(trend_protocol.get_item_metadata(trend_protocol.selected))
	var ordered := trend_sessions.duplicate()
	ordered.reverse()
	var matching: Array = []
	for session in ordered:
		if session is Dictionary and session.get("source") == source and session.get("protocol_version") == protocol:
			matching.append(session)
	if metric.get("kind", "survey") == "report" and load_missing:
		var missing: Array = []
		for session in matching:
			if session.get("trend_kind") != "game" and session.get("id") is String and not trend_report_cache.has(session.id):
				missing.append(session)
		if not missing.is_empty():
			load_trend_reports(missing)
			return
	var points: Array = []
	var skipped := 0
	var unavailable := 0
	var valid_points: Array = []
	var peak := 0.0
	for session in matching:
		if not session.get("performed_at") is String or str(session.performed_at).is_empty():
			skipped += 1
			points.append({"value": null, "performed_at": "Time unknown", "reason": "no check-in time"})
			continue
		var value: Variant = null
		var reason := "no data"
		if metric.get("kind", "survey") == "report" and session.get("trend_kind") == "game":
			reason = "this metric belongs to the legacy reaction and memory tasks"
		elif metric.get("kind", "survey") == "report":
			var report: Variant = trend_report_cache.get(session.get("id", ""))
			if not session.get("id") is String or str(session.id).is_empty():
				reason = "no check-in ID"
			elif not report is Dictionary:
				reason = "report unavailable"
				unavailable += 1
			elif metric.key == "memory_percent":
				value = report.get("memory_percent")
			elif report.get("reaction") is Dictionary:
				value = report.reaction.get("median_ms")
				if value == null:
					reason = "no valid trials"
		else:
			var survey: Variant = session.get("survey")
			if survey is Dictionary:
				value = survey.get(metric.key)
		var minimum := 1.0 if metric.key == "reaction_median_ms" else 0.0
		if not session_queue.is_number(value) or float(value) < minimum or float(value) > float(metric.max):
			value = null
			skipped += 1
		else:
			value = float(value)
			peak = maxf(peak, value)
		var point := {"value": value, "performed_at": session.performed_at, "reason": reason}
		points.append(point)
		if value != null:
			valid_points.append(point)
	var scale_max: float = float(metric.max)
	if metric.key == "reaction_median_ms":
		scale_max = maxf(100.0, ceilf(peak / 100.0) * 100.0)
	trend_hint.text = str(metric.hint) + (" The scale is based on the data and is not a medical reference range." if metric.key == "reaction_median_ms" else " This scale is not a medical reference range.")
	var window_count := trend_sessions.size()
	trend_summary.text = "Latest records checked across all sources: %d of %d. Available values: %d." % [window_count, trend_total + trend_game_total, valid_points.size()]
	if protocol.begins_with("zuma-game/"):
		trend_hint.text += " These are copies of saved surveys: the timestamp refers to the game, not the survey; the same copy may appear more than once."
	if trend_game_error:
		trend_summary.text += " Game runs were not loaded; refresh this section."
	if skipped > 0:
		trend_summary.text += " Missing values: %d." % skipped
	if unavailable > 0:
		trend_summary.text += " Unavailable reports: %d." % unavailable
	trend_retry.visible = unavailable > 0
	if matching.is_empty():
		trend_summary.text += " No data for the selected source and protocol."
	elif valid_points.is_empty():
		trend_summary.text += " No available values."
	trend_dates.visible = not valid_points.is_empty()
	trend_order.visible = not points.is_empty()
	if not valid_points.is_empty():
		var first: Dictionary = valid_points.front()
		var last: Dictionary = valid_points.back()
		var first_time := str(first.performed_at).replace("T", " ").replace("Z", " UTC")
		var last_time := str(last.performed_at).replace("T", " ").replace("Z", " UTC")
		trend_dates.text = "First: %s — %.1f %s  •  Latest: %s — %.1f %s" % [first_time, float(first.value), metric.unit, last_time, float(last.value), metric.unit]
	trend_chart.visible = not valid_points.is_empty()
	trend_chart.set_data(points, scale_max)
	for child in trend_values.get_children():
		trend_values.remove_child(child)
		child.queue_free()
	trend_values.visible = false
	trend_values_button.disabled = points.is_empty()
	trend_values_button.text = "Show values"
	for point in points:
		var timestamp := str(point.performed_at).replace("T", " ").replace("Z", " UTC")
		var text := str(point.reason) if point.value == null else "%.1f %s" % [float(point.value), metric.unit]
		trend_values.add_child(label("%s  •  %s" % [timestamp, text], 15, MUTED))

func load_trend_reports(sessions: Array) -> void:
	trend_hint.text = "Values come from server calculations; unavailable reports are not replaced with zero."
	trend_summary.text = "Loading reports: 0 of %d." % sessions.size()
	trend_dates.visible = false
	trend_order.visible = false
	trend_chart.visible = false
	trend_values.visible = false
	trend_values_button.disabled = true
	trend_retry.visible = false
	var revision := trend_load_revision
	var page := page_revision
	var loader := TrendReportLoader.new()
	loader.api_url = api_url
	trend_loader = loader
	add_child(loader)
	loader.progress.connect(func(completed: int, total: int) -> void:
		if current_page == "trends" and page_revision == page and trend_load_revision == revision:
			trend_summary.text = "Loading reports: %d of %d." % [completed, total]
	)
	loader.finished.connect(func(reports: Dictionary, _failures: Array) -> void:
		if current_page == "trends" and page_revision == page and trend_load_revision == revision:
			trend_report_cache.merge(reports, true)
			render_trend(false)
	)
	loader.start(sessions)

func toggle_trend_values() -> void:
	trend_values.visible = not trend_values.visible
	trend_values_button.text = "Hide values" if trend_values.visible else "Show values"

func show_history() -> void:
	clear_content("history")
	report_trail.clear()
	var revision := page_revision
	content.add_child(label("Reaction and memory check-in history", 34))
	if selected_profile.is_empty():
		content.add_child(label("Select a profile to view its history.", 17, MUTED))
		content.add_child(button("Check connection", func() -> void: refresh_profiles()))
		return
	var profile_id: String = selected_profile.id
	if profile_id != history_profile_id:
		history_profile_id = profile_id
		history_offset = 0
	var requested_offset := history_offset
	var loading := label("Loading history…", 16, MUTED)
	content.add_child(loading)
	var response := await request(HTTPClient.METHOD_GET, "/api/v1/profiles/%s/sessions?limit=%d&offset=%d" % [profile_id, HISTORY_PAGE_SIZE, requested_offset])
	if page_revision != revision or selected_profile.get("id", "") != profile_id or not is_instance_valid(loading):
		return
	loading.queue_free()
	if not response.ok:
		content.add_child(label("Could not load history. Check the server connection.", 16, Color("ffadad")))
		content.add_child(button("Retry", show_history))
		return
	if response.data.items.is_empty() and requested_offset == 0:
		content.add_child(label("There are no legacy check-ins yet. The four games are available under Games.", 17, MUTED))
		return
	var count: int = response.data.items.size()
	var total: int = int(response.data.total)
	if count > 0:
		content.add_child(label("Records %d–%d of %d • newest first" % [requested_offset + 1, requested_offset + count, total], 14, MUTED))
	else:
		content.add_child(label("There are no more records on this page.", 16, MUTED))
	var navigation := HBoxContainer.new()
	navigation.add_theme_constant_override("separation", 10)
	content.add_child(navigation)
	var previous := button("← Newer", func() -> void: show_history_page(maxi(0, requested_offset - HISTORY_PAGE_SIZE)))
	previous.disabled = requested_offset == 0
	navigation.add_child(previous)
	var next := button("Older →", func() -> void: show_history_page(requested_offset + HISTORY_PAGE_SIZE))
	next.disabled = requested_offset + count >= total or count == 0
	navigation.add_child(next)
	for session in response.data.items:
		var entry := card()
		entry.add_child(label(str(session.performed_at).replace("T", " ").replace("Z", " UTC"), 19))
		entry.add_child(label("Source: " + ("demonstration data" if session.source == "synthetic" else "check-in result"), 14, MUTED))
		if session.get("survey") is Dictionary and session.get("memory") is Dictionary:
			var survey: Dictionary = session.survey
			var memory: Dictionary = session.memory
			entry.add_child(label("Sleep: %s h  •  Fatigue: %s/10  •  Stress: %s/10  •  Mood: %s/10" % [survey.sleep_hours, survey.fatigue, survey.stress, survey.mood], 15, MUTED))
			entry.add_child(label("Memory: %d of %d answers correct" % [int(memory.correct), int(memory.total)], 15, MUTED))
		var session_id: String = session.id
		entry.add_child(button("Open report", func() -> void: show_report(session_id)))

func show_history_page(offset: int) -> void:
	history_offset = maxi(0, offset)
	show_history()

func show_report(session_id: String) -> void:
	clear_content("report")
	var revision := page_revision
	content.add_child(label("Check-in report", 34))
	var loading := label("Loading report…", 16, MUTED)
	content.add_child(loading)
	var response := await request(HTTPClient.METHOD_GET, "/api/v1/sessions/%s/report" % session_id)
	if page_revision != revision or not is_instance_valid(loading):
		return
	loading.queue_free()
	if not response.ok:
		content.add_child(label("Could not load the report.", 16, Color("ffadad")))
		content.add_child(button("Back to history", show_history))
		return
	var report: Dictionary = response.data
	var summary := card()
	summary.add_child(label(str(report.performed_at).replace("T", " ").replace("Z", " UTC"), 16, MUTED))
	if report.source == "synthetic":
		summary.add_child(label("Demonstration data", 16, ACCENT))
	var median: Variant = report.reaction.median_ms
	summary.add_child(label("Reaction: %s" % ("no valid trials" if median == null else "%.0f ms (median)" % float(median)), 22))
	summary.add_child(label("Memory: %.1f%% correct answers" % float(report.memory_percent), 22))
	summary.add_child(label("Sleep: %s h   •   Fatigue: %s/10   •   Stress: %s/10   •   Mood: %s/10" % [report.survey.sleep_hours, report.survey.fatigue, report.survey.stress, report.survey.mood], 16, MUTED))
	summary.add_child(label("Higher fatigue and stress mean more; higher mood means better.", 14, MUTED))
	if report.comparison == null:
		summary.add_child(label("There is no previous comparable check-in yet.", 16, MUTED))
	else:
		summary.add_child(label("Compared with the nearest previous check-in for the same profile, protocol, and data source.", 15, MUTED))
		summary.add_child(label("Change in memory performance since the previous check-in: %+.1f pp." % float(report.comparison.memory_delta_pp), 16, MUTED))
		if report.comparison.reaction_delta_ms != null:
			summary.add_child(label("Change in median reaction time: %+.0f ms." % float(report.comparison.reaction_delta_ms), 16, MUTED))
		else:
			summary.add_child(label("Reaction comparison is unavailable: one check-in has no valid trials.", 16, MUTED))
		var delta: Dictionary = report.comparison.survey_delta
		summary.add_child(label("Change in self-reported values: sleep %+.1f h • fatigue %+.1f • stress %+.1f • mood %+.1f" % [float(delta.sleep_hours), float(delta.fatigue), float(delta.stress), float(delta.mood)], 16, MUTED))
	var details := card()
	details.add_child(label("Details", 20))
	details.add_child(label("Reaction trials: %s valid, %s premature, %s missed." % [report.reaction.valid, report.reaction.premature, report.reaction.missed], 16, MUTED))
	if report.explanation != null:
		for category in ["observations", "comparisons", "limitations"]:
			for fact in report.explanation.get(category, []):
				details.add_child(label("• " + str(fact.text), 16, MUTED))
	else:
		details.add_child(label("The model explanation has not been created yet. The numerical report is available without it.", 16, MUTED))
	var explain_status := label("", 15, MUTED)
	details.add_child(explain_status)
	details.add_child(button("Get explanation", func() -> void: generate_explanation(session_id, revision, explain_status)))
	details.add_child(button("How do I read the results?", func() -> void: show_help("report", session_id)))
	details.add_child(button("Open print version", func() -> void: OS.shell_open(api_url + "/api/v1/sessions/%s/report.html" % session_id)))
	if report.get("baseline_session_id") != null:
		var baseline_id: String = report.baseline_session_id
		details.add_child(button("Open previous comparable check-in", func() -> void: open_baseline(session_id, baseline_id)))
	if not report_trail.is_empty():
		details.add_child(button("Back to the open report", back_to_report))
	details.add_child(button("Back to history", show_history))

func open_baseline(current_id: String, baseline_id: String) -> void:
	report_trail.append(current_id)
	show_report(baseline_id)

func back_to_report() -> void:
	if report_trail.is_empty():
		return
	var previous_id: String = report_trail.pop_back()
	show_report(previous_id)

func generate_explanation(session_id: String, revision: int, message: Label) -> void:
	if explaining:
		message.text = "Another explanation request is still running."
		return
	explaining = true
	message.text = "Creating an explanation. This may take a few minutes…"
	var response := await request(HTTPClient.METHOD_POST, "/api/v1/sessions/%s/explanation" % session_id, null, 140.0)
	explaining = false
	if page_revision != revision or not is_instance_valid(message):
		return
	if not response.ok:
		message.text = "Could not obtain an explanation. The model may be busy or the server unavailable."
	elif response.data.status == "ready":
		show_report(session_id)
	elif response.data.status == "unavailable":
		message.text = "The local model is unavailable. You can view the report without it."
	else:
		message.text = "Could not prepare the explanation. Try again later."
