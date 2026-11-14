extends SceneTree
const Outbox = preload("res://addons/zuma_minigames/core/outbox.gd")
const Rules = preload("res://addons/zuma_minigames/core/rules.gd")

func _initialize() -> void:
	call_deferred("run_test")

func run_test() -> void:
	create_timer(5).timeout.connect(func(): quit(2))
	for bad in [null, 7, [], {"profile_id": "a".repeat(32)}, {"base_url": "https://example.com", "profile_id": "a".repeat(32)}]:
		var path: String = "user://recovery_tests/" + Rules.uuid()
		var queue = Outbox.new(path)
		var file := FileAccess.open(path.path_join("bindings.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify({"pilot": bad}))
		file.close()
		queue = Outbox.new(path)
		assert(not queue.bindings.has("pilot"), "malformed route accepted")
		assert(not queue.warnings.is_empty(), "corrupt bindings warning missing")
		var payload: Dictionary = {"client_run_id": Rules.uuid(), "game_id": "pairs"}
		assert(queue.enqueue("pilot", payload) == OK)
		assert(queue.freeze_route(queue.pending()[0]).is_empty())
		assert(queue.bind_owner("pilot", "a".repeat(32), "http://127.0.0.1:8080") == OK)
		var destination: String = path.path_join("sent").path_join(payload.client_run_id + ".json")
		file = FileAccess.open(destination, FileAccess.WRITE)
		file.store_string(JSON.stringify({"record": queue.pending()[0], "receipt": null}))
		file.close()
		assert(queue.mark_sent(queue.pending()[0], {"client_run_id": payload.client_run_id, "id": "c".repeat(32), "profile_id": "a".repeat(32)}) == OK)
		assert(queue.pending().is_empty())
	print("MINIGAMES_RECOVERY PASS malformed bindings/receipts handled without data loss")
	quit(0)
