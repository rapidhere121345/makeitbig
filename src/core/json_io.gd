extends RefCounted

## Shared JSON file readers. Each reader keeps one explicit failure contract so
## call sites can pick the shape they report on; none of them logs errors.

const STATUS_OK := "ok"
const STATUS_MISSING := "missing"
const STATUS_UNREADABLE := "unreadable"
const STATUS_INVALID := "invalid"


## Returns the parsed top-level object, or {} when the file is missing,
## unreadable, not JSON, or not an object.
static func read_object(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed as Dictionary if parsed is Dictionary else {}


## Like read_object but reports why it failed: {"status": STATUS_*, "data": Dictionary}.
## "data" is empty unless status is STATUS_OK.
static func read_object_status(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"status": STATUS_MISSING, "data": {}}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"status": STATUS_UNREADABLE, "data": {}}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return {"status": STATUS_INVALID, "data": {}}
	return {"status": STATUS_OK, "data": parsed}


## Registry-style reader returning {"ok": true, "data": Variant} or
## {"ok": false, "error": String} with messages prefixed by label. When
## require_object is false the root may be any JSON value.
static func read_result(path: String, label: String, require_object: bool = false) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "%s: content file not found: %s" % [label, path]}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "%s: cannot open content file: %s" % [label, path]}
	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	if parse_error != OK:
		return {"ok": false, "error": "%s: invalid JSON at line %d: %s" % [label, json.get_error_line(), json.get_error_message()]}
	if require_object and not json.data is Dictionary:
		return {"ok": false, "error": "%s: JSON root must be an object" % label}
	return {"ok": true, "data": json.data}
