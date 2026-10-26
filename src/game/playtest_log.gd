class_name PlaytestLog
extends RefCounted

## Append-only, local JSONL events for rapid-prototype playtests.
## This log is observational only and must never feed authoritative simulation.

const SCHEMA_VERSION := 1
const CoreResult := preload("res://src/core/result.gd")
const DEFAULT_DIRECTORY := "user://playtest"

var _directory_path: String
var _session_id := ""
var _log_path := ""
var _sequence := 0
var _context: Dictionary = {}
var _file: FileAccess


func _init(directory_path: String = DEFAULT_DIRECTORY) -> void:
	_directory_path = directory_path.strip_edges()
	if _directory_path.is_empty():
		_directory_path = DEFAULT_DIRECTORY


func start_session(context: Dictionary, requested_session_id: String = "") -> Dictionary:
	if _file != null:
		return CoreResult.failure("session_already_started")
	var normalized_id := _normalized_session_id(requested_session_id)
	if normalized_id.is_empty():
		normalized_id = "%d-%d" % [int(Time.get_unix_time_from_system() * 1000.0), OS.get_process_id()]
	var absolute_directory := ProjectSettings.globalize_path(_directory_path)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_directory)
	if directory_error != OK:
		return CoreResult.failure("log_directory_unavailable")
	_session_id = normalized_id
	_log_path = _directory_path.path_join("session-%s.jsonl" % _session_id)
	_file = FileAccess.open(_log_path, FileAccess.WRITE)
	if _file == null:
		_session_id = ""
		_log_path = ""
		return CoreResult.failure("log_file_unavailable")
	_sequence = 0
	_context = context.duplicate(true)
	var recorded := record("session_started", {})
	if not bool(recorded.get("ok", false)):
		close()
		return recorded
	return {
		"ok": true,
		"session_id": _session_id,
		"path": _log_path,
		"event": (recorded.event as Dictionary).duplicate(true),
	}


func record(event_id: String, payload: Dictionary = {}) -> Dictionary:
	if _file == null:
		return CoreResult.failure("session_not_started")
	var normalized_event_id := event_id.strip_edges().to_lower()
	if not _valid_token(normalized_event_id):
		return CoreResult.failure("invalid_event_id")
	var event := {
		"schema_version": SCHEMA_VERSION,
		"sequence": _sequence,
		"session_id": _session_id,
		"event_id": normalized_event_id,
		"unix_msec": int(Time.get_unix_time_from_system() * 1000.0),
		"context": _context.duplicate(true),
		"payload": payload.duplicate(true),
	}
	_file.store_line(JSON.stringify(event))
	_file.flush()
	if _file.get_error() != OK:
		return CoreResult.failure("log_write_failed")
	_sequence += 1
	return {"ok": true, "event": event.duplicate(true)}


func finish(payload: Dictionary = {}) -> Dictionary:
	if _file == null:
		return CoreResult.failure("session_not_started")
	var recorded := record("session_finished", payload)
	close()
	return recorded


func close() -> void:
	if _file != null:
		_file.close()
	_file = null


func is_active() -> bool:
	return _file != null


func log_path() -> String:
	return _log_path


func _normalized_session_id(value: String) -> String:
	var normalized := value.strip_edges().to_lower()
	return normalized if _valid_token(normalized) else ""


func _valid_token(value: String) -> bool:
	if value.is_empty():
		return false
	for index in value.length():
		var character := value.substr(index, 1)
		var code := character.unicode_at(0)
		var is_ascii_letter := code >= 97 and code <= 122
		var is_digit := code >= 48 and code <= 57
		if not is_ascii_letter and not is_digit and character not in ["_", "-", "."]:
			return false
	return true

