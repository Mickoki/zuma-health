extends Control

signal closed

const Module = preload("res://addons/zuma_minigames/module.gd")
var module
var menu: Control
var game_area: Control
var status: Label
var level: OptionButton
var history: VBoxContainer
var profile_id := ""
var base_url := ""
var history_revision := 0
var history_offset := 0
const HISTORY_PAGE_SIZE := 10

func _ready() -> void:
	theme = preload("res://addons/zuma_minigames/theme.tres")
	var background := ColorRect.new()
	background.color = Color("08121f")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	menu = VBoxContainer.new()
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(menu)
	_add_label(menu, "ZUMA / МИНИ-ИГРЫ", 26)
	_add_label(menu, "Выберите сложность и задание. Сохранённый опрос прикрепляется к прохождению; при изменении самочувствия обновите его. Результаты не являются диагнозом.", 16)
	level = OptionButton.new()
	for title in ["Легко", "Обычно", "Сложно"]:
		level.add_item(title)
	level.select(1)
	menu.add_child(level)
	var grid := GridContainer.new()
	grid.columns = 2
	menu.add_child(grid)
	for item in [["fifteen", "Пятнашки"], ["pairs", "Найди пару"], ["math", "Математика"], ["chimp", "Запомни числа"]]:
		_add_button(grid, item[1], _launch.bind(item[0]))
	var actions := HBoxContainer.new()
	menu.add_child(actions)
	_add_button(actions, "Повторить отправку", func(): module.retry_pending())
	_add_button(actions, "Обновить историю", _load_history)
	_add_button(actions, "В приложение", _close)
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
		_update_status("Чтобы начать игру, вернитесь в приложение и сохраните опрос. История остаётся доступна.")
	else:
		_update_status("Профиль: %s. Всего в очереди на устройстве: %d" % [profile.get("display_name", ""), module.pending_count()])
	return true

func _launch(game: String) -> void:
	if module.options.survey.is_empty():
		_update_status("Чтобы начать игру, вернитесь в приложение и сохраните опрос для этого профиля.")
		return
	var error: Error = module.start_game(game, ["easy", "normal", "hard"][level.selected])
	if error != OK:
		_update_status("Не удалось открыть игру: %d" % error)
		return
	menu.get_parent().visible = false
	game_area.visible = true

func _back_to_menu() -> void:
	game_area.visible = false
	menu.get_parent().visible = true
	_load_history()

func _close() -> void:
	visible = false
	closed.emit()

func _delivery(_id: String, _state: String, message: String) -> void:
	_update_status(message + " • Всего в очереди: %d" % module.pending_count())
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
	_add_label(history, "История прохождений", 20)
	if not response.ok:
		_add_label(history, "История недоступна: проверьте подключение к серверу. Сохранённые результаты можно отправить позже.", 15)
		return
	var items: Array = response.data.get("items", [])
	if items.is_empty():
		_add_label(history, "Пока нет отправленных прохождений.", 15)
	var titles := {"fifteen": "Пятнашки", "pairs": "Найди пару", "math": "Математика", "chimp": "Запомни числа"}
	var levels := {"easy": "легко", "normal": "обычно", "hard": "сложно"}
	var statuses := {"completed": "завершено", "failed": "лимит ошибок", "aborted": "прервано"}
	for item in items:
		var run_id: String = item.get("id", "")
		var title := "%s • %s • %s\n%s • %s" % [titles.get(item.get("game_id", ""), "Игра"), levels.get(item.get("difficulty", ""), "неизвестно"), statuses.get(item.get("status", ""), "неизвестно"), "демонстрация" if item.get("source") == "synthetic" else "прохождение", str(item.get("performed_at", "")).replace("T", " ").replace("Z", " UTC")]
		var row := HBoxContainer.new()
		history.add_child(row)
		_add_button(row, title + " — отчёт", func(): OS.shell_open(base_url + "/api/v1/game-runs/" + run_id + "/report.html"))
		_add_button(row, "Объяснить", _explain.bind(run_id, profile_id))
	var total := int(response.data.get("total", 0))
	if total > HISTORY_PAGE_SIZE:
		var navigation := HBoxContainer.new()
		history.add_child(navigation)
		var previous := _add_button(navigation, "← Предыдущие", func(): history_offset = maxi(0, offset - HISTORY_PAGE_SIZE); _load_history())
		previous.disabled = offset == 0
		_add_label(navigation, "%d–%d из %d" % [offset + 1, mini(offset + items.size(), total), total], 15)
		var next := _add_button(navigation, "Следующие →", func(): history_offset = offset + HISTORY_PAGE_SIZE; _load_history())
		next.disabled = offset + items.size() >= total

func _explain(run_id: String, owner_id: String) -> void:
	_update_status("Запрашиваем объяснение модели; это может занять до двух минут.")
	var response: Dictionary = await module.transport.request(base_url, "/api/v1/game-runs/%s/explanation" % run_id, HTTPClient.METHOD_POST, null, 140.0)
	if profile_id != owner_id:
		return
	if not response.ok:
		_update_status("Объяснение не получено: " + str(response.get("error", response.status)))
	elif response.data.get("status") == "ready":
		_update_status("Объяснение готово. Откройте отчёт этого прохождения.")
	else:
		_update_status("Объяснение недоступно или не прошло проверку. Числовой отчёт доступен без модели.")

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
