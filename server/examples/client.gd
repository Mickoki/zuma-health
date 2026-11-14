class_name ZumaAPI
extends Node
## Godot 4 desktop example. Call await demo() explicitly. Synthetic data only.

@export var base_url: String = "http://127.0.0.1:8080"

func new_session_uuid() -> String:
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	var text: String = bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [text.substr(0, 8), text.substr(8, 4), text.substr(12, 4), text.substr(16, 4), text.substr(20, 12)]

func api_request(method: HTTPClient.Method, path: String, payload: Variant = null, timeout_seconds: float = 15.0) -> Dictionary:
	# A distinct node per call keeps long model requests separate.
	var http := HTTPRequest.new()
	http.timeout = timeout_seconds
	add_child(http)
	var headers := PackedStringArray()
	var body: String = ""
	if payload != null:
		headers.append("Content-Type: application/json")
		body = JSON.stringify(payload)
	var start_error: Error = http.request(base_url + path, headers, method, body)
	if start_error != OK:
		http.queue_free()
		return {"ok": false, "status": 0, "error": "Could not start request", "detail": start_error}
	var response: Array = await http.request_completed
	http.queue_free()
	var result: int = response[0]
	var status: int = response[1]
	var response_bytes: PackedByteArray = response[3]
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "status": status, "error": "Transport error or timeout", "detail": result}
	var data: Variant = JSON.parse_string(response_bytes.get_string_from_utf8())
	if not data is Dictionary:
		return {"ok": false, "status": status, "error": "Expected JSON object"}
	return {"ok": status >= 200 and status < 300, "status": status, "data": data}

func save_session(profile_id: String, payload: Dictionary) -> Dictionary:
	# Persist payload/UUID locally until success; retry unchanged after transport errors.
	return await api_request(HTTPClient.METHOD_POST, "/api/v1/profiles/%s/sessions" % profile_id, payload)

func get_history(profile_id: String, limit: int = 20, offset: int = 0) -> Dictionary:
	return await api_request(HTTPClient.METHOD_GET, "/api/v1/profiles/%s/sessions?limit=%d&offset=%d" % [profile_id, limit, offset])

func get_report(session_id: String) -> Dictionary:
	return await api_request(HTTPClient.METHOD_GET, "/api/v1/sessions/%s/report" % session_id)

func explain(session_id: String) -> Dictionary:
	# 140 s exceeds server's default 120 s; adjust when changing server configuration.
	return await api_request(HTTPClient.METHOD_POST, "/api/v1/sessions/%s/explanation" % session_id, null, 140.0)

func demo() -> Dictionary:
	var profile: Dictionary = await api_request(HTTPClient.METHOD_POST, "/api/v1/profiles", {"display_name": "Demo crew member"})
	if not profile.ok:
		return profile
	var payload: Dictionary = {
		"client_session_id": new_session_uuid(),
		"performed_at": Time.get_datetime_string_from_system(true) + "Z",
		"protocol_version": "reaction-memory-v1", "source": "synthetic",
		"survey": {"sleep_hours": 8, "fatigue": 0, "stress": 2, "mood": 7},
		"reaction": {"trials": [{"outcome": "valid", "reaction_ms": 200}, {"outcome": "valid", "reaction_ms": 300}, {"outcome": "missed"}]},
		"memory": {"correct": 3, "total": 4}
	}
	var saved: Dictionary = await save_session(profile.data.id, payload)
	if not saved.ok:
		return saved
	var history: Dictionary = await get_history(profile.data.id)
	if not history.ok:
		return history
	var report: Dictionary = await get_report(saved.data.id)
	if not report.ok:
		return report
	var explanation: Dictionary = await explain(saved.data.id)
	# Also inspect explanation.data.status: unavailable/invalid are HTTP 200.
	return {"ok": true, "session_id": saved.data.id, "history": history, "report": report, "explanation": explanation}
