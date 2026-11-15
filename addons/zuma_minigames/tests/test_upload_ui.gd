extends SceneTree
const Module = preload("res://addons/zuma_minigames/module.gd")

func _initialize() -> void:
	call_deferred("run_test")

func run_test() -> void:
	create_timer(180).timeout.connect(func(): push_error("UI UPLOAD TEST TIMEOUT"); quit(2))
	var args: PackedStringArray = OS.get_cmdline_user_args()
	assert(args.size() == 2, "pass screenshots directory and local API base URL")
	var folder: String = args[0]
	var base: String = args[1]
	var module = Module.new()
	root.add_child(module)
	var profile: Dictionary = await module.transport.request(base, "/api/v1/profiles", HTTPClient.METHOD_POST, {"display_name": "Synthetic <UI> QA"})
	assert(profile.ok)
	var storage: String = FileAccess.get_file_as_string(folder.path_join("outbox-path.txt"))
	assert(module.configure({"storage_dir": storage, "owner_key": "qa-ui", "profile_id": profile.data.id, "base_url": base, "auto_upload": false, "source": "synthetic"}) == OK)
	assert(module.pending_count() == 4)
	module.retry_pending()
	while module.delivery_busy:
		await process_frame
	assert(module.pending_count() == 0)
	var history: Dictionary = await module.transport.request(base, "/api/v1/profiles/%s/game-runs?limit=100" % profile.data.id)
	assert(history.ok and history.data.total == 4)
	var model_run: String = ""
	var evidence: Dictionary = {"profile_id": profile.data.id, "runs": []}
	for record in history.data.items:
		var report: Dictionary = await module.transport.request(base, "/api/v1/game-runs/%s/report" % record.id)
		assert(report.ok and report.data.status == "completed" and report.data.source == "synthetic")
		var html := HTTPRequest.new()
		root.add_child(html)
		assert(html.request(base + "/api/v1/game-runs/%s/report.html" % record.id) == OK)
		var response: Array = await html.request_completed
		html.queue_free()
		assert(response[0] == HTTPRequest.RESULT_SUCCESS and response[1] == 200)
		assert(response[3].get_string_from_utf8().contains("&lt;UI&gt;"))
		evidence.runs.append({"id": record.id, "game_id": record.game_id, "metrics": report.data.metrics})
		if record.game_id == "math":
			model_run = record.id
	assert(not model_run.is_empty())
	var explained: Dictionary = await module.transport.request(base, "/api/v1/game-runs/%s/explanation" % model_run, HTTPClient.METHOD_POST, null, 140.0)
	assert(explained.ok and explained.data.status == "ready", "real model not ready: " + str(explained))
	var cached: Dictionary = await module.transport.request(base, "/api/v1/game-runs/%s/report" % model_run)
	assert(cached.ok and cached.data.explanation != null and cached.data.explanation.status == "ready")
	evidence["model"] = explained.data
	var file := FileAccess.open(folder.path_join("server-evidence.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence, "  "))
	file.close()
	print("UI END-TO-END PASS: four rendered games uploaded; JSON/HTML reports; real qwen3:8b ready; cached explanation")
	module.queue_free()
	await process_frame
	quit(0)
