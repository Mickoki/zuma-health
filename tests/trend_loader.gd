extends SceneTree

var api := ""
var failed := false

func check(condition: bool, message: String) -> void:
	if not condition:
		push_error("TEST FAILED: " + message)
		failed = true

func get_json(path: String) -> Dictionary:
	var http := HTTPRequest.new()
	root.add_child(http)
	var error := http.request(api + path)
	if error != OK:
		http.queue_free()
		return {}
	var response: Array = await http.request_completed
	http.queue_free()
	var parsed: Variant = JSON.parse_string(response[3].get_string_from_utf8())
	return parsed if parsed is Dictionary else {}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	api = OS.get_environment("ZUMA_TEST_API")
	await get_json("/test/slow_trend_reports")
	var sessions: Array = []
	for character in ["1", "4", "5", "6", "7", "8", "9", "a"]:
		sessions.append({"id": str(character).repeat(32), "source": "observed", "protocol_version": "reaction-memory-v1"})
	var loader = load("res://scripts/trend_report_loader.gd").new()
	loader.api_url = api
	root.add_child(loader)
	loader.start(sessions)
	var outcome: Array = await loader.finished
	check(outcome[0].size() == 8 and outcome[1].is_empty(), "all report results received")
	var stats: Dictionary = await get_json("/test/trend_report_stats")
	check(int(stats.peak) == 4, "requests are bounded to four concurrent workers")
	loader.queue_free()
	var mismatched = load("res://scripts/trend_report_loader.gd").new()
	mismatched.api_url = api
	root.add_child(mismatched)
	var wrong_source := [{"id": "2".repeat(32), "source": "observed", "protocol_version": "reaction-memory-v1"}]
	mismatched.start(wrong_source)
	var rejected: Array = await mismatched.finished
	check(rejected[0].is_empty() and rejected[1].size() == 1, "report with mismatched source is rejected")
	mismatched.queue_free()
	var cancelled = {"finished": false}
	var second = load("res://scripts/trend_report_loader.gd").new()
	second.api_url = api
	root.add_child(second)
	second.finished.connect(func(_reports: Dictionary, _failures: Array) -> void: cancelled.finished = true)
	second.start(sessions)
	await create_timer(0.08).timeout
	second.cancel()
	await process_frame
	check(second.get_child_count() == 0, "cancel releases outstanding requests")
	await create_timer(0.6).timeout
	check(not cancelled.finished, "cancel does not publish stale results")
	second.queue_free()
	if not failed:
		print("TREND LOADER TEST PASSED")
	quit(1 if failed else 0)
