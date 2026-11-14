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
	theme = preload("res://addons/zuma_minigames/theme.tres")
	var background := ColorRect.new()
	background.color = Color("08121f")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
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
	brand.text = "ZUMA / МИНИ-ИГРЫ"
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
	intro.text = "Выберите задание\nМожно играть без подключения к серверу."
	intro.add_theme_font_size_override("font_size", 23)
	content.add_child(intro)
	var level_row := HBoxContainer.new()
	content.add_child(level_row)
	var level_label := Label.new()
	level_label.text = "Сложность: "
	level_row.add_child(level_label)
	difficulty_picker = OptionButton.new()
	for title in ["Легко", "Обычно", "Сложно"]:
		difficulty_picker.add_item(title)
	difficulty_picker.select(1)
	level_row.add_child(difficulty_picker)
	var games := GridContainer.new()
	games.columns = 2
	games.add_theme_constant_override("h_separation", 12)
	games.add_theme_constant_override("v_separation", 12)
	content.add_child(games)
	for item in [["fifteen", "Пятнашки\nСоберите поле 4×4"], ["pairs", "Найди пару\nЗапомните карточки"], ["math", "Математика\nОтветьте быстрее таймера"], ["chimp", "Запомни числа\nВосстановите порядок"]]:
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
	profile_picker.add_item("Без серверного профиля")
	profile_picker.item_selected.connect(_select_profile)
	profile_row.add_child(profile_picker)
	profile_name = LineEdit.new()
	profile_name.placeholder_text = "Имя нового профиля"
	profile_name.max_length = 100
	profile_name.custom_minimum_size.x = 210
	profile_row.add_child(profile_name)
	_button(profile_row, "Создать профиль", _create_profile)
	_button(profile_row, "Обновить", _load_profiles)
	var delivery_row := HBoxContainer.new()
	content.add_child(delivery_row)
	_button(delivery_row, "Привязать локальные результаты", _bind_local)
	_button(delivery_row, "Повторить отправку", func(): module.retry_pending())
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", 15)
	status.text = "Выберите профиль для новых игр. Ранее локальные результаты привязываются отдельной кнопкой."
	content.add_child(status)
	var note := Label.new()
	note.text = "Показатели заданий не являются медицинским диагнозом."
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
		status.text = "Выбранный профиль не применён. Повторите выбор перед игрой."
		return
	var error: Error = module.start_game(game, ["easy", "normal", "hard"][difficulty_picker.selected])
	if error != OK:
		status.text = "Не удалось открыть игру: " + str(error)
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
		status.text = "Сервер недоступен. Игры работают, результаты сохраняются локально."
		return
	profiles = response.data.get("items", [])
	profile_picker.clear()
	profile_picker.add_item("Без серверного профиля")
	for profile in profiles:
		profile_picker.add_item(profile.display_name)
	_restore_selection()
	status.text = "Сервер доступен. Выберите профиль для новых игр."

func _select_profile(index: int) -> void:
	var profile: String = "" if index == 0 else profiles[index - 1].id
	if profile.is_empty():
		_prepare_local_owner()
	var owner: String = _local_owner if profile.is_empty() else "profile:" + profile
	var error: Error = module.configure({"owner_key": owner, "profile_id": profile})
	if error != OK:
		_restore_selection()
		status.text = "Не удалось сменить профиль (код %d). Дождитесь отправки или устраните ошибку записи." % error
		return
	selected_profile = profile
	status.text = "Профиль выбран для новых игр. Старые записи не переназначены."

func _create_profile() -> void:
	if profile_name.text.strip_edges().is_empty():
		status.text = "Введите имя профиля."
		return
	var response: Dictionary = await module.transport.request(module.options.base_url, "/api/v1/profiles", HTTPClient.METHOD_POST, {"display_name": profile_name.text.strip_edges()}, 3.0)
	if not response.ok:
		status.text = "Профиль не создан: " + str(response.get("error", "ошибка"))
		return
	var created_id: String = response.data.id
	var error: Error = module.configure({"owner_key": "profile:" + created_id, "profile_id": created_id})
	if error == OK:
		selected_profile = created_id
	else:
		_restore_selection()
	await _load_profiles()
	status.text = "Профиль создан и выбран." if error == OK else "Профиль создан, но не выбран (код %d). Действующим остался прежний профиль." % error

func _bind_local() -> void:
	if selected_profile.is_empty():
		status.text = "Сначала выберите серверный профиль."
		return
	var error: Error = module.bind_owner(_local_owner, selected_profile)
	if error != OK:
		status.text = "Локальный владелец уже связан с другим профилем либо очередь недоступна (код %d)." % error
		return
	status.text = "Локальные записи явно привязаны к выбранному профилю."
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
	profiles.append({"id": selected_profile, "display_name": "Текущий профиль " + selected_profile.left(8)})
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
		status.text = "Не удалось сохранить локального владельца. Результаты не будут переназначены."

func _delivery(_id: String, state: String, message: String) -> void:
	status.text = message.left(250)
	queue_label.tooltip_text = state + ": " + message
	_refresh_count()

func _refresh_count() -> void:
	queue_label.text = "Ожидают отправки: %d" % module.pending_count()

func _button(parent: Node, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
