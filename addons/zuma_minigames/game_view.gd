extends Control

signal run_finished(payload: Dictionary)
signal exit_requested
const Rules = preload("res://addons/zuma_minigames/core/rules.gd")
const Generator = preload("res://addons/zuma_minigames/core/generator.gd")
const TITLES: Dictionary = {"fifteen": "Fifteen Puzzle", "pairs": "Find the Pair", "math": "Speed Math", "chimp": "Remember the Numbers"}
const INSTRUCTIONS: Dictionary = {
	"fifteen": "Arrange 1–15 in order by sliding tiles into the empty space.",
	"pairs": "Memorize the cards, then reveal matching pairs.",
	"math": "Choose the correct answer before time runs out.",
	"chimp": "Memorize the numbers and select them in order. They disappear after 1."
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
var interruption_overlay: PanelContainer
var interruption_message: Label
var feedback_label: Label
var back_button: Button
var game_actions: HBoxContainer
var disclaimer_label: Label
var _started_at: int = 0
var _emitted: bool = false

func _ready() -> void:
	theme = preload("res://addons/zuma_minigames/theme.tres")
	var panel := PanelContainer.new()
	var frame: StyleBoxFlat = theme.get_stylebox("panel", "PanelContainer").duplicate()
	for edge in ["left", "right", "top", "bottom"]:
		frame.set("content_margin_" + edge, 0.0)
	panel.add_theme_stylebox_override("panel", frame)
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
	heading.text = TITLES[game_id] + "  /  " + {"easy": "EASY", "normal": "NORMAL", "hard": "HARD"}[difficulty]
	heading.add_theme_font_size_override("font_size", 25)
	var heading_row := HBoxContainer.new()
	column.add_child(heading_row)
	var game_icon := TextureRect.new()
	game_icon.texture = load("res://addons/zuma_minigames/icons/%s.svg" % game_id)
	game_icon.custom_minimum_size = Vector2(30, 30)
	game_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	heading_row.add_child(game_icon)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading_row.add_child(heading)
	var source_label := Label.new()
	source_label.name = "SourceLabel"
	source_label.text = "Synthetic data" if source == "synthetic" else "Local run"
	source_label.add_theme_font_size_override("font_size", 13)
	source_label.add_theme_color_override("font_color", Color("f59e0b") if source == "synthetic" else Color("10b981"))
	heading_row.add_child(source_label)
	help_label = Label.new()
	help_label.text = INSTRUCTIONS[game_id] + " Switching windows ends the attempt."
	help_label.tooltip_text = "Losing window focus interrupts the attempt."
	help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_label.add_theme_font_size_override("font_size", 15)
	column.add_child(help_label)
	stats = Label.new()
	stats.theme_type_variation = &"TelemetryLabel"
	column.add_child(stats)
	question_label = Label.new()
	question_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question_label.add_theme_font_size_override("font_size", 30)
	question_label.theme_type_variation = &"TelemetryLabel"
	question_label.visible = false
	column.add_child(question_label)
	feedback_label = Label.new()
	feedback_label.visible = false
	feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback_label.add_theme_font_size_override("font_size", 14)
	column.add_child(feedback_label)
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
	game_actions = actions
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	column.add_child(actions)
	start_button = _button(actions, "Start", _start)
	start_button.name = "Start"
	restart_button = _button(actions, "Restart", _restart)
	skip_button = _button(actions, "Skip", _skip)
	next_button = _button(actions, "Next round", _next_round)
	back_button = _button(actions, "Back", _back)
	restart_button.tooltip_text = "Restart · R"
	back_button.tooltip_text = "Back · Esc"
	skip_button.tooltip_text = "Skip question"
	var disclaimer := Label.new()
	disclaimer_label = disclaimer
	disclaimer.text = "Results describe task performance and are not a diagnosis."
	disclaimer.add_theme_font_size_override("font_size", 12)
	disclaimer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(disclaimer)
	stats.text = _parameters()
	result_label.text = ""
	restart_button.visible = false
	skip_button.visible = false
	next_button.visible = false
	_build_interruption_overlay()
	start_button.grab_focus()

func _parameters() -> String:
	var c: Dictionary = generator.defaults(game_id, difficulty)
	match game_id:
		"fifteen": return "4×4 board"
		"pairs": return "%d pairs · %.1f s preview" % [c.pairs, c.preview_ms / 1000.0]
		"math": return "20 questions · 60 s · %.1f s each" % (c.question_limit_ms / 1000.0)
		"chimp": return "%d–%d numbers · %d mistakes allowed" % [c.start_count, c.target_count, c.mistake_limit]
	return ""

func elapsed() -> int:
	return maxi(0, Time.get_ticks_msec() - _started_at)

func _start() -> void:
	interruption_overlay.visible = false
	game_actions.visible = true
	disclaimer_label.visible = true
	help_label.visible = false
	stats.visible = true
	result_label.visible = true
	feedback_label.visible = false
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
		button.add_theme_font_override("font", theme.get_font("font", "TelemetryLabel"))
		if game_id == "math":
			button.tooltip_text = "Answer · %d" % (index + 1)
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
		var before_question: int = session.question_index
		session.advance(elapsed())
		if game_id == "math" and session.question_index != before_question:
			_feedback("Question time expired · next question", Color("ef4444"))
		_render()
		_finish_once()

func _choose(index: int) -> void:
	if session == null or session.done:
		return
	var previous_correct: int = session.correct
	var previous_incorrect: int = session.incorrect
	var previous_skipped: int = session.skipped
	session.act(index, elapsed())
	if game_id == "math":
		if session.correct > previous_correct:
			_feedback("Correct · next question", Color("10b981"))
		elif session.incorrect > previous_incorrect:
			_feedback("Incorrect · next question", Color("ef4444"))
		elif session.skipped > previous_skipped:
			_feedback("Question time expired", Color("ef4444"))
	_render()
	_finish_once()

func _render() -> void:
	if session == null:
		return
	var t: int = session.last_time
	stats.text = "Time: %.1f s  |  " % (t / 1000.0)
	question_label.visible = game_id == "math"
	skip_button.visible = game_id == "math" and not session.done
	next_button.visible = game_id == "chimp" and session.round_pending and not session.done
	match game_id:
		"fifteen": stats.text += "Moves: %d" % session.moves
		"pairs":
			stats.text += "Pairs: %d/%d · Attempts: %d · Errors: %d" % [session.pairs_found, session.config.pairs, session.attempts, session.pair_errors]
			if t < session.config.preview_ms:
				stats.text += " · Memorize: %.1f s" % ((session.config.preview_ms - t) / 1000.0)
		"math":
			stats.text = "Remaining: %.1f s · Question %d/20 · Correct: %d · Errors: %d · Skipped: %d" % [maxf(0, (60000 - t) / 1000.0), session.question_index + 1, session.correct, session.incorrect, session.skipped]
			var q: Dictionary = session.initial.questions[session.question_index]
			question_label.text = "%d %s %d = ?  ·  %.1f s" % [q.a, {"add": "+", "sub": "−", "mul": "×", "div": "÷"}[q.op], q.b, maxf(0, (session.deadline - t) / 1000.0)]
		"chimp":
			stats.text += "Numbers: %d · Successful rounds: %d · Errors: %d/%d" % [session.chimp_count, session.chimp_success, session.chimp_errors, session.config.mistake_limit]
			if session.round_pending and not session.done:
				result_label.text = "Round completed. Continue." if session.chimp_next == session.positions.size() else "Incorrect. The next round uses a new layout."
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
					button.modulate = Color("10b981")
				elif session.open_second >= 0 and (index == session.open_first or index == session.open_second):
					button.modulate = Color("ef4444")
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
	stats.visible = false
	help_label.visible = false
	question_label.visible = false
	skip_button.visible = false
	next_button.visible = false
	feedback_label.visible = false
	var reasons: Dictionary = {"solved": "Puzzle solved", "questions_done": "All questions completed", "time_limit": "Time is up", "target_reached": "Target level reached", "mistake_limit": "Mistake limit reached", "user_exit": "Left the game", "focus_lost": "Window lost focus", "host_removed": "Module closed", "recording_limit": "Recording limit reached"}
	result_label.text = reasons.get(session.result.finish_reason, "Completed") + "\n"
	var parts: PackedStringArray = []
	for key in session.summary():
		if key == "Duration, ms":
			parts.append("Time: %.1f s" % (session.result.duration_ms / 1000.0))
		else:
			parts.append("%s: %s" % [key, session.summary()[key]])
	result_label.text += " · ".join(parts)
	run_finished.emit(session.result.duplicate(true))
	if session.result.finish_reason == "focus_lost":
		interruption_message.text = "Attempt interrupted — Window lost focus\nDuration: %d ms" % session.result.duration_ms
		interruption_overlay.visible = true
		game_actions.visible = false
		disclaimer_label.visible = false
		result_label.visible = false
		interruption_overlay.find_child("ResumeRestart", true, false).grab_focus()

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
	_feedback("Question skipped · next question", Color("f59e0b"))
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
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		cancel("focus_lost")

func _feedback(text: String, color: Color) -> void:
	feedback_label.text = text
	feedback_label.add_theme_color_override("font_color", color)
	feedback_label.visible = not session.done

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo:
		return
	var code: int = event.keycode if event.keycode != 0 else event.physical_keycode
	if code == KEY_ESCAPE:
		_back()
	elif code == KEY_R and session != null:
		_restart()
	elif code >= KEY_1 and code <= KEY_4 and game_id == "math" and session != null and not session.done:
		_choose(code - KEY_1)
	else:
		return
	get_viewport().set_input_as_handled()

func _build_interruption_overlay() -> void:
	interruption_overlay = PanelContainer.new()
	interruption_overlay.name = "InterruptionOverlay"
	interruption_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scrim := StyleBoxFlat.new()
	scrim.bg_color = Color(0.016, 0.027, 0.059, 0.96)
	interruption_overlay.add_theme_stylebox_override("panel", scrim)
	add_child(interruption_overlay)
	var center := CenterContainer.new()
	interruption_overlay.add_child(center)
	var card := PanelContainer.new()
	center.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	card.add_child(column)
	var icon := TextureRect.new()
	icon.texture = preload("res://addons/zuma_minigames/icons/warning.svg")
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size.y = 44
	column.add_child(icon)
	interruption_message = Label.new()
	interruption_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interruption_message.add_theme_font_size_override("font_size", 20)
	interruption_message.add_theme_color_override("font_color", Color("ef4444"))
	column.add_child(interruption_message)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 16)
	column.add_child(actions)
	var restart := _button(actions, "Restart", _restart)
	restart.name = "ResumeRestart"
	_button(actions, "Back", _back)
	var note := Label.new()
	note.text = "Results describe task performance and are not a diagnosis."
	note.add_theme_font_size_override("font_size", 12)
	column.add_child(note)
	interruption_overlay.visible = false

func _exit_tree() -> void:
	cancel("host_removed")

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
