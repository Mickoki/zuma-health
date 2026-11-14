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
	pending() # Detect/quarantine damaged records at startup, before reporting readiness.
	if warnings.is_empty() and not DirAccess.get_files_at(root_dir.path_join("corrupt")).is_empty():
		warnings.append("В каталоге corrupt есть записи для восстановления; они не удалены")

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
	warnings.append("Повреждённая/незавершённая запись сохранена: %s (код %d)" % [path, result])

func _valid_record(record: Dictionary, id: String) -> bool:
	return Wire.valid_uuid(id) and record.get("owner_key", "") is String and not str(record.get("owner_key", "")).is_empty() and record.get("payload") is Dictionary and record.payload.get("client_run_id") == id and record.payload.get("game_id") in ["fifteen", "pairs", "math", "chimp"]

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
			if valid and not FileAccess.file_exists(target):
				if DirAccess.rename_absolute(path, target) != OK:
					warnings.append("Не удалось восстановить " + path)
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
	if not archived.is_empty():
		return OK if Wire.stringify(archived.get("record", {})) == Wire.stringify(record) else ERR_ALREADY_EXISTS
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
		if sent.get("receipt") is Dictionary and sent.receipt.get("client_run_id") == id and Wire.valid_id(str(sent.receipt.get("id", ""))):
			continue
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
		return route if Wire.valid_id(str(route.get("profile_id", ""))) and Wire.valid_url(str(route.get("base_url", ""))) else {}
	if not bindings.has(record.owner_key):
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
	if not previous.is_empty() and previous.get("receipt", {}).get("id") == receipt.id:
		return OK
	var result: Error = _write(destination, archive)
	if result != OK:
		return result
	# Receipt is durable before pending cleanup. A crash here remains idempotent.
	var pending_path: String = root_dir.path_join("pending").path_join(id + ".json")
	if FileAccess.file_exists(pending_path):
		DirAccess.remove_absolute(pending_path)
	return OK
