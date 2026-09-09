class_name SaveStore
extends RefCounted

## Versioned JSON persistence with deterministic encoding and A/B recovery.
##
## SaveStore only stores and restores the supplied payload.  It never reads the
## clock and never interprets exit-time fields, so offline progress belongs to a
## separate, explicitly invoked game system rather than the persistence layer.

const FORMAT_VERSION: int = 1
const CHECKSUM_ALGORITHM: String = "sha256"
const MAX_SAFE_JSON_INTEGER: int = 9007199254740991
const SLOT_NAMES: Array[String] = ["a", "b"]

var directory_path: String


func _init(p_directory_path: String = "user://saves") -> void:
	directory_path = p_directory_path


func save(payload: Variant) -> Dictionary:
	var payload_encoding: Dictionary = _encode_json(payload)
	if not bool(payload_encoding.ok):
		return {"ok": false, "error": str(payload_encoding.error)}

	var slots: Array[Dictionary] = _read_slots()
	var newest_generation: int = 0
	for slot in slots:
		if bool(slot.valid):
			newest_generation = maxi(newest_generation, int(slot.generation))
	var generation: int = newest_generation + 1
	if generation > MAX_SAFE_JSON_INTEGER:
		return {"ok": false, "error": "save generation exceeds JSON's exact integer range"}

	var target_name: String = _choose_target(slots)
	var protected_document := {
		"checksum_algorithm": CHECKSUM_ALGORITHM,
		"format_version": FORMAT_VERSION,
		"generation": generation,
		"payload": payload,
	}
	var protected_encoding: Dictionary = _encode_json(protected_document)
	if not bool(protected_encoding.ok):
		return {"ok": false, "error": str(protected_encoding.error)}
	var checksum: String = _sha256(str(protected_encoding.text))
	if checksum.is_empty():
		return {"ok": false, "error": "could not calculate SHA-256"}

	var envelope: Dictionary = protected_document.duplicate(true)
	envelope["checksum"] = checksum
	var envelope_encoding: Dictionary = _encode_json(envelope)
	if not bool(envelope_encoding.ok):
		return {"ok": false, "error": str(envelope_encoding.error)}
	var write_error: String = _write_slot(target_name, str(envelope_encoding.text))
	if not write_error.is_empty():
		return {"ok": false, "error": write_error}
	return {"ok": true, "generation": generation, "slot": target_name}


func load_latest() -> Dictionary:
	var newest: Dictionary = {}
	for slot in _read_slots():
		if not bool(slot.valid):
			continue
		if newest.is_empty() or int(slot.generation) > int(newest.generation):
			newest = slot
	if newest.is_empty():
		return {"ok": false, "error": "no valid save slot"}
	return {
		"ok": true,
		"generation": int(newest.generation),
		"payload": newest.payload,
		"slot": str(newest.name),
	}


static func canonical_json(value: Variant) -> String:
	var encoded: Dictionary = _encode_json(value)
	return str(encoded.text) if bool(encoded.ok) else ""


func _read_slots() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	for slot_name in SLOT_NAMES:
		slots.append(_read_slot(slot_name))
	return slots


func _read_slot(slot_name: String) -> Dictionary:
	var invalid := {"valid": false, "name": slot_name, "generation": 0}
	var path: String = _slot_path(slot_name)
	if not FileAccess.file_exists(path):
		return invalid
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return invalid
	var text: String = file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(text) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return invalid
	var envelope: Dictionary = parser.data
	if int(envelope.get("format_version", -1)) != FORMAT_VERSION:
		return invalid
	if str(envelope.get("checksum_algorithm", "")) != CHECKSUM_ALGORITHM:
		return invalid
	if not envelope.has("payload"):
		return invalid
	var generation_value: Variant = envelope.get("generation")
	if not _is_exact_positive_json_integer(generation_value):
		return invalid
	var expected_checksum: String = str(envelope.get("checksum", ""))
	if expected_checksum.length() != 64:
		return invalid
	var protected_document := {
		"checksum_algorithm": CHECKSUM_ALGORITHM,
		"format_version": FORMAT_VERSION,
		"generation": int(generation_value),
		"payload": envelope.payload,
	}
	var protected_encoding: Dictionary = _encode_json(protected_document)
	if not bool(protected_encoding.ok):
		return invalid
	if _sha256(str(protected_encoding.text)) != expected_checksum:
		return invalid
	return {
		"valid": true,
		"name": slot_name,
		"generation": int(generation_value),
		"payload": envelope.payload,
	}


func _choose_target(slots: Array[Dictionary]) -> String:
	for slot in slots:
		if not bool(slot.valid):
			return str(slot.name)
	if int(slots[0].generation) <= int(slots[1].generation):
		return str(slots[0].name)
	return str(slots[1].name)


func _write_slot(slot_name: String, contents: String) -> String:
	var absolute_directory: String = ProjectSettings.globalize_path(directory_path)
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(absolute_directory)
	if directory_error != OK:
		return "could not create save directory: %s" % error_string(directory_error)
	var target_path: String = _slot_path(slot_name)
	var temporary_path: String = target_path + ".tmp"
	if FileAccess.file_exists(temporary_path):
		DirAccess.remove_absolute(temporary_path)
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return "could not open temporary save: %s" % error_string(FileAccess.get_open_error())
	file.store_string(contents)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temporary_path)
		return "could not write temporary save: %s" % error_string(write_error)
	# Replacing only the older slot keeps the other verified generation intact.
	# The temp file lives in the same directory, so the final rename cannot cross
	# filesystems.  Removing the old target is needed by Windows rename semantics.
	if FileAccess.file_exists(target_path):
		var remove_error: Error = DirAccess.remove_absolute(target_path)
		if remove_error != OK:
			DirAccess.remove_absolute(temporary_path)
			return "could not replace old save slot: %s" % error_string(remove_error)
	var rename_error: Error = DirAccess.rename_absolute(temporary_path, target_path)
	if rename_error != OK:
		DirAccess.remove_absolute(temporary_path)
		return "could not publish save slot: %s" % error_string(rename_error)
	return ""


func _slot_path(slot_name: String) -> String:
	return ProjectSettings.globalize_path(directory_path).path_join("save_%s.json" % slot_name)


static func _encode_json(value: Variant) -> Dictionary:
	match typeof(value):
		TYPE_NIL:
			return {"ok": true, "text": "null"}
		TYPE_BOOL:
			return {"ok": true, "text": "true" if bool(value) else "false"}
		TYPE_INT:
			if absi(int(value)) > MAX_SAFE_JSON_INTEGER:
				return {"ok": false, "error": "integer exceeds JSON's exact range"}
			return {"ok": true, "text": str(int(value))}
		TYPE_FLOAT:
			var number: float = float(value)
			if is_nan(number) or is_inf(number):
				return {"ok": false, "error": "non-finite numbers are not valid save data"}
			if number == 0.0:
				return {"ok": true, "text": "0"}
			if absf(number) <= float(MAX_SAFE_JSON_INTEGER) and floor(number) == number:
				return {"ok": true, "text": str(int(number))}
			return {"ok": true, "text": JSON.stringify(number)}
		TYPE_STRING, TYPE_STRING_NAME:
			return {"ok": true, "text": _encode_string(str(value))}
		TYPE_ARRAY:
			var parts: Array[String] = []
			for item in value:
				var item_encoding: Dictionary = _encode_json(item)
				if not bool(item_encoding.ok):
					return item_encoding
				parts.append(str(item_encoding.text))
			return {"ok": true, "text": "[" + ",".join(parts) + "]"}
		TYPE_DICTIONARY:
			var keys: Array[String] = []
			for key in value.keys():
				if typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME:
					return {"ok": false, "error": "save dictionaries require string keys"}
				keys.append(str(key))
			keys.sort()
			var members: Array[String] = []
			for key in keys:
				var member_encoding: Dictionary = _encode_json(value[key])
				if not bool(member_encoding.ok):
					return member_encoding
				members.append(_encode_string(key) + ":" + str(member_encoding.text))
			return {"ok": true, "text": "{" + ",".join(members) + "}"}
		_:
			return {"ok": false, "error": "unsupported save-data type: %s" % type_string(typeof(value))}


static func _encode_string(value: String) -> String:
	var result: String = "\""
	for index in value.length():
		var codepoint: int = value.unicode_at(index)
		match codepoint:
			0x08:
				result += "\\b"
			0x09:
				result += "\\t"
			0x0a:
				result += "\\n"
			0x0c:
				result += "\\f"
			0x0d:
				result += "\\r"
			0x22:
				result += "\\\""
			0x5c:
				result += "\\\\"
			_:
				result += "\\u%04x" % codepoint if codepoint < 0x20 else value.substr(index, 1)
	return result + "\""


static func _sha256(value: String) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(value.to_utf8_buffer()) != OK:
		return ""
	return context.finish().hex_encode()


static func _is_exact_positive_json_integer(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return (
		not is_nan(number)
		and not is_inf(number)
		and number >= 1.0
		and number <= float(MAX_SAFE_JSON_INTEGER)
		and floor(number) == number
	)
