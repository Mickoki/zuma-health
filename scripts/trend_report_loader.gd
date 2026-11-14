extends Node
## Fetch calculated session reports with bounded concurrency and cancellation.

signal progress(completed: int, total: int)
signal finished(reports: Dictionary, failures: Array)

const MAX_WORKERS := 4
var api_url := ""
var work: Array = []
var next_index := 0
var active_workers := 0
var completed_count := 0
var running := false
var reports: Dictionary = {}
var failures: Array = []

func start(sessions: Array) -> void:
	work = sessions.duplicate(true)
	next_index = 0
	completed_count = 0
	reports.clear()
	failures.clear()
	running = true
	active_workers = mini(MAX_WORKERS, work.size())
	if active_workers == 0:
		finished.emit(reports, failures)
		return
	for i in range(active_workers):
		worker()

func cancel() -> void:
	running = false
	for child in get_children():
		if child is HTTPRequest:
			child.cancel_request()
			child.queue_free()

func worker() -> void:
	while running and next_index < work.size():
		var session: Dictionary = work[next_index]
		next_index += 1
		var http := HTTPRequest.new()
		http.timeout = 5.0
		http.body_size_limit = 1048576
		add_child(http)
		var error := http.request(api_url + "/api/v1/sessions/%s/report" % str(session.id))
		var result := -1
		var status := 0
		var body := PackedByteArray()
		if error == OK:
			var response: Array = await http.request_completed
			result = response[0]
			status = response[1]
			body = response[3]
		if is_instance_valid(http):
			http.queue_free()
		if not running:
			return
		var parser := JSON.new()
		var data: Variant = null
		if result == HTTPRequest.RESULT_SUCCESS and status == 200 and parser.parse(body.get_string_from_utf8()) == OK:
			data = parser.data
		if data is Dictionary and data.get("session_id") == session.id and data.get("source") == session.source and data.get("protocol_version") == session.protocol_version:
			reports[session.id] = data
		else:
			failures.append(session.id)
		completed_count += 1
		progress.emit(completed_count, work.size())
	active_workers -= 1
	if running and active_workers == 0:
		running = false
		finished.emit(reports, failures)
