extends RefCounted

static func normalize(value: Variant) -> Variant:
	# JSON parsing in Godot produces floats. Restore exact integral wire values
	# before posting a durable record to Go's integer fields.
	if value is float and is_finite(value) and floor(value) == value and abs(value) <= 9007199254740991.0:
		return int(value)
	if value is Array:
		var items: Array = []
		for item in value:
			items.append(normalize(item))
		return items
	if value is Dictionary:
		var object: Dictionary = {}
		for key in value:
			object[key] = normalize(value[key])
		return object
	return value

static func stringify(value: Variant) -> String:
	return JSON.stringify(normalize(value), "", true)

static func valid_uuid(value: String) -> bool:
	var regex := RegEx.new()
	regex.compile("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
	return regex.search(value) != null

static func valid_id(value: String) -> bool:
	var regex := RegEx.new()
	regex.compile("^[0-9a-f]{32}$")
	return regex.search(value) != null

static func valid_url(value: String) -> bool:
	var regex := RegEx.new()
	regex.compile("^http://(localhost|127\\.0\\.0\\.1|\\[::1\\])(:([0-9]{1,5}))?/?$")
	var match_value: RegExMatch = regex.search(value)
	if match_value == null:
		return false
	var port: String = match_value.get_string(3)
	return port.is_empty() or int(port) >= 1 and int(port) <= 65535
