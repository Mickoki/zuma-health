extends Control
## Public host: configure(), start_game(), cancel_game(), retry_pending().
signal run_finished(payload: Dictionary)
signal delivery_changed(client_run_id: String, state: String, message: String)
signal module_exit_requested

const Generator = preload("res://addons/zuma_minigames/core/generator.gd")
const SCENES: Dictionary = {
	"fifteen": preload("res://addons/zuma_minigames/games/fifteen.tscn"),
	"pairs": preload("res://addons/zuma_minigames/games/pairs.tscn"),
	"math": preload("res://addons/zuma_minigames/games/math.tscn"),
	"chimp": preload("res://addons/zuma_minigames/games/chimp.tscn")
}
var generator = Generator.new()
var options: Dictionary = {"source": "observed"}
var view = null

func configure(settings: Dictionary) -> Error:
	if view != null and view.session != null and not view.session.done:
		return ERR_BUSY
	options.merge(settings, true)
	return OK

func start_game(game: String, difficulty: String = "easy") -> Error:
	if not SCENES.has(game) or generator.defaults(game, difficulty).is_empty():
		return ERR_INVALID_PARAMETER
	if view != null:
		cancel_game()
		remove_child(view)
		view.queue_free()
	view = SCENES[game].instantiate()
	view.difficulty = difficulty
	view.generator = generator
	view.source = options.get("source", "observed")
	view.run_finished.connect(_on_finished)
	view.exit_requested.connect(func(): module_exit_requested.emit())
	add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return OK

func cancel_game() -> void:
	if view != null:
		view.cancel()

func retry_pending() -> void:
	pass # Transport/outbox is attached in the next plan task.

func _on_finished(payload: Dictionary) -> void:
	run_finished.emit(payload)
