extends SceneTree

const Outbox = preload("res://addons/zuma_minigames/core/outbox.gd")
const Rules = preload("res://addons/zuma_minigames/core/rules.gd")

func _initialize() -> void:
	call_deferred("run_tests")

func run_tests() -> void:
	create_timer(15).timeout.connect(func(): push_error("OUTBOX TEST TIMEOUT"); quit(2))
	var path: String = "user://outbox_tests/" + Rules.uuid()
	var queue = Outbox.new(path)
	assert(queue.error == OK)
	var payload: Dictionary = {"client_run_id": Rules.uuid(), "game_id": "pairs", "duration_ms": 0}
	assert(queue.enqueue("pilot", payload) == OK)
	assert(queue.enqueue("pilot", payload) == OK and queue.pending().size() == 1)
	var changed: Dictionary = payload.duplicate(true)
	changed.game_id = "math"
	assert(queue.enqueue("pilot", changed) == ERR_ALREADY_EXISTS)
	assert(queue.freeze_route(queue.pending()[0]).is_empty())
	assert(queue.bind_owner("pilot", "a".repeat(32), "http://127.0.0.1:8080") == OK)
	var route: Dictionary = queue.freeze_route(queue.pending()[0])
	assert(route.profile_id == "a".repeat(32))
	assert(queue.bind_owner("pilot", "b".repeat(32), "http://127.0.0.1:8080") == ERR_ALREADY_EXISTS)
	var restored = Outbox.new(path)
	assert(restored.pending().size() == 1)
	assert(restored.freeze_route(restored.pending()[0]).profile_id == "a".repeat(32))
	assert(restored.mark_sent(restored.pending()[0], {"client_run_id": payload.client_run_id, "id": "c".repeat(32), "profile_id": "a".repeat(32)}) == OK)
	assert(Outbox.new(path).pending().is_empty())
	var second: Dictionary = {"client_run_id": Rules.uuid(), "game_id": "math"}
	var record: Dictionary = {"owner_key": "pilot", "payload": second}
	var file := FileAccess.open(path.path_join("pending").path_join(second.client_run_id + ".json.tmp"), FileAccess.WRITE)
	file.store_string(JSON.stringify(record))
	file.close()
	assert(Outbox.new(path).pending().size() == 1, "complete temp file was not recovered")
	file = FileAccess.open(path.path_join("pending/broken.json"), FileAccess.WRITE)
	file.store_string("not json")
	file.close()
	var recovered = Outbox.new(path)
	assert(not recovered.warnings.is_empty(), "corruption was hidden")
	assert(DirAccess.get_files_at(path.path_join("corrupt")).size() == 1)
	var blocked: String = path.path_join("regular_file")
	file = FileAccess.open(blocked, FileAccess.WRITE)
	file.store_string("cannot be a directory")
	file.close()
	assert(Outbox.new(blocked).error != OK, "disk error treated as success")
	print("MINIGAMES_OUTBOX PASS")
	quit(0)
