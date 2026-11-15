extends SceneTree

var failed := false

func check(condition: bool, message: String) -> void:
	if not condition:
		push_error("TEST FAILED: " + message)
		failed = true

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var queue = load("res://scripts/session_queue.gd").new()
	queue.api_url = OS.get_environment("ZUMA_TEST_API")
	queue.queue_dir = OS.get_environment("ZUMA_TEST_QUEUE_DIR")
	root.add_child(queue)
	var profile := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	var survey := {"sleep_hours": 8, "fatigue": 0, "stress": 2, "mood": 7}
	var reaction := {"protocol_version": "reaction-memory-v1", "trials": [{"outcome": "valid", "reaction_ms": 230}, {"outcome": "missed"}]}
	var memory := {"protocol_version": "reaction-memory-v1", "correct": 3, "total": 4}
	var invalid: Dictionary = queue.enqueue(profile, survey, reaction, {"protocol_version": "other", "correct": 3, "total": 4})
	check(not invalid.ok and queue.pending(profile).is_empty(), "wrong protocol rejected")
	var queued: Dictionary = queue.enqueue(profile, survey, reaction, memory)
	check(queued.ok, "complete result persisted")
	var pending: Array = queue.pending(profile)
	check(pending.size() == 1, "pending item available after reload")
	var second_queue = load("res://scripts/session_queue.gd").new()
	second_queue.api_url = queue.api_url
	second_queue.queue_dir = queue.queue_dir
	root.add_child(second_queue)
	pending = second_queue.pending(profile)
	var first: Dictionary = await second_queue.send(pending[0])
	check(not first.ok and second_queue.pending(profile).size() == 1, "failed request remains queued")
	var retry: Dictionary = await second_queue.send(second_queue.pending(profile)[0])
	check(retry.ok and second_queue.pending(profile).is_empty(), "successful retry removes pending item")
	if not failed:
		print("SESSION QUEUE TEST PASSED")
	quit(1 if failed else 0)
