extends SceneTree

const Module = preload("res://addons/zuma_minigames/module.gd")
const Wire = preload("res://addons/zuma_minigames/core/wire.gd")
const Rules = preload("res://addons/zuma_minigames/core/rules.gd")

func _initialize() -> void:
	call_deferred("run_test")

func run_test() -> void:
	create_timer(45).timeout.connect(func(): push_error("DELIVERY TEST TIMEOUT"); quit(2))
	var args: PackedStringArray = OS.get_cmdline_user_args()
	assert(args.size() == 2, "pass config.json and offline/online")
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var phase: String = args[1]
	var module = Module.new()
	root.add_child(module)
	module.delivery_changed.connect(func(_id, state, _message): print("DELIVERY STATE ", state))
	assert(module.configure({"storage_dir": config.storage_dir, "base_url": config.base_url, "profile_id": config.profile_id, "owner_key": "delivery-test", "auto_upload": false, "source": "synthetic"}) == OK)
	if phase == "offline":
		for name in DirAccess.get_files_at(config.fixtures_dir):
			if name.ends_with(".json"):
				var payload: Dictionary = Wire.normalize(JSON.parse_string(FileAccess.get_file_as_string(config.fixtures_dir.path_join(name))))
				assert(module.outbox.enqueue("delivery-test", payload) == OK)
		assert(module.pending_count() == 12)
		module.retry_pending()
		while module.delivery_busy:
			await process_frame
		assert(module.pending_count() == 12, "offline delivery lost records")
		print("DELIVERY OFFLINE PASS:12 records remain on disk")
	else:
		assert(module.pending_count() == 12, "restart did not restore pending records")
		# Simulate successful server commit with a lost acknowledgement.
		var first: Dictionary = module.outbox.pending()[0]
		var acknowledgement: Dictionary = await module.transport.request(config.base_url, "/api/v1/profiles/%s/game-runs" % config.profile_id, HTTPClient.METHOD_POST, first.payload)
		assert(acknowledgement.ok and acknowledgement.status == 201)
		module.retry_pending()
		while module.delivery_busy:
			await process_frame
		assert(module.pending_count() == 0, "some records not acknowledged")
		var history: Dictionary = await module.transport.request(config.base_url, "/api/v1/profiles/%s/game-runs?limit=100" % config.profile_id)
		assert(history.ok and history.data.total == 12, "retry created duplicates")
		for record in history.data.items:
			var report: Dictionary = await module.transport.request(config.base_url, "/api/v1/game-runs/%s/report" % record.id)
			assert(report.ok and not report.data.metrics.is_empty())
			var explanation: Dictionary = await module.transport.request(config.base_url, "/api/v1/game-runs/%s/explanation" % record.id, HTTPClient.METHOD_POST)
			assert(explanation.ok and explanation.data.status == "unavailable")
		var rejection = Module.new()
		root.add_child(rejection)
		assert(rejection.configure({"storage_dir": config.storage_dir + "-rejected", "base_url": config.base_url, "profile_id": config.profile_id, "owner_key": "rejected", "auto_upload": false}) == OK)
		var conflicting: Dictionary = first.payload.duplicate(true)
		conflicting.source = "observed"
		assert(rejection.outbox.enqueue("rejected", conflicting) == OK)
		var invalid: Dictionary = {"client_run_id": Rules.uuid(), "game_id": "pairs"}
		assert(rejection.outbox.enqueue("rejected", invalid) == OK)
		rejection.retry_pending()
		while rejection.delivery_busy:
			await process_frame
		assert(rejection.pending_count() == 2, "409/422 record was discarded")
		print("DELIVERY ONLINE PASS:12 reports; lost-ack replay no duplicate;409/422 retained")
		rejection.queue_free()
	module.queue_free()
	await process_frame
	quit(0)
