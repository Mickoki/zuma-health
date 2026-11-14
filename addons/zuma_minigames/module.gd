extends Control
## Public host: configure(), start_game(), cancel_game(), retry_pending().
signal run_finished(payload: Dictionary)
signal delivery_changed(client_run_id: String, state: String, message: String)
signal module_exit_requested

const Generator = preload("res://addons/zuma_minigames/core/generator.gd")
const Outbox = preload("res://addons/zuma_minigames/core/outbox.gd")
const Transport = preload("res://addons/zuma_minigames/core/transport.gd")
const Wire = preload("res://addons/zuma_minigames/core/wire.gd")
const SCENES: Dictionary = {
	"fifteen": preload("res://addons/zuma_minigames/games/fifteen.tscn"),
	"pairs": preload("res://addons/zuma_minigames/games/pairs.tscn"),
	"math": preload("res://addons/zuma_minigames/games/math.tscn"),
	"chimp": preload("res://addons/zuma_minigames/games/chimp.tscn")
}
var generator = Generator.new()
var options: Dictionary = {"source": "observed", "owner_key": "local", "profile_id": "", "base_url": "http://127.0.0.1:8080", "storage_dir": "user://zuma_minigames", "auto_upload": true, "survey": {}}
var run_survey: Dictionary = {}
var view = null
var outbox = null
var transport = null
var unsaved: Array = []
var delivery_busy: bool = false
var _retry_after: bool = false

func _ready() -> void:
	configure({})

func configure(settings: Dictionary) -> Error:
	if delivery_busy or view != null and view.session != null and not view.session.done:
		return ERR_BUSY
	for key in settings:
		if not options.has(key):
			return ERR_INVALID_PARAMETER
	var candidate: Dictionary = options.duplicate(true)
	candidate.merge(settings, true)
	if not candidate.source is String or candidate.source not in ["observed", "synthetic"] or not candidate.owner_key is String or candidate.owner_key.is_empty() or candidate.owner_key.length() > 128 or not candidate.profile_id is String or not candidate.base_url is String or not Wire.valid_url(candidate.base_url) or not candidate.storage_dir is String or candidate.storage_dir.begins_with("res://") or not (candidate.storage_dir.begins_with("user://") or candidate.storage_dir.is_absolute_path()) or not candidate.auto_upload is bool:
		return ERR_INVALID_PARAMETER
	if not candidate.profile_id.is_empty() and not Wire.valid_id(candidate.profile_id):
		return ERR_INVALID_PARAMETER
	if not candidate.survey is Dictionary:
		return ERR_INVALID_PARAMETER
	if not candidate.survey.is_empty():
		if candidate.survey.size() != 4:
			return ERR_INVALID_PARAMETER
		for key in ["sleep_hours", "fatigue", "stress", "mood"]:
			var value: Variant = candidate.survey.get(key)
			if not (value is int or value is float) or not is_finite(float(value)) or value < 0 or value > (24 if key == "sleep_hours" else 10):
				return ERR_INVALID_PARAMETER
	if not unsaved.is_empty() and (candidate.owner_key != options.owner_key or candidate.base_url != options.base_url or candidate.profile_id != options.profile_id):
		return ERR_BUSY
	var queue = Outbox.new(candidate.storage_dir)
	if queue.error == OK and not candidate.profile_id.is_empty():
		var bound: Error = queue.bind_owner(candidate.owner_key, candidate.profile_id, candidate.base_url)
		if bound != OK:
			return bound
	options = candidate.duplicate(true)
	outbox = queue
	if transport == null:
		transport = Transport.new()
		add_child(transport)
	for warning in outbox.warnings:
		delivery_changed.emit("", "storage_warning", warning)
	return outbox.error

func start_game(game: String, difficulty: String = "easy") -> Error:
	if not SCENES.has(game) or generator.defaults(game, difficulty).is_empty():
		return ERR_INVALID_PARAMETER
	if view != null:
		cancel_game()
		remove_child(view)
		view.queue_free()
	run_survey = options.survey.duplicate(true)
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
	if delivery_busy or not is_inside_tree():
		return
	if outbox == null or outbox.error != OK:
		if configure({}) != OK:
			delivery_changed.emit("", "storage_error", "Каталог очереди недоступен; результаты остаются в памяти")
			return
	var retained: Array = []
	for record in unsaved:
		if outbox.enqueue(record.owner_key, record.payload) != OK:
			retained.append(record)
	unsaved = retained
	delivery_busy = true
	_drain.call_deferred()

func _on_finished(payload: Dictionary) -> void:
	payload = payload.duplicate(true)
	if not run_survey.is_empty():
		payload["survey"] = run_survey.duplicate(true)
	var stored: Error = ERR_CANT_CREATE if outbox == null else outbox.enqueue(options.owner_key, payload)
	if stored != OK:
		unsaved.append({"owner_key": options.owner_key, "payload": payload.duplicate(true)})
		delivery_changed.emit(payload.client_run_id, "storage_error", "Не удалось сохранить на диск (код %d); результат остаётся в памяти" % stored)
	else:
		delivery_changed.emit(payload.client_run_id, "pending", "Результат сохранён локально")
	run_finished.emit(payload)
	if options.auto_upload and stored == OK:
		if delivery_busy:
			_retry_after = true
		else:
			retry_pending()

func pending_count() -> int:
	return unsaved.size() + (0 if outbox == null else outbox.pending().size())

func bind_owner(owner: String, profile_id: String) -> Error:
	if delivery_busy or outbox == null:
		return ERR_BUSY
	return outbox.bind_owner(owner, profile_id, options.base_url)

func _drain() -> void:
	var unavailable_servers := {}
	for record in outbox.pending():
		var id: String = record.payload.client_run_id
		var route: Dictionary = outbox.freeze_route(record)
		if route.is_empty():
			delivery_changed.emit(id, "unassigned", "Нет привязанного профиля или не удалось сохранить адрес доставки")
			continue
		if unavailable_servers.has(route.base_url):
			delivery_changed.emit(id, "pending", "Ожидает подключения к серверу")
			continue
		delivery_changed.emit(id, "sending", "Отправка…")
		var response: Dictionary = await transport.request(route.base_url, "/api/v1/profiles/%s/game-runs" % route.profile_id, HTTPClient.METHOD_POST, record.payload)
		if not response.ok or response.status not in [200, 201]:
			delivery_changed.emit(id, "pending", "Не отправлено: " + str(response.get("error", response.status)))
			if response.status == 0 or response.status >= 500:
				unavailable_servers[route.base_url] = true # Do not let one offline server block other routes.
			continue
		var receipt: Dictionary = response.data
		if receipt.get("game_id") != record.payload.game_id or outbox.mark_sent(record, receipt) != OK:
			delivery_changed.emit(id, "pending", "Ответ или сохранение квитанции не подтверждены; повтор безопасен")
			continue
		delivery_changed.emit(id, "sent", "Сохранено на сервере: " + str(receipt.id))
	delivery_busy = false
	if _retry_after:
		_retry_after = false
		retry_pending()
