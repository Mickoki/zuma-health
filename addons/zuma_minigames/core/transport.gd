extends Node

const Wire = preload("res://addons/zuma_minigames/core/wire.gd")

func request(base_url: String, path: String, method: HTTPClient.Method = HTTPClient.METHOD_GET, payload: Variant = null, timeout: float = 15.0) -> Dictionary:
	if not Wire.valid_url(base_url) or not is_inside_tree():
		return {"ok": false, "status": 0, "error": "Invalid local address or module is not in the SceneTree"}
	var http := HTTPRequest.new()
	http.timeout = timeout
	http.body_size_limit = 2 * 1024 * 1024
	# Redirects could send private results outside the local service.
	http.max_redirects = 0
	add_child(http)
	var headers := PackedStringArray()
	var body: String = ""
	if payload != null:
		headers.append("Content-Type: application/json")
		body = Wire.stringify(payload)
	var started: Error = http.request(base_url.trim_suffix("/") + path, headers, method, body)
	if started != OK:
		http.queue_free()
		return {"ok": false, "status": 0, "error": "Could not start the request: " + str(started)}
	var response: Array = await http.request_completed
	http.queue_free()
	var status: int = response[1]
	if response[0] != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "status": status, "error": "Server unavailable or request timed out"}
	var data: Variant = JSON.parse_string(response[3].get_string_from_utf8())
	if not data is Dictionary:
		return {"ok": false, "status": status, "error": "The server response is not a JSON object"}
	return {"ok": status >= 200 and status < 300, "status": status, "data": data, "error": "" if status >= 200 and status < 300 else str(data.get("error", "API error"))}
