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
	{"key": "sleep_hours", "name": "Сон", "unit": "ч", "max": 24.0, "hint": "Часы сна, указанные в опросе."},
	{"key": "fatigue", "name": "Усталость", "unit": "/10", "max": 10.0, "hint": "Чем выше значение, тем больше усталость."},
	{"key": "stress", "name": "Стресс", "unit": "/10", "max": 10.0, "hint": "Чем выше значение, тем больше стресс."},
	{"key": "mood", "name": "Настроение", "unit": "/10", "max": 10.0, "hint": "Чем выше значение, тем лучше настроение."},
	{"key": "memory_percent", "name": "Память", "unit": "%", "max": 100.0, "kind": "report", "hint": "Доля правильных ответов, рассчитанная сервером."},
	{"key": "reaction_median_ms", "name": "Реакция", "unit": "мс", "max": 10000.0, "kind": "report", "hint": "Медиана действительных попыток, рассчитанная сервером."}
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
	var brand := label("ZUMA / MISSION HEALTH", 21, ACCENT)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(brand)
	status_label = label("Проверяем сервер…", 14, MUTED)
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
	nav.add_theme_constant_override("separation", 8)
	sidebar.add_child(nav)
	nav.add_child(label("ПОЛЁТНАЯ ПАЛУБА", 12, MUTED))
	navigation_buttons = {"home": button("Обзор", show_home), "survey": button("Самочувствие", show_survey), "games": button("Игры", show_minigames), "history": button("История", show_history), "trends": button("Динамика", show_trends), "help": button("Справка", show_help)}
	for nav_button in navigation_buttons.values():
		nav.add_child(nav_button)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav.add_child(spacer)
	nav.add_child(label("ЛОКАЛЬНОЕ\nПРИЛОЖЕНИЕ", 12, MUTED))
	nav.add_child(button("Выход", func(): get_tree().quit()))
	profile_picker = OptionButton.new()
	profile_picker.custom_minimum_size = Vector2(210, 44)
	profile_picker.add_item("Нет профиля")
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
	root_column.add_child(label("Показатели заданий не являются медицинским диагнозом.", 13, MUTED))

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
	content.add_child(label("Ваше самочувствие в миссии", 34))
	content.add_child(label("Небольшие регулярные проверки помогают замечать изменения со временем.", 17, MUTED))
	home_queue_warning = VBoxContainer.new()
	home_queue_warning.add_theme_constant_override("separation", 8)
	content.add_child(home_queue_warning)
	if not selected_profile.is_empty():
		var latest := card()
		latest.add_child(label("ПРЕЖНИЙ ФОРМАТ ПРОВЕРКИ  /  " + str(selected_profile.display_name), 14, ACCENT))
		home_latest_section = VBoxContainer.new()
		home_latest_section.add_theme_constant_override("separation", 10)
		latest.add_child(home_latest_section)
		var game_latest := card()
		game_latest.add_child(label("ПОСЛЕДНЯЯ ИГРА  /  " + str(selected_profile.display_name), 14, ACCENT))
		home_game_latest_section = VBoxContainer.new()
		game_latest.add_child(home_game_latest_section)
	var intro := card()
	intro.add_child(label("01  /  ПРОФИЛЬ ЭКИПАЖА", 14, ACCENT))
	intro.add_child(label("Выберите профиль вверху или создайте новый", 21))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	intro.add_child(row)
	var name_input := LineEdit.new()
	name_input.placeholder_text = "Имя участника"
	name_input.max_length = 100
	name_input.custom_minimum_size = Vector2(260, 44)
	name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_input)
	row.add_child(button("Создать профиль", func() -> void: create_profile(name_input.text), true))
	intro.add_child(button("Обновить подключение и список профилей", func() -> void: refresh_profiles(selected_profile.get("id", ""))))
	var next := card()
	next.add_child(label("02  /  ЕЖЕДНЕВНАЯ ПРОВЕРКА", 14, ACCENT))
	next.add_child(label("Самочувствие → игровые задания → отчёт", 21))
	next.add_child(button("Перейти к мини-играм", show_minigames, true))
	var storage_result := label("", 14, MUTED)
	next.add_child(button("Проверить локальное сохранение", func():
		var file := FileAccess.open("user://setup_check.json", FileAccess.WRITE)
		if file == null:
			storage_result.text = "Ошибка сохранения: %d" % FileAccess.get_open_error()
			return
		file.store_string(JSON.stringify({"setup": "ok", "time": Time.get_datetime_string_from_system(true)}))
		file.flush()
		var error := file.get_error()
		file.close()
		storage_result.text = "Запись сохранена: setup_check.json" if error == OK else "Ошибка сохранения: %d" % error
	))
	next.add_child(storage_result)
	next.add_child(label("Сохраните опрос и выберите игру. Копия опроса будет прикреплена к каждому новому прохождению.", 16, MUTED))
	next.add_child(button("Заполнить опрос  →", show_survey, true))
	var history := card()
	history.add_child(label("03  /  ИСТОРИЯ МИССИИ", 14, ACCENT))
	history.add_child(label("Просматривайте прохождения игр и прежние проверки выбранного профиля.", 16, MUTED))
	history.add_child(button("Открыть историю игр", show_minigames))
	history.add_child(button("История прежних проверок", show_history))
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
	section.add_child(label("Загружаем прохождение…", 16, MUTED))
	var response := await request(HTTPClient.METHOD_GET, "/api/v1/profiles/%s/game-runs?limit=1&offset=0" % profile_id)
	if page_revision != page or home_game_latest_revision != revision or selected_profile.get("id", "") != profile_id or not is_instance_valid(section):
		return
	for child in section.get_children():
		section.remove_child(child)
		child.queue_free()
	if not response.ok:
		section.add_child(label("Не удалось загрузить игровые прохождения.", 16, MUTED))
		section.add_child(button("Повторить загрузку игр", refresh_home_game_latest))
		return
	if not response.data.get("items") is Array or response.data.items.is_empty():
		section.add_child(label("Пока нет отправленных игр. Локальные результаты доступны в разделе «Игры».", 16, MUTED))
		return
	var run: Dictionary = response.data.items[0]
	var names := {"fifteen": "Пятнашки", "pairs": "Найди пару", "math": "Математика", "chimp": "Запомни числа"}
	section.add_child(label("%s • %s • %s" % [names.get(run.get("game_id", ""), "Игра"), str(run.get("performed_at", "")).replace("T", " ").replace("Z", " UTC"), "Демонстрационные данные" if run.get("source") == "synthetic" else "Результат игры"], 16, MUTED))
	section.add_child(label("Исход: " + {"completed": "завершено", "failed": "лимит ошибок", "aborted": "прервано"}.get(run.get("status", ""), "неизвестен"), 16, MUTED))
	var run_id: String = run.get("id", "")
	if not run_id.is_empty():
		section.add_child(button("Открыть отчёт последней игры ↗", func() -> void: OS.shell_open(api_url + "/api/v1/game-runs/" + run_id + "/report.html")))

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
	section.add_child(label("Загружаем последнюю проверку…", 16, MUTED))
	var response := await request(HTTPClient.METHOD_GET, "/api/v1/profiles/%s/sessions?limit=1&offset=0" % profile_id)
	if page_revision != page or home_latest_revision != revision or selected_profile.get("id", "") != profile_id or not is_instance_valid(section):
		return
	for child in section.get_children():
		section.remove_child(child)
		child.queue_free()
	if not response.ok:
		section.add_child(label("Не удалось загрузить последнюю проверку.", 16, MUTED))
		section.add_child(button("Повторить загрузку", refresh_home_latest))
		return
	if response.data.items.is_empty():
		section.add_child(label("Пока нет сохранённых проверок этого профиля.", 16, MUTED))
		return
	var session: Dictionary = response.data.items[0]
	section.add_child(label(str(session.performed_at).replace("T", " ").replace("Z", " UTC"), 19))
	section.add_child(label("Демонстрационные данные" if session.source == "synthetic" else "Результат проверки", 14, MUTED))
	var survey: Dictionary = session.survey
	var memory: Dictionary = session.memory
	section.add_child(label("Сон: %s ч  •  Усталость: %s/10  •  Стресс: %s/10  •  Настроение: %s/10" % [survey.sleep_hours, survey.fatigue, survey.stress, survey.mood], 16, MUTED))
	section.add_child(label("Память: %d из %d ответов верные" % [int(memory.correct), int(memory.total)], 16, MUTED))
	var session_id: String = session.id
	section.add_child(button("Открыть отчёт последней проверки", func() -> void: report_trail.clear(); show_report(session_id)))

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
		var warning := "Не удалось открыть папку локальной очереди." if audit.directory_error else "Некоторые файлы очереди не удалось проверить: %d." % audit.problem_count
		home_queue_warning.add_child(label(warning + " Файлы не изменены; сохраните копию папки и обратитесь к команде.", 16, Color("ffbf8a")))
		var queue_path := LineEdit.new()
		queue_path.text = ProjectSettings.globalize_path(session_queue.queue_dir)
		queue_path.editable = false
		queue_path.custom_minimum_size.y = 42
		queue_path.add_theme_color_override("font_uneditable_color", MUTED)
		queue_path.tooltip_text = "Путь к локальной очереди"
		home_queue_warning.add_child(queue_path)
	if not selected_profile.is_empty():
		var count: int = audit.records.size()
		if count > 0:
			home_pending_section.add_child(label("Ожидают отправки: %d" % count, 16, ACCENT))
			home_pending_section.add_child(button("Отправить сохранённые проверки", send_pending))

func show_survey() -> void:
	clear_content("survey")
	survey_inputs.clear()
	content.add_child(label("Как вы себя чувствуете?", 34))
	content.add_child(label("Заполните все поля. Несохранённый ввод доступен, пока приложение открыто; сохранённый черновик хранится на этом устройстве для выбранного профиля.", 16, MUTED))
	if selected_profile.is_empty():
		content.add_child(label("Сначала выберите или создайте профиль на экране обзора.", 18, ACCENT))
		return
	var form := card()
	var draft: Dictionary = drafts.get(selected_profile.id, {})
	add_survey_field(form, "sleep_hours", "Сон", "Сколько часов вы спали?  •  0–24 часа", draft)
	add_survey_field(form, "fatigue", "Усталость", "0 — нет усталости  •  10 — сильная усталость", draft)
	add_survey_field(form, "stress", "Стресс", "0 — нет стресса  •  10 — сильный стресс", draft)
	add_survey_field(form, "mood", "Настроение", "0 — очень плохое  •  10 — отличное", draft)
	survey_status = label("", 15, MUTED)
	form.add_child(survey_status)
	if survey_edits.has(selected_profile.id):
		survey_status.text = "Есть несохранённые изменения."
	form.add_child(button("Сохранить черновик", func() -> void: save_survey(), true))
	form.add_child(button("Как заполнить опрос?", func() -> void: show_help("survey")))
	if games_available():
		form.add_child(button("Начать игровые задания →", start_game_run))
	else:
		form.add_child(label("Сохраните опрос, затем откройте раздел «Игры». К каждому прохождению будет прикреплена сохранённая копия.", 15, MUTED))

func show_minigames() -> void:
	if selected_profile.is_empty():
		clear_content("games")
		content.add_child(label("Для игр сначала создайте или выберите профиль на экране обзора.", 20, ACCENT))
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
		set_connection_status("Игры: дождитесь отправки или проверьте доступ к очереди.")

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
	input.placeholder_text = "Введите"
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
			survey_status.text = "Есть несохранённые изменения."
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
		set_survey_status("Не удалось прочитать прежние черновики. Сохранение остановлено, чтобы не перезаписать файл.", Color("ffadad"))
		return false
	var draft := {}
	for key in survey_inputs:
		var value_text: String = survey_inputs[key].text.strip_edges().replace(",", ".")
		if not value_text.is_valid_float():
			set_survey_status("Заполните все поля числами от 0 до 10 (сон — от 0 до 24).", Color("ffadad"))
			return false
		var value := value_text.to_float()
		var maximum := 24.0 if key == "sleep_hours" else 10.0
		if not is_finite(value) or value < 0.0 or value > maximum:
			set_survey_status("Проверьте диапазоны: сон — от 0 до 24, остальные показатели — от 0 до 10.", Color("ffadad"))
			return false
		draft[key] = value
	var updated := drafts.duplicate(true)
	updated[selected_profile.id] = draft
	var temp_path := draft_path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		set_survey_status("Не удалось сохранить черновик на устройстве.", Color("ffadad"))
		return false
	file.store_string(JSON.stringify(updated))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		set_survey_status("Не удалось сохранить черновик на устройстве.", Color("ffadad"))
		return false
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(draft_path)) != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		set_survey_status("Не удалось сохранить черновик на устройстве.", Color("ffadad"))
		return false
	drafts = updated
	survey_edits.erase(selected_profile.id)
	set_survey_status("Черновик сохранён на этом устройстве.", ACCENT)
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
	content.add_child(label("Задание 1 / 2 • Реакция" if kind == "reaction" else "Задание 2 / 2 • Память", 30))
	content.add_child(label("Переключение раздела и профиля доступно после завершения или отмены проверки.", 14, MUTED))
	var scene: PackedScene = load(game_scene_paths[kind]) as PackedScene
	if scene == null:
		game_error("Не удалось загрузить игровую сцену.")
		return
	var game := scene.instantiate()
	if not game is Control or not game.has_signal("completed") or not game.has_signal("cancelled"):
		game.free()
		game_error("Игровая сцена не поддерживает нужный интерфейс.")
		return
	# A plain Control has a zero minimum height in a VBoxContainer. Give every
	# game a usable drawing/input area while respecting larger scene minima.
	game.custom_minimum_size.y = maxf(game.custom_minimum_size.y, 360.0)
	game.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	game.completed.connect(func(result: Dictionary) -> void: complete_game(kind, revision, result), CONNECT_DEFERRED)
	game.cancelled.connect(func() -> void: cancel_game(revision), CONNECT_DEFERRED)
	content.add_child(button("Отменить проверку", func() -> void: cancel_game(revision)))
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
	content.add_child(label("Проверка не сохранена. Вернитесь к опросу и попробуйте снова.", 16, MUTED))
	content.add_child(button("Вернуться к опросу", show_survey))

func complete_game(kind: String, revision: int, result: Dictionary) -> void:
	if current_page != "game" or page_revision != revision or active_run.is_empty():
		return
	if selected_profile.get("id", "") != active_run.profile_id or result.get("protocol_version") != session_queue.PROTOCOL:
		game_error("Результат задания не соответствует профилю или согласованному протоколу.")
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
		content.add_child(label("Результаты остаются в памяти до выхода с этого экрана.", 16, MUTED))
		if outcome.error == "storage_unavailable":
			content.add_child(button("Повторить сохранение", finish_game_run))
		content.add_child(button("Вернуться к опросу", func() -> void: active_run.clear(); show_survey()))
		return
	content.add_child(label("Проверка сохранена на устройстве", 30, ACCENT))
	content.add_child(label("Отправьте её на сервер, чтобы открыть отчёт. При сбое её можно будет отправить повторно.", 16, MUTED))
	var send_status := label("", 16, MUTED)
	content.add_child(send_status)
	var revision := page_revision
	var queue_id: String = outcome.id
	content.add_child(button("Отправить и открыть отчёт", func() -> void: send_completed_session(profile_id, queue_id, revision, send_status), true))
	content.add_child(button("На обзор", show_home))

func game_save_error_message(code: String) -> String:
	match code:
		"storage_unavailable":
			return "Не удалось сохранить проверку на устройстве."
		"invalid_profile":
			return "Профиль проверки не распознан."
		"incompatible_protocol":
			return "Версии игровых заданий не совпадают с протоколом."
		"invalid_survey":
			return "Данные опроса не соответствуют допустимому формату."
		"invalid_reaction":
			return "Результаты задания на реакцию имеют неверный формат."
		"invalid_memory":
			return "Результаты задания на память имеют неверный формат."
	return "Не удалось сохранить проверку."

func send_completed_session(profile_id: String, queue_id: String, revision: int, message: Label) -> void:
	if page_revision != revision or selected_profile.get("id", "") != profile_id or not is_instance_valid(message):
		return
	if sending_pending:
		message.text = "Дождитесь завершения текущей отправки."
		return
	var record: Dictionary = {}
	var audit: Dictionary = session_queue.inspect_queue(profile_id)
	for pending_record in audit.records:
		if pending_record.payload.client_session_id == queue_id:
			record = pending_record
			break
	if record.is_empty():
		message.text = "Не удалось проверить локальную очередь. Откройте обзор для подробностей." if audit.directory_error or audit.problem_count > 0 else "Проверка не найдена в очереди. Проверьте историю."
		return
	sending_pending = true
	message.text = "Отправляем проверку…"
	var response: Dictionary = await session_queue.send(record)
	sending_pending = false
	if page_revision != revision or selected_profile.get("id", "") != profile_id or not is_instance_valid(message):
		if selected_profile.get("id", "") == profile_id:
			set_connection_status("Проверка отправлена • отчёт доступен в истории" if response.ok else pending_error_message(response))
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
		content.add_child(button("Открыть сохранённый отчёт", func() -> void: report_trail.clear(); show_report(session_id)))

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
		set_connection_status("Сервер недоступен • запустите Go API")
		status_label.add_theme_color_override("font_color", Color("ffbf8a"))
		return
	set_connection_status("Сервер подключён")
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
		profile_picker.add_item("Нет профиля")
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
		set_connection_status("Введите имя профиля")
		return
	set_connection_status("Создаём профиль…")
	creating_profile = true
	var response := await request(HTTPClient.METHOD_POST, "/api/v1/profiles", {"display_name": trimmed})
	creating_profile = false
	if not response.ok:
		set_connection_status("Не удалось создать профиль • проверьте сервер")
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
		set_connection_status("Не удалось открыть локальную очередь • проверьте обзор")
		refresh_home_pending()
		return
	set_connection_status("Отправляем сохранённые проверки…")
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
		set_connection_status("Есть непроверенные файлы очереди • проверьте обзор")
		status_label.add_theme_color_override("font_color", Color("ffbf8a"))
	elif records.is_empty():
		set_connection_status("Нет проверок для отправки")
	else:
		set_connection_status("Проверки отправлены")
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
		return "Сервер сохранил проверку, но локальная копия осталась в очереди"
	var status := int(failure.get("status", 0))
	if status == 409:
		return "Конфликт идентификатора проверки • нужна проверка данных"
	if status == 400 or status == 422:
		return "Сервер отклонил данные проверки • нужна проверка формата"
	if status == 404:
		return "Профиль не найден на сервере • проверьте подключённую базу"
	return "Не удалось отправить проверку • повторите позже"

func show_help(origin: String = "", session_id: String = "") -> void:
	var profile_id: String = selected_profile.get("id", "")
	clear_content("help")
	content.add_child(label("Как пользоваться Zuma", 34))
	content.add_child(label("Краткая справка доступна без интернета. Это прототип для наблюдения, не медицинская консультация.", 16, MUTED))
	var why := card()
	why.add_child(label("Почему эти показатели?", 21, ACCENT))
	why.add_child(label("NASA изучает влияние недостатка сна и нарушений суточных ритмов на усталость и выполнение задач [1]. Изоляция и замкнутое пространство также могут влиять на когнитивные и поведенческие функции [2]. Эти материалы дают контекст, но не подтверждают медицинскую пригодность заданий Zuma.", 16, MUTED))
	var survey := card()
	survey.add_child(label("Как заполнить опрос", 21, ACCENT))
	survey.add_child(label("Выберите свой профиль и заполните все поля. Сон укажите в часах от 0 до 24; используйте один и тот же период, согласованный командой. Этот прототип не сохраняет период сна отдельно.", 16, MUTED))
	survey.add_child(label("Усталость и стресс: от 0 до 10, где большее число означает более сильное ощущение. Настроение: от 0 до 10, где большее число означает лучшее настроение. Ноль — допустимый ответ, пустое поле не считается нулём.", 16, MUTED))
	survey.add_child(label("Черновик хранится на устройстве после нажатия «Сохранить черновик». Его копия прикрепляется к каждой новой игре. Если состояние изменилось, обновите опрос перед следующей игрой.", 16, MUTED))
	var results := card()
	results.add_child(label("Как читать результаты", 21, ACCENT))
	results.add_child(label("Реакция — медиана времени действительных попыток в миллисекундах: среднее двух центральных значений или центральное значение упорядоченного ряда. Без действительных попыток она не рассчитывается. Память — доля правильных ответов. Эти результаты описывают задания и не являются диагнозом.", 16, MUTED))
	results.add_child(label("Сравнение строится с ближайшей более ранней проверкой того же профиля, протокола и источника данных. Если такой проверки нет, сравнение не показывается. Демонстрационные данные не смешиваются с результатами проверок.", 16, MUTED))
	results.add_child(label("Игровые отчёты сравнивают только сопоставимые прохождения той же игры, сложности, правил и источника. Прерванные попытки не сравниваются. Время точки с игровым опросом — время игры, а не заполнения опроса.", 16, MUTED))
	results.add_child(label("На графике расстояние между точками показывает порядок проверок, а не длительность между ними. Пропуски не соединяются; точные даты и значения доступны списком.", 16, MUTED))
	var actions := card()
	actions.add_child(label("Что можно сделать дальше", 21, ACCENT))
	actions.add_child(label("Проверьте, актуален ли сохранённый опрос, и откройте историю или график, чтобы увидеть изменения. При беспокоящих симптомах или вопросах о результатах следуйте протоколу миссии и свяжитесь с медицинским специалистом. Игровые показатели не задают пороги для лечения.", 16, MUTED))
	var limits := card()
	limits.add_child(label("Ограничения", 21, ACCENT))
	limits.add_child(label("Для шкал самооценки и игровых заданий этого прототипа нет подтверждённой клинической валидации. Приложение не измеряет давление, пульс или другие показатели датчиками и не назначает лечение. При вопросах о здоровье следуйте медицинскому протоколу миссии и обращайтесь к специалисту согласно правилам экипажа.", 16, MUTED))
	limits.add_child(label("Локальная модель, если она доступна, выбирает проверенные сервером факты для объяснения. Её вывод не заменяет медицинскую консультацию.", 16, MUTED))
	var sources := card()
	sources.add_child(label("Источники NASA", 21, ACCENT))
	sources.add_child(label("Ссылки открываются в браузере и требуют подключения к интернету.", 15, MUTED))
	sources.add_child(button("[1] NASA: сон и работоспособность ↗", func() -> void: OS.shell_open(NASA_SLEEP_URL)))
	sources.add_child(button("[2] NASA: поведенческие и когнитивные риски ↗", func() -> void: OS.shell_open(NASA_BEHAVIOR_URL)))
	sources.add_child(button("Задача NASA Space Apps ↗", func() -> void: OS.shell_open(NASA_CHALLENGE_URL)))
	if origin in ["survey", "report", "trends"]:
		content.add_child(button("Вернуться", func() -> void:
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
	content.add_child(label("Динамика самочувствия", 34))
	if selected_profile.is_empty():
		content.add_child(label("Выберите профиль, чтобы увидеть динамику.", 17, MUTED))
		return
	var profile_id: String = selected_profile.id
	content.add_child(label("Профиль: " + str(selected_profile.display_name) + " • Результаты не являются медицинской оценкой.", 16, MUTED))
	var loading := label("Загружаем проверки…", 16, MUTED)
	content.add_child(loading)
	var response := await request(HTTPClient.METHOD_GET, "/api/v1/profiles/%s/sessions?limit=100&offset=0" % profile_id)
	if page_revision != revision or selected_profile.get("id", "") != profile_id or not is_instance_valid(loading):
		return
	loading.queue_free()
	if not response.ok:
		content.add_child(label("Не удалось загрузить проверки. Проверьте подключение к серверу.", 16, Color("ffadad")))
		content.add_child(button("Повторить", show_trends))
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
	trend_metric = trend_picker(filters, "Показатель")
	for metric in TREND_METRICS:
		trend_metric.add_item(metric.name)
	trend_metric.select(0)
	trend_source = trend_picker(filters, "Источник данных")
	trend_source.add_item("Результаты проверок")
	trend_source.set_item_metadata(0, "observed")
	trend_source.add_item("Демонстрационные")
	trend_source.set_item_metadata(1, "synthetic")
	trend_source.select(0)
	trend_protocol = trend_picker(filters, "Протокол")
	trend_hint = label("", 15, MUTED)
	section.add_child(trend_hint)
	trend_summary = label("", 15, MUTED)
	section.add_child(trend_summary)
	trend_retry = button("Повторить загрузку отчётов", func() -> void: render_trend())
	trend_retry.visible = false
	section.add_child(trend_retry)
	trend_dates = label("", 14, MUTED)
	section.add_child(trend_dates)
	trend_order = label("Слева старые проверки, справа новые. Расстояние между ними одинаковое и не отражает интервалы времени; пропуски не соединяются.", 14, MUTED)
	section.add_child(trend_order)
	trend_chart = SurveyChart.new()
	section.add_child(trend_chart)
	trend_values = VBoxContainer.new()
	trend_values.add_theme_constant_override("separation", 6)
	trend_values.visible = false
	trend_values_button = button("Показать значения", toggle_trend_values)
	section.add_child(trend_values_button)
	section.add_child(trend_values)
	section.add_child(button("Как читать график?", func() -> void: show_help("trends")))
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
				var games := {"fifteen": "Пятнашки", "pairs": "Найди пару", "math": "Математика", "chimp": "Запомни числа"}
				var levels := {"easy": "легко", "normal": "обычно", "hard": "сложно"}
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
			points.append({"value": null, "performed_at": "Время неизвестно", "reason": "нет времени проверки"})
			continue
		var value: Variant = null
		var reason := "нет данных"
		if metric.get("kind", "survey") == "report" and session.get("trend_kind") == "game":
			reason = "этот показатель относится к прежним заданиям реакции и памяти"
		elif metric.get("kind", "survey") == "report":
			var report: Variant = trend_report_cache.get(session.get("id", ""))
			if not session.get("id") is String or str(session.id).is_empty():
				reason = "нет идентификатора проверки"
			elif not report is Dictionary:
				reason = "отчёт недоступен"
				unavailable += 1
			elif metric.key == "memory_percent":
				value = report.get("memory_percent")
			elif report.get("reaction") is Dictionary:
				value = report.reaction.get("median_ms")
				if value == null:
					reason = "нет действительных попыток"
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
	trend_hint.text = str(metric.hint) + (" Масштаб выбран по данным и не является медицинской нормой." if metric.key == "reaction_median_ms" else " Шкала не является медицинской нормой.")
	var window_count := trend_sessions.size()
	trend_summary.text = "Проверено последних записей всех источников: %d из %d. Доступных значений: %d." % [window_count, trend_total + trend_game_total, valid_points.size()]
	if protocol.begins_with("zuma-game/"):
		trend_hint.text += " Это копии сохранённого опроса: отметка времени относится к игре, а не к заполнению опроса; одна копия может повторяться."
	if trend_game_error:
		trend_summary.text += " Игровые прохождения не загружены; обновите раздел."
	if skipped > 0:
		trend_summary.text += " Без значения: %d." % skipped
	if unavailable > 0:
		trend_summary.text += " Отчётов недоступно: %d." % unavailable
	trend_retry.visible = unavailable > 0
	if matching.is_empty():
		trend_summary.text += " Нет данных для выбранных источника и протокола."
	elif valid_points.is_empty():
		trend_summary.text += " Нет доступных значений."
	trend_dates.visible = not valid_points.is_empty()
	trend_order.visible = not points.is_empty()
	if not valid_points.is_empty():
		var first: Dictionary = valid_points.front()
		var last: Dictionary = valid_points.back()
		var first_time := str(first.performed_at).replace("T", " ").replace("Z", " UTC")
		var last_time := str(last.performed_at).replace("T", " ").replace("Z", " UTC")
		trend_dates.text = "Первая: %s — %.1f %s  •  Последняя: %s — %.1f %s" % [first_time, float(first.value), metric.unit, last_time, float(last.value), metric.unit]
	trend_chart.visible = not valid_points.is_empty()
	trend_chart.set_data(points, scale_max)
	for child in trend_values.get_children():
		trend_values.remove_child(child)
		child.queue_free()
	trend_values.visible = false
	trend_values_button.disabled = points.is_empty()
	trend_values_button.text = "Показать значения"
	for point in points:
		var timestamp := str(point.performed_at).replace("T", " ").replace("Z", " UTC")
		var text := str(point.reason) if point.value == null else "%.1f %s" % [float(point.value), metric.unit]
		trend_values.add_child(label("%s  •  %s" % [timestamp, text], 15, MUTED))

func load_trend_reports(sessions: Array) -> void:
	trend_hint.text = "Значения берутся из расчётов сервера; недоступные отчёты не заменяются нулём."
	trend_summary.text = "Загружаем отчёты: 0 из %d." % sessions.size()
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
			trend_summary.text = "Загружаем отчёты: %d из %d." % [completed, total]
	)
	loader.finished.connect(func(reports: Dictionary, _failures: Array) -> void:
		if current_page == "trends" and page_revision == page and trend_load_revision == revision:
			trend_report_cache.merge(reports, true)
			render_trend(false)
	)
	loader.start(sessions)

func toggle_trend_values() -> void:
	trend_values.visible = not trend_values.visible
	trend_values_button.text = "Скрыть значения" if trend_values.visible else "Показать значения"

func show_history() -> void:
	clear_content("history")
	report_trail.clear()
	var revision := page_revision
	content.add_child(label("История проверок реакции и памяти", 34))
	content.add_child(label("История четырёх игр доступна в разделе «Игры».", 16, MUTED))
	if selected_profile.is_empty():
		content.add_child(label("Выберите профиль, чтобы увидеть его историю.", 17, MUTED))
		content.add_child(button("Проверить подключение", func() -> void: refresh_profiles()))
		return
	content.add_child(label("Профиль: " + str(selected_profile.display_name), 16, MUTED))
	var profile_id: String = selected_profile.id
	if profile_id != history_profile_id:
		history_profile_id = profile_id
		history_offset = 0
	var requested_offset := history_offset
	var loading := label("Загружаем историю…", 16, MUTED)
	content.add_child(loading)
	var response := await request(HTTPClient.METHOD_GET, "/api/v1/profiles/%s/sessions?limit=%d&offset=%d" % [profile_id, HISTORY_PAGE_SIZE, requested_offset])
	if page_revision != revision or selected_profile.get("id", "") != profile_id or not is_instance_valid(loading):
		return
	loading.queue_free()
	if not response.ok:
		content.add_child(label("Не удалось загрузить историю. Проверьте подключение к серверу.", 16, Color("ffadad")))
		content.add_child(button("Повторить", show_history))
		return
	if response.data.items.is_empty() and requested_offset == 0:
		content.add_child(label("Пока нет проверок прежнего формата. Прохождения четырёх игр доступны в разделе «Игры».", 17, MUTED))
		return
	var count: int = response.data.items.size()
	var total: int = int(response.data.total)
	if count > 0:
		content.add_child(label("Записи %d–%d из %d • сначала новые" % [requested_offset + 1, requested_offset + count, total], 14, MUTED))
	else:
		content.add_child(label("На этой странице больше нет записей.", 16, MUTED))
	var navigation := HBoxContainer.new()
	navigation.add_theme_constant_override("separation", 10)
	content.add_child(navigation)
	var previous := button("← Новее", func() -> void: show_history_page(maxi(0, requested_offset - HISTORY_PAGE_SIZE)))
	previous.disabled = requested_offset == 0
	navigation.add_child(previous)
	var next := button("Старее →", func() -> void: show_history_page(requested_offset + HISTORY_PAGE_SIZE))
	next.disabled = requested_offset + count >= total or count == 0
	navigation.add_child(next)
	for session in response.data.items:
		var entry := card()
		entry.add_child(label(str(session.performed_at).replace("T", " ").replace("Z", " UTC"), 19))
		entry.add_child(label("Источник: " + ("демонстрационные данные" if session.source == "synthetic" else "результат проверки"), 14, MUTED))
		if session.get("survey") is Dictionary and session.get("memory") is Dictionary:
			var survey: Dictionary = session.survey
			var memory: Dictionary = session.memory
			entry.add_child(label("Сон: %s ч  •  Усталость: %s/10  •  Стресс: %s/10  •  Настроение: %s/10" % [survey.sleep_hours, survey.fatigue, survey.stress, survey.mood], 15, MUTED))
			entry.add_child(label("Память: %d из %d ответов верные" % [int(memory.correct), int(memory.total)], 15, MUTED))
		var session_id: String = session.id
		entry.add_child(button("Открыть отчёт", func() -> void: show_report(session_id)))

func show_history_page(offset: int) -> void:
	history_offset = maxi(0, offset)
	show_history()

func show_report(session_id: String) -> void:
	clear_content("report")
	var revision := page_revision
	content.add_child(label("Отчёт о проверке", 34))
	var loading := label("Загружаем отчёт…", 16, MUTED)
	content.add_child(loading)
	var response := await request(HTTPClient.METHOD_GET, "/api/v1/sessions/%s/report" % session_id)
	if page_revision != revision or not is_instance_valid(loading):
		return
	loading.queue_free()
	if not response.ok:
		content.add_child(label("Не удалось загрузить отчёт.", 16, Color("ffadad")))
		content.add_child(button("Вернуться к истории", show_history))
		return
	var report: Dictionary = response.data
	var summary := card()
	summary.add_child(label(str(report.performed_at).replace("T", " ").replace("Z", " UTC"), 16, MUTED))
	if report.source == "synthetic":
		summary.add_child(label("Демонстрационные данные", 16, ACCENT))
	var median: Variant = report.reaction.median_ms
	summary.add_child(label("Реакция: %s" % ("нет действительных попыток" if median == null else "%.0f мс (медиана)" % float(median)), 22))
	summary.add_child(label("Память: %.1f%% правильных ответов" % float(report.memory_percent), 22))
	summary.add_child(label("Сон: %s ч   •   Усталость: %s/10   •   Стресс: %s/10   •   Настроение: %s/10" % [report.survey.sleep_hours, report.survey.fatigue, report.survey.stress, report.survey.mood], 16, MUTED))
	summary.add_child(label("Усталость и стресс: выше — больше; настроение: выше — лучше.", 14, MUTED))
	if report.comparison == null:
		summary.add_child(label("Пока нет предыдущей сопоставимой проверки для сравнения.", 16, MUTED))
	else:
		summary.add_child(label("Сравнение с ближайшей предыдущей проверкой того же профиля, протокола и источника данных.", 15, MUTED))
		summary.add_child(label("Изменение памяти относительно предыдущей проверки: %+.1f п.п." % float(report.comparison.memory_delta_pp), 16, MUTED))
		if report.comparison.reaction_delta_ms != null:
			summary.add_child(label("Изменение медианы реакции: %+.0f мс." % float(report.comparison.reaction_delta_ms), 16, MUTED))
		else:
			summary.add_child(label("Сравнение реакции недоступно: в одной из проверок нет действительных попыток.", 16, MUTED))
		var delta: Dictionary = report.comparison.survey_delta
		summary.add_child(label("Изменение самооценки: сон %+.1f ч • усталость %+.1f • стресс %+.1f • настроение %+.1f" % [float(delta.sleep_hours), float(delta.fatigue), float(delta.stress), float(delta.mood)], 16, MUTED))
	var details := card()
	details.add_child(label("Подробнее", 20))
	details.add_child(label("Попытки реакции: %s действительных, %s преждевременных, %s пропущенных." % [report.reaction.valid, report.reaction.premature, report.reaction.missed], 16, MUTED))
	if report.explanation != null:
		for category in ["observations", "comparisons", "limitations"]:
			for fact in report.explanation.get(category, []):
				details.add_child(label("• " + str(fact.text), 16, MUTED))
	else:
		details.add_child(label("Объяснение модели ещё не создано. Числовой отчёт доступен и без него.", 16, MUTED))
	var explain_status := label("", 15, MUTED)
	details.add_child(explain_status)
	details.add_child(button("Получить объяснение", func() -> void: generate_explanation(session_id, revision, explain_status)))
	details.add_child(button("Как читать результаты?", func() -> void: show_help("report", session_id)))
	details.add_child(button("Открыть версию для печати", func() -> void: OS.shell_open(api_url + "/api/v1/sessions/%s/report.html" % session_id)))
	if report.get("baseline_session_id") != null:
		var baseline_id: String = report.baseline_session_id
		details.add_child(button("Открыть предыдущую сопоставимую проверку", func() -> void: open_baseline(session_id, baseline_id)))
	if not report_trail.is_empty():
		details.add_child(button("Вернуться к открытому отчёту", back_to_report))
	details.add_child(button("Вернуться к истории", show_history))

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
		message.text = "Другой запрос объяснения ещё выполняется."
		return
	explaining = true
	message.text = "Создаём объяснение. Это может занять несколько минут…"
	var response := await request(HTTPClient.METHOD_POST, "/api/v1/sessions/%s/explanation" % session_id, null, 140.0)
	explaining = false
	if page_revision != revision or not is_instance_valid(message):
		return
	if not response.ok:
		message.text = "Не удалось получить объяснение. Возможно, модель занята или сервер недоступен."
	elif response.data.status == "ready":
		show_report(session_id)
	elif response.data.status == "unavailable":
		message.text = "Локальная модель недоступна. Отчёт можно просмотреть без неё."
	else:
		message.text = "Объяснение не удалось подготовить. Попробуйте позже."
