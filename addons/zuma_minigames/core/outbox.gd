extends RefCounted
## Immutable payload files; routes/receipts are persisted separately before use.
const Wire = preload("res://addons/zuma_minigames/core/wire.gd")
var root_dir: String
var error: Error = OK
var warnings: Array = []
var bindings: Dictionary = {}

func _init(storage_dir: String = "user://zuma_minigames") -> void:
	root_dir = ProjectSettings.globalize_path(storage_dir)
	if FileAccess.file_exists(root_dir):
		error = ERR_CANT_CREATE
		return
	for sub in ["pending", "sent", "routes", "corrupt"]:
		error = DirAccess.make_dir_recursive_absolute(root_dir.path_join(sub))
		if error != OK:
			return
	_recover()
	bindings = read_dict(root_dir.path_join("bindings.json"))
	var clean: Dictionary = {}
	for owner in bindings:
		if owner is String and not owner.is_empty() and owner.length() <= 128 and _valid_route(bindings[owner]):
			clean[owner] = bindings[owner]
	if clean.size() != bindings.size():
		_quarantine(root_dir.path_join("bindings.json"))
		bindings = clean
		if not clean.is_empty():
			error = _write(root_dir.path_join("bindings.json"), clean)
	_recover_sent()
	pending() # Detect/quarantine damaged records at startup, before reporting readiness.
	if warnings.is_empty() and not DirAccess.get_files_at(root_dir.path_join("corrupt")).is_empty():
		warnings.append("The corrupt folder contains records to recover; they have not been deleted")

func read_dict(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	if file.get_length() > 2 * 1024 * 1024:
		file.close()
		return {}
	var parser := JSON.new()
	var status: Error = parser.parse(file.get_as_text())
	file.close()
	if status != OK or not parser.data is Dictionary:
		return {}
	return Wire.normalize(parser.data)

func _write(path: String, data: Dictionary, replace: bool = false) -> Error:
	if error != OK:
		return error
	if FileAccess.file_exists(path) and not replace:
		return OK if Wire.stringify(read_dict(path)) == Wire.stringify(data) else ERR_ALREADY_EXISTS
	var temporary: String = path + ".tmp"
	if FileAccess.file_exists(temporary):
		_quarantine(temporary)
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(Wire.stringify(data))
	file.flush()
	var result: Error = file.get_error()
	file.close()
	if result != OK:
		return result
	return DirAccess.rename_absolute(temporary, path)

func _quarantine(path: String) -> void:
	var destination: String = root_dir.path_join("corrupt").path_join(path.get_file() + ".%d.%d.bad" % [Time.get_ticks_usec(), warnings.size()])
	var result: Error = DirAccess.rename_absolute(path, destination)
	warnings.append("Damaged/incomplete record preserved: %s (code %d)" % [path, result])

func _valid_record(record: Dictionary, id: String) -> bool:
	return Wire.valid_uuid(id) and record.get("owner_key", "") is String and not str(record.get("owner_key", "")).is_empty() and record.get("payload") is Dictionary and record.payload.get("client_run_id") == id and record.payload.get("game_id") in ["fifteen", "pairs", "math", "chimp"]

func _valid_route(value: Variant) -> bool:
	return value is Dictionary and value.get("base_url") is String and Wire.valid_url(value.base_url) and value.get("profile_id") is String and Wire.valid_id(value.profile_id)

func _valid_archive(value: Dictionary, id: String) -> bool:
	return value.get("record") is Dictionary and _valid_record(value.record, id) and _valid_route(value.get("route")) and value.get("receipt") is Dictionary and value.receipt.get("client_run_id") == id and value.receipt.get("id") is String and Wire.valid_id(value.receipt.id) and value.receipt.get("profile_id") == value.route.profile_id

func _recover_sent() -> void:
	for name in DirAccess.get_files_at(root_dir.path_join("sent")):
		if not name.ends_with(".json"):
			continue
		var id: String = name.trim_suffix(".json")
		var path: String = root_dir.path_join("sent").path_join(name)
		var archive: Dictionary = read_dict(path)
		if _valid_archive(archive, id):
			continue
		_quarantine(path)
		if archive.get("record") is Dictionary and _valid_record(archive.record, id):
			var restored: Error = _write(root_dir.path_join("pending").path_join(name), archive.record)
			if restored != OK:
				warnings.append("Could not restore an unconfirmed record to the queue: " + id)

func _recover() -> void:
	for sub in ["pending", "routes", "sent", ""]:
		var folder: String = root_dir.path_join(sub)
		for name in DirAccess.get_files_at(folder):
			if not name.ends_with(".tmp"):
				continue
			var path: String = folder.path_join(name)
			var target: String = path.trim_suffix(".tmp")
			var data: Dictionary = read_dict(path)
			var valid: bool = not data.is_empty()
			if sub == "pending":
				valid = _valid_record(data, target.get_file().trim_suffix(".json"))
			elif sub == "routes":
				valid = _valid_route(data)
			elif sub == "sent":
				valid = _valid_archive(data, target.get_file().trim_suffix(".json"))
			if valid and not FileAccess.file_exists(target):
				if DirAccess.rename_absolute(path, target) != OK:
					warnings.append("Could not recover " + path)
			else:
				_quarantine(path)
	var binding_path: String = root_dir.path_join("bindings.json")
	if FileAccess.file_exists(binding_path) and read_dict(binding_path).is_empty():
		_quarantine(binding_path)

func enqueue(owner: String, payload: Dictionary) -> Error:
	var id: String = payload.get("client_run_id", "")
	var record: Dictionary = {"owner_key": owner, "payload": payload.duplicate(true)}
	if not _valid_record(record, id):
		return ERR_INVALID_DATA
	var archived: Dictionary = read_dict(root_dir.path_join("sent").path_join(id + ".json"))
	if _valid_archive(archived, id):
		return OK if Wire.stringify(archived.get("record", {})) == Wire.stringify(record) else ERR_ALREADY_EXISTS
	if FileAccess.file_exists(root_dir.path_join("sent").path_join(id + ".json")):
		_quarantine(root_dir.path_join("sent").path_join(id + ".json"))
	var result: Error = _write(root_dir.path_join("pending").path_join(id + ".json"), record)
	if result == OK and bindings.has(owner):
		var route: Dictionary = freeze_route(record)
		if route.is_empty():
			return ERR_FILE_CANT_WRITE
	return result

func pending() -> Array:
	var records: Array = []
	if error != OK:
		return records
	for name in DirAccess.get_files_at(root_dir.path_join("pending")):
		if not name.ends_with(".json"):
			continue
		var id: String = name.trim_suffix(".json")
		var path: String = root_dir.path_join("pending").path_join(name)
		var record: Dictionary = read_dict(path)
		if not _valid_record(record, id):
			_quarantine(path)
			continue
		var sent: Dictionary = read_dict(root_dir.path_join("sent").path_join(name))
		if _valid_archive(sent, id):
			continue
		if FileAccess.file_exists(root_dir.path_join("sent").path_join(name)):
			_quarantine(root_dir.path_join("sent").path_join(name))
		records.append(record)
	return records

func bind_owner(owner: String, profile_id: String, base_url: String) -> Error:
	if owner.is_empty() or owner.length() > 128 or not Wire.valid_id(profile_id) or not Wire.valid_url(base_url):
		return ERR_INVALID_PARAMETER
	var route: Dictionary = {"base_url": base_url.trim_suffix("/"), "profile_id": profile_id}
	if bindings.has(owner) and bindings[owner] != route:
		return ERR_ALREADY_EXISTS
	var updated: Dictionary = bindings.duplicate(true)
	updated[owner] = route
	var result: Error = _write(root_dir.path_join("bindings.json"), updated, true)
	if result != OK:
		return result
	bindings = updated
	for record in pending():
		if record.owner_key == owner and freeze_route(record).is_empty():
			return ERR_FILE_CANT_WRITE
	return OK

func freeze_route(record: Dictionary) -> Dictionary:
	var id: String = record.payload.client_run_id
	var path: String = root_dir.path_join("routes").path_join(id + ".json")
	if FileAccess.file_exists(path):
		var route: Dictionary = read_dict(path)
		if _valid_route(route):
			return route
		_quarantine(path)
	if not _valid_route(bindings.get(record.owner_key)):
		return {}
	var route: Dictionary = bindings[record.owner_key].duplicate(true)
	return route if _write(path, route) == OK else {}

func mark_sent(record: Dictionary, receipt: Dictionary) -> Error:
	var id: String = record.payload.client_run_id
	var route: Dictionary = freeze_route(record)
	if route.is_empty() or receipt.get("client_run_id") != id or receipt.get("profile_id") != route.profile_id or not Wire.valid_id(str(receipt.get("id", ""))):
		return ERR_INVALID_DATA
	var archive: Dictionary = {"record": record, "receipt": receipt, "route": route}
	var destination: String = root_dir.path_join("sent").path_join(id + ".json")
	var previous: Dictionary = read_dict(destination)
	if _valid_archive(previous, id) and previous.receipt.id == receipt.id:
		return OK
	if FileAccess.file_exists(destination) and not _valid_archive(previous, id):
		_quarantine(destination)
	var result: Error = _write(destination, archive)
	if result != OK:
		return result
	# Receipt is durable before pending cleanup. A crash here remains idempotent.
	var pending_path: String = root_dir.path_join("pending").path_join(id + ".json")
	if FileAccess.file_exists(pending_path):
		DirAccess.remove_absolute(pending_path)
	return OK
