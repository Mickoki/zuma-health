extends Node
## Boundary for the team's games. See docs/game-integration.md.
## Complete sessions are persisted before the first network attempt.

const PROTOCOL := "reaction-memory-v1"
var api_url := "http://127.0.0.1:8080"
var queue_dir := "user://pending_sessions"
var in_flight: Dictionary = {}

func is_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))

func validate(profile_id: String, survey: Dictionary, reaction: Dictionary, memory: Dictionary) -> String:
	var id_pattern := RegEx.new()
	id_pattern.compile("^[0-9a-f]{32}$")
	if id_pattern.search(profile_id) == null:
		return "invalid_profile"
	if reaction.get("protocol_version") != PROTOCOL or memory.get("protocol_version") != PROTOCOL:
		return "incompatible_protocol"
	for key in ["sleep_hours", "fatigue", "stress", "mood"]:
		var value: Variant = survey.get(key)
		var maximum := 24.0 if key == "sleep_hours" else 10.0
		if not is_number(value) or float(value) < 0.0 or float(value) > maximum:
			return "invalid_survey"
	var trials: Variant = reaction.get("trials")
	if not trials is Array or trials.size() < 1 or trials.size() > 200:
		return "invalid_reaction"
	for trial in trials:
		if not trial is Dictionary:
			return "invalid_reaction"
		var outcome: Variant = trial.get("outcome")
		if outcome == "valid":
			if trial.size() != 2 or not is_number(trial.get("reaction_ms")) or float(trial.reaction_ms) < 1.0 or float(trial.reaction_ms) > 10000.0:
				return "invalid_reaction"
		elif outcome == "premature" or outcome == "missed":
			if trial.size() != 1:
				return "invalid_reaction"
		else:
			return "invalid_reaction"
	var correct: Variant = memory.get("correct")
	var total: Variant = memory.get("total")
	if not is_number(correct) or not is_number(total):
		return "invalid_memory"
	if float(correct) != floor(float(correct)) or float(total) != floor(float(total)) or int(total) < 1 or int(total) > 1000 or int(correct) < 0 or int(correct) > int(total):
		return "invalid_memory"
	return ""

func new_uuid() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]

func enqueue(profile_id: String, survey: Dictionary, reaction: Dictionary, memory: Dictionary) -> Dictionary:
	var error := validate(profile_id, survey, reaction, memory)
	if not error.is_empty():
		return {"ok": false, "error": error}
	var uuid := new_uuid()
	var record := {"profile_id": profile_id, "payload": {
		"client_session_id": uuid,
		"performed_at": Time.get_datetime_string_from_system(true) + "Z",
		"protocol_version": PROTOCOL, "source": "observed",
		"survey": {"sleep_hours": survey.sleep_hours, "fatigue": survey.fatigue, "stress": survey.stress, "mood": survey.mood},
		"reaction": {"trials": reaction.trials.duplicate(true)},
		"memory": {"correct": int(memory.correct), "total": int(memory.total)}
	}}
	var folder := ProjectSettings.globalize_path(queue_dir)
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		return {"ok": false, "error": "storage_unavailable"}
	var target := folder.path_join(uuid + ".json")
	var temp := target + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "storage_unavailable"}
	file.store_string(JSON.stringify(record))
	var write_error := file.get_error()
	file.flush()
	if file.get_error() != OK:
		write_error = file.get_error()
	file.close()
	if write_error != OK or DirAccess.rename_absolute(temp, target) != OK:
		DirAccess.remove_absolute(temp)
		return {"ok": false, "error": "storage_unavailable"}
	return {"ok": true, "id": uuid}

func parse_object(text: String) -> Variant:
	var parser := JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		return null
	return parser.data

func valid_record(filename: String, record: Variant) -> bool:
	if not record is Dictionary or not record.get("profile_id") is String or not record.get("payload") is Dictionary:
		return false
	var payload: Dictionary = record.payload
	var uuid: String = str(payload.get("client_session_id", ""))
	var pattern := RegEx.new()
	pattern.compile("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
	if pattern.search(uuid) == null or filename != uuid + ".json":
		return false
	if not payload.get("performed_at") is String or str(payload.performed_at).is_empty() or payload.get("source") != "observed":
		return false
	if not payload.get("survey") is Dictionary or not payload.get("reaction") is Dictionary or not payload.get("memory") is Dictionary:
		return false
	var reaction: Dictionary = payload.reaction.duplicate(true)
	var memory: Dictionary = payload.memory.duplicate(true)
	reaction["protocol_version"] = payload.get("protocol_version", "")
	memory["protocol_version"] = payload.get("protocol_version", "")
	return validate(record.profile_id, payload.survey, reaction, memory).is_empty()

func inspect_queue(profile_id: String) -> Dictionary:
	var result := {"records": [], "problem_count": 0, "directory_error": false}
	var absolute_dir := ProjectSettings.globalize_path(queue_dir)
	if FileAccess.file_exists(absolute_dir) or DirAccess.make_dir_recursive_absolute(absolute_dir) != OK:
		result.directory_error = true
		return result
	var directory := DirAccess.open(queue_dir)
	if directory == null:
		result.directory_error = true
		return result
	if directory.list_dir_begin() != OK:
		result.directory_error = true
		return result
	var filename := directory.get_next()
	while not filename.is_empty():
		if not directory.current_is_dir():
			if filename.ends_with(".json.tmp"):
				result.problem_count += 1
			elif filename.ends_with(".json"):
				var file := FileAccess.open(queue_dir.path_join(filename), FileAccess.READ)
				var record: Variant = null
				if file != null:
					record = parse_object(file.get_as_text())
					file.close()
				if not valid_record(filename, record):
					result.problem_count += 1
				elif record.profile_id == profile_id:
					result.records.append(record)
		filename = directory.get_next()
	directory.list_dir_end()
	return result

func pending(profile_id: String) -> Array:
	return inspect_queue(profile_id).records

func send(record: Dictionary) -> Dictionary:
	var profile_id: String = record.get("profile_id", "")
	var payload: Variant = record.get("payload")
	if not payload is Dictionary:
		return {"ok": false, "error": "invalid_record"}
	var uuid: String = str(payload.get("client_session_id", ""))
	var pattern := RegEx.new()
	pattern.compile("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
	if pattern.search(uuid) == null or in_flight.has(uuid):
		return {"ok": false, "error": "invalid_or_busy"}
	var path := ProjectSettings.globalize_path(queue_dir.path_join(uuid + ".json"))
	var saved := FileAccess.open(path, FileAccess.READ)
	if saved == null:
		return {"ok": false, "error": "missing_record"}
	var stored: Variant = parse_object(saved.get_as_text())
	saved.close()
	if not stored is Dictionary or stored != record:
		return {"ok": false, "error": "changed_record"}
	if not payload.get("reaction") is Dictionary or not payload.get("memory") is Dictionary or not payload.get("survey") is Dictionary:
		return {"ok": false, "error": "invalid_record"}
	var reaction: Dictionary = payload.get("reaction", {}).duplicate(true)
	var memory: Dictionary = payload.get("memory", {}).duplicate(true)
	reaction["protocol_version"] = payload.get("protocol_version", "")
	memory["protocol_version"] = payload.get("protocol_version", "")
	if not validate(profile_id, payload.get("survey", {}), reaction, memory).is_empty() or payload.get("source") != "observed":
		return {"ok": false, "error": "invalid_record"}
	in_flight[uuid] = true
	var http := HTTPRequest.new()
	http.timeout = 15
	add_child(http)
	var start := http.request(api_url + "/api/v1/profiles/%s/sessions" % profile_id, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, JSON.stringify(payload))
	if start != OK:
		http.queue_free()
		in_flight.erase(uuid)
		return {"ok": false, "error": "transport"}
	var response: Array = await http.request_completed
	http.queue_free()
	in_flight.erase(uuid)
	if response[0] != HTTPRequest.RESULT_SUCCESS or (response[1] != 200 and response[1] != 201):
		return {"ok": false, "error": "request_failed", "status": response[1]}
	var data: Variant = parse_object(response[3].get_string_from_utf8())
	if not data is Dictionary or data.get("client_session_id") != uuid or data.get("profile_id") != profile_id or not data.has("id"):
		return {"ok": false, "error": "unexpected_response"}
	if DirAccess.remove_absolute(path) != OK:
		return {"ok": false, "error": "saved_but_local_removal_failed", "session_id": data.id}
	return {"ok": true, "session_id": data.id}
