extends Control

signal run_finished(payload: Dictionary)
signal exit_requested
const Rules = preload("res://addons/zuma_minigames/core/rules.gd")
const Generator = preload("res://addons/zuma_minigames/core/generator.gd")
const TITLES: Dictionary = {"fifteen": "Пятнашки", "pairs": "Найди пару", "math": "Математика на скорость", "chimp": "Запомни числа"}
const INSTRUCTIONS: Dictionary = {
	"fifteen": "Соберите числа 1–15 по порядку. Нажимайте на плитку рядом с пустой клеткой. Время и ходы учитываются.",
	"pairs": "Запомните открытые карточки. После скрытия находите пары одинаковых символов, открывая по две карточки.",
	"math": "Выберите правильный ответ. До 20 разных примеров за 60 секунд. Ответ на границе таймера уже не принимается.",
	"chimp": "Запомните расположение чисел. Выбирайте по возрастанию: после нажатия на 1 остальные числа скроются."
}
@export_enum("fifteen", "pairs", "math", "chimp") var game_id: String = "fifteen"
var difficulty: String = "easy"
var source: String = "observed"
var generator = Generator.new()
var session = null
var start_button: Button
var restart_button: Button
var skip_button: Button
var next_button: Button
var grid: GridContainer
var stats: Label
var help_label: Label
var question_label: Label
var result_label: Label
var _started_at: int = 0
var _emitted: bool = false

func _ready() -> void:
	theme = preload("res://addons/zuma_minigames/theme.tres")
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 14)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var heading := Label.new()
	heading.text = TITLES[game_id] + "  /  " + {"easy": "ЛЕГКО", "normal": "ОБЫЧНО", "hard": "СЛОЖНО"}[difficulty]
	heading.add_theme_font_size_override("font_size", 25)
	column.add_child(heading)
	help_label = Label.new()
	help_label.text = INSTRUCTIONS[game_id] + " Потеря фокуса прерывает попытку."
	help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_label.add_theme_font_size_override("font_size", 15)
	column.add_child(help_label)
	stats = Label.new()
	column.add_child(stats)
	question_label = Label.new()
	question_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question_label.add_theme_font_size_override("font_size", 30)
	question_label.visible = false
	column.add_child(question_label)
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(center)
	grid = GridContainer.new()
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 4)
	center.add_child(grid)
	result_label = Label.new()
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_label.add_theme_font_size_override("font_size", 15)
	column.add_child(result_label)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	column.add_child(actions)
	start_button = _button(actions, "Начать", _start)
	start_button.name = "Start"
	restart_button = _button(actions, "Заново", _restart)
	skip_button = _button(actions, "Пропустить", _skip)
	next_button = _button(actions, "Следующий раунд", _next_round)
	_button(actions, "Назад", _back)
	stats.text = _parameters()
	result_label.text = "Результаты описывают выполнение задания и не являются диагнозом."
	restart_button.visible = false
	skip_button.visible = false
	next_button.visible = false
	start_button.grab_focus()

func _parameters() -> String:
	var c: Dictionary = generator.defaults(game_id, difficulty)
	match game_id:
		"fifteen": return "Поле 4×4 · Перемешивание: %d ходов" % c.shuffle_moves
		"pairs": return "%d пар · Показ %.1f с · После ошибки пауза 0,7 с" % [c.pairs, c.preview_ms / 1000.0]
		"math": return "20 заданий · 60 секунд · На пример до %.1f с" % (c.question_limit_ms / 1000.0)
		"chimp": return "От %d до %d чисел · Допустимо ошибок: %d" % [c.start_count, c.target_count, c.mistake_limit]
	return ""

func elapsed() -> int:
	return maxi(0, Time.get_ticks_msec() - _started_at)

func _start() -> void:
	session = Rules.new(game_id, difficulty, generator)
	session.source = source
	_started_at = Time.get_ticks_msec()
	_emitted = false
	start_button.visible = false
	restart_button.visible = true
	result_label.text = ""
	_build_grid()
	_render()

func _build_grid() -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	var count: int = {"fifteen": 16, "pairs": session.config.get("pairs", 0) * 2, "math": 4, "chimp": 40}[game_id]
	grid.columns = {"fifteen": 4, "pairs": 6, "math": 2, "chimp": 8}[game_id]
	for index in range(count):
		var button := Button.new()
		button.name = "Cell%d" % index
		button.custom_minimum_size = {"fifteen": Vector2(75, 58), "pairs": Vector2(60, 40), "math": Vector2(180, 60), "chimp": Vector2(60, 40)}[game_id]
		button.add_theme_font_size_override("font_size", 22)
		if game_id in ["pairs", "chimp"]:
			button.add_theme_font_size_override("font_size", 20)
			for state in ["normal", "hover", "pressed", "disabled"]:
				var style: StyleBox = theme.get_stylebox(state, "Button").duplicate()
				style.content_margin_top = 2
				style.content_margin_bottom = 2
				button.add_theme_stylebox_override(state, style)
		button.pressed.connect(_choose.bind(index))
		grid.add_child(button)

func _process(_delta: float) -> void:
	if session != null and not session.done:
		session.advance(elapsed())
		_render()
		_finish_once()

func _choose(index: int) -> void:
	if session == null or session.done:
		return
	session.act(index, elapsed())
	_render()
	_finish_once()

func _render() -> void:
	if session == null:
		return
	var t: int = session.last_time
	stats.text = "Время: %.1f с  |  " % (t / 1000.0)
	question_label.visible = game_id == "math"
	skip_button.visible = game_id == "math" and not session.done
	next_button.visible = game_id == "chimp" and session.round_pending and not session.done
	match game_id:
		"fifteen": stats.text += "Ходы: %d" % session.moves
		"pairs":
			stats.text += "Пары: %d/%d · Попытки: %d · Ошибки: %d" % [session.pairs_found, session.config.pairs, session.attempts, session.pair_errors]
			if t < session.config.preview_ms:
				stats.text += " · Запоминайте: %.1f с" % ((session.config.preview_ms - t) / 1000.0)
		"math":
			stats.text = "Осталось: %.1f с · Пример %d/20 · Верно: %d · Ошибки: %d · Пропуски: %d" % [maxf(0, (60000 - t) / 1000.0), session.question_index + 1, session.correct, session.incorrect, session.skipped]
			var q: Dictionary = session.initial.questions[session.question_index]
			question_label.text = "%d %s %d = ?  ·  %.1f с" % [q.a, {"add": "+", "sub": "−", "mul": "×", "div": "÷"}[q.op], q.b, maxf(0, (session.deadline - t) / 1000.0)]
		"chimp":
			stats.text += "Чисел: %d · Успешных раундов: %d · Ошибки: %d/%d" % [session.chimp_count, session.chimp_success, session.chimp_errors, session.config.mistake_limit]
			if session.round_pending and not session.done:
				result_label.text = "Раунд пройден. Продолжайте." if session.chimp_next == session.positions.size() else "Ошибка. Следующий раунд — с новой раскладкой."
	for index in range(grid.get_child_count()):
		var button: Button = grid.get_child(index)
		button.modulate = Color.WHITE
		button.disabled = session.done
		match game_id:
			"fifteen":
				button.text = str(session.board[index]) if session.board[index] != 0 else ""
				button.disabled = session.done or session.board[index] == 0
				if session.board[index] == 0:
					button.modulate = Color(0.5, 0.7, 0.8, 0.35)
			"pairs":
				var revealed: bool = t < session.config.preview_ms or session.found.has(index) or session.open_first == index or session.open_second == index
				button.text = String.chr(65 + session.cards[index]) if revealed else "?"
				button.disabled = session.done or t < session.locked_until or session.found.has(index) or session.open_first == index
				if session.found.has(index):
					button.modulate = Color(0.55, 1, 0.8)
			"math": button.text = str(session.initial.questions[session.question_index].options[index])
			"chimp":
				var number: int = session.positions.find(index)
				button.text = str(number + 1) if number >= 0 and (not session.hidden or session.round_pending) else ""
				button.disabled = session.done or session.round_pending or number < session.chimp_next or number < 0
				if number < 0 or number < session.chimp_next:
					button.modulate = Color(1, 1, 1, 0)

func _finish_once() -> void:
	if session == null or not session.done or _emitted:
		return
	_emitted = true
	help_label.visible = false
	question_label.visible = false
	skip_button.visible = false
	next_button.visible = false
	var reasons: Dictionary = {"solved": "Задача решена", "questions_done": "Все примеры пройдены", "time_limit": "Время вышло", "target_reached": "Целевой уровень достигнут", "mistake_limit": "Лимит ошибок", "user_exit": "Выход из игры", "focus_lost": "Окно потеряло фокус", "host_removed": "Модуль закрыт", "recording_limit": "Достигнут предел записи"}
	result_label.text = {"completed": "Завершено", "failed": "Игра окончена", "aborted": "Попытка прервана"}[session.result.status] + " · " + reasons.get(session.result.finish_reason, "") + "\n"
	var parts: PackedStringArray = []
	for key in session.summary():
		parts.append("%s: %s" % [key, session.summary()[key]])
	result_label.text += " · ".join(parts)
	run_finished.emit(session.result.duplicate(true))

func cancel(reason: String = "user_exit") -> void:
	if session != null and not session.done:
		session.abort(reason, elapsed())
		_render()
		_finish_once()

func _restart() -> void:
	cancel()
	help_label.visible = true
	_start()

func _skip() -> void:
	session.skip(elapsed())
	_render()
	_finish_once()

func _next_round() -> void:
	session.next_round(elapsed())
	result_label.text = ""
	_render()

func _back() -> void:
	cancel()
	exit_requested.emit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		cancel("focus_lost")

func _exit_tree() -> void:
	cancel("host_removed")

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
