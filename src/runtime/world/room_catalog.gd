class_name RoomCatalog
extends RefCounted

## Strict registry for native combat room assets and the data for mechanisms
## shared by those rooms. Room identity is supplied by the caller; the catalog
## selects an asset by layout and an optional room-specific spawn profile.

const CONTENT_PATH := "res://content/rooms/combat/room_catalog.json"
const SCHEMA_VERSION := 1
const TOP_LEVEL_FIELDS: Array[String] = ["schema_version", "rooms"]
const ASSET_FIELDS: Array[String] = [
	"world_scene_path", "manifest_path", "gameplay_digest", "presentation_digest", "schema_version",
]
const PRESENTATION_FIELDS: Array[String] = ["display_name", "concept", "landmark", "entry_hint", "exit_hint"]
const ROOM_FIELDS: Array[String] = [
	"world_scene_path", "manifest_path", "gameplay_digest", "presentation_digest", "schema_version",
	"layout_id", "presentation", "spawn_profiles",
]
const OPTIONAL_ROOM_FIELDS: Array[String] = ["room_id"]
const PROFILE_PATTERNS: Array[String] = ["grid", "alternating_rows", "radial", "fan", "approach_band", "explicit"]

var load_errors: Array[String] = []
var _data: Dictionary = {}
var _rooms: Dictionary = {}


func _init(path: String = CONTENT_PATH) -> void:
	load_catalog(path)


func load_catalog(path: String = CONTENT_PATH) -> Array[String]:
	var read_result := _read_json(path)
	if not bool(read_result.get("ok", false)):
		load_errors = [String(read_result.get("error", "room catalog: unable to read catalog"))]
		_data.clear()
		_rooms.clear()
		return load_errors.duplicate()
	load_errors = validate_catalog(read_result.get("data", null))
	if not load_errors.is_empty():
		_data.clear()
		_rooms.clear()
		return load_errors.duplicate()
	_data = (read_result.get("data", {}) as Dictionary).duplicate(true)
	_rooms.clear()
	for raw_room in _data.rooms:
		var room: Dictionary = raw_room
		_rooms[String(room.layout_id)] = room.duplicate(true)
	return []


func validate_catalog(candidate: Variant) -> Array[String]:
	var failures: Array[String] = []
	if not candidate is Dictionary:
		return ["room_catalog: root must be an object"]
	var data: Dictionary = candidate
	_check_exact_fields(data, TOP_LEVEL_FIELDS, "room_catalog", failures)
	if not _is_exact_integer(data.get("schema_version", null)) or int(data.get("schema_version", 0)) != SCHEMA_VERSION:
		failures.append("room_catalog: schema_version must be %d" % SCHEMA_VERSION)
	var rooms_value: Variant = data.get("rooms", null)
	if not rooms_value is Array:
		failures.append("room_catalog: rooms must be an array")
		return failures
	if (rooms_value as Array).is_empty():
		failures.append("room_catalog: rooms must contain at least one entry")
	var seen: Dictionary = {}
	for index in (rooms_value as Array).size():
		var raw_room: Variant = (rooms_value as Array)[index]
		if not raw_room is Dictionary:
			failures.append("room_catalog: rooms[%d] must be an object" % index)
			continue
		var room: Dictionary = raw_room
		var context := "room_catalog: rooms[%d]" % index
		_check_exact_fields(room, ROOM_FIELDS, context, failures, OPTIONAL_ROOM_FIELDS)
		var layout_id := _required_id(room.get("layout_id", null), context, "layout_id", failures)
		if not layout_id.is_empty():
			if seen.has(layout_id):
				failures.append("room_catalog: duplicate layout_id '%s'" % layout_id)
			seen[layout_id] = true
		if room.has("room_id"):
			_required_id(room.get("room_id", null), context, "room_id", failures)
		_validate_asset(room, layout_id, failures)
		_validate_presentation(room.get("presentation", null), context, failures)
		_validate_spawn_profiles(room.get("spawn_profiles", null), context, failures)
	return failures


func resolve(room: Variant) -> Dictionary:
	if not load_errors.is_empty():
		return {"ok": false, "error": "room_catalog_invalid", "errors": load_errors.duplicate()}
	if not room is Dictionary:
		return {"ok": false, "error": "invalid_room"}
	var room_data: Dictionary = room
	for key: String in ["layout_id", "layout"]:
		if room_data.has(key) and (not room_data[key] is String or String(room_data[key]).strip_edges().is_empty()):
			return {"ok": false, "error": "invalid_room_layout"}
	if room_data.has("layout_id") and room_data.has("layout") and room_data["layout_id"] != room_data["layout"]:
		return {"ok": false, "error": "room_layout_conflict"}
	if room_data.has("room_id") and room_data.has("id") and room_data["room_id"] != room_data["id"]:
		return {"ok": false, "error": "room_identity_conflict"}
	if room_data.has("room_id") or room_data.has("id"):
		var room_id_value: Variant = room_data.get("room_id", room_data.get("id", null))
		if not room_id_value is String or String(room_id_value).strip_edges().is_empty():
			return {"ok": false, "error": "invalid_room_id"}
	var layout_id := _room_layout_id(room_data)
	if layout_id.is_empty():
		return {"ok": false, "error": "missing_room_layout"}
	if not _rooms.has(layout_id):
		return {"ok": false, "error": "unknown_room_layout", "layout_id": layout_id}
	var entry: Dictionary = (_rooms[layout_id] as Dictionary).duplicate(true)
	var asset: Dictionary = {}
	for field: String in ASSET_FIELDS:
		asset[field] = entry.get(field)
	# JSON numbers are represented as floats by Godot's parser.  The asset
	# contract stores its schema version as an integer, so normalize this one
	# exact integer at the catalog boundary instead of leaking parser types into
	# WorldAsset.
	asset["schema_version"] = int(asset.get("schema_version", 0))
	var result := {
		"ok": true,
		"error": "",
		"layout_id": layout_id,
		"room_id": String(room_data.get("room_id", room_data.get("id", ""))),
		"asset": asset.duplicate(true),
		"presentation": (entry.get("presentation", {}) as Dictionary).duplicate(true),
		"spawn_profiles": (entry.get("spawn_profiles", {}) as Dictionary).duplicate(true),
	}
	for field: String in ASSET_FIELDS:
		result[field] = asset.get(field, null)
	result["native_scene_path"] = String(asset.get("world_scene_path", ""))
	return result


func presentation(layout_id: String) -> Dictionary:
	var resolved := resolve({"layout_id": layout_id})
	if not bool(resolved.get("ok", false)):
		return {}
	return (resolved.get("presentation", {}) as Dictionary).duplicate(true)


## Generates authored spawn offsets for an existing mechanism. Profiles are
## content data; this method only interprets the five reusable constructions.
## A profile that cannot satisfy the requested count fails closed with no
## center fallback, so a room must explicitly provide enough legal sockets.
func spawn_offsets(room: Variant, count: int) -> Array[Vector2]:
	var result := spawn_offsets_result(room, count)
	var offsets: Array[Vector2] = []
	var value: Variant = result.get("offsets", [])
	if value is Array:
		for point: Variant in value:
			if point is Vector2:
				offsets.append(point)
	return offsets


## Returns an explicit failure reason for room assembly while preserving the
## historical Array-returning convenience wrapper above. Empty offsets are a
## valid result only for an explicit zero-count request.
func spawn_offsets_result(room: Variant, count: int) -> Dictionary:
	if count < 0:
		return {"ok": false, "error": "invalid_spawn_count", "offsets": []}
	if not room is Dictionary:
		return {"ok": false, "error": "invalid_room", "offsets": []}
	var room_data: Dictionary = room
	var room_id_value: Variant = room_data.get("room_id", room_data.get("id", null))
	if not room_id_value is String or String(room_id_value).strip_edges().is_empty():
		return {"ok": false, "error": "missing_room_id", "offsets": []}
	var resolved := resolve(room_data)
	if not bool(resolved.get("ok", false)):
		return {"ok": false, "error": String(resolved.get("error", "room_resolution_failed")), "offsets": []}
	if count == 0:
		return {"ok": true, "error": "", "offsets": []}
	var profiles: Dictionary = resolved.get("spawn_profiles", {})
	var room_id := String(room_id_value).strip_edges()
	var profile_value: Variant = profiles.get(room_id, profiles.get("default", null))
	if not profile_value is Dictionary:
		return {"ok": false, "error": "missing_spawn_profile", "offsets": []}
	var offsets := _generate_profile(profile_value as Dictionary, count)
	if offsets.size() != count:
		return {"ok": false, "error": "insufficient_spawn_sockets", "offsets": []}
	for point: Vector2 in offsets:
		if not point.is_finite():
			return {"ok": false, "error": "invalid_spawn_socket", "offsets": []}
	return {"ok": true, "error": "", "offsets": offsets}


func catalog() -> Dictionary:
	return {
		"ok": load_errors.is_empty(),
		"errors": load_errors.duplicate(),
		"schema_version": SCHEMA_VERSION,
		"rooms": _data.get("rooms", []).duplicate(true) if _data.get("rooms", []) is Array else [],
	}


func _validate_asset(room: Dictionary, layout_id: String, failures: Array[String]) -> void:
	var context := "room_catalog: %s" % layout_id if not layout_id.is_empty() else "room_catalog: asset"
	for field: String in ["world_scene_path", "manifest_path"]:
		if not room.get(field, null) is String:
			failures.append("%s: invalid_asset_path:%s" % [context, field])
			continue
		var path := String(room.get(field, "")).strip_edges()
		if path.is_empty():
			failures.append("%s: missing_asset_path:%s" % [context, field])
			continue
		if not path.begins_with("res://"):
			failures.append("%s: invalid_asset_path:%s" % [context, field])
			continue
		if field == "world_scene_path":
			if not path.ends_with(".tscn"):
				failures.append("%s: invalid_asset_path:%s" % [context, field])
			elif not ResourceLoader.exists(path):
				failures.append("%s: missing_asset:%s" % [context, field])
		elif not FileAccess.file_exists(path):
			failures.append("%s: missing_asset:%s" % [context, field])
	for field: String in ["gameplay_digest", "presentation_digest"]:
		if not room.get(field, null) is String or String(room[field]).strip_edges().is_empty():
			failures.append("%s: missing_digest:%s" % [context, field])
	if not _is_exact_integer(room.get("schema_version", null)) or int(room.get("schema_version", 0)) != SCHEMA_VERSION:
		failures.append("%s: schema_version must be %d" % [context, SCHEMA_VERSION])


func _validate_presentation(value: Variant, context: String, failures: Array[String]) -> void:
	if not value is Dictionary:
		failures.append("%s: presentation must be an object" % context)
		return
	var presentation_value: Dictionary = value
	_check_exact_fields(presentation_value, PRESENTATION_FIELDS, "%s.presentation" % context, failures)
	for field: String in PRESENTATION_FIELDS:
		if not presentation_value.get(field, "") is String or String(presentation_value.get(field, "")).strip_edges().is_empty():
			failures.append("%s.presentation: %s must be a non-empty string" % [context, field])


func _validate_spawn_profiles(value: Variant, context: String, failures: Array[String]) -> void:
	if not value is Dictionary:
		failures.append("%s: spawn_profiles must be an object" % context)
		return
	var profiles: Dictionary = value
	if not profiles.has("default"):
		failures.append("%s.spawn_profiles: missing default profile" % context)
	for profile_id: Variant in profiles.keys():
		if not profile_id is String or String(profile_id).strip_edges().is_empty():
			failures.append("%s.spawn_profiles: profile ids must be non-empty strings" % context)
			continue
		var profile: Variant = profiles[profile_id]
		if not profile is Dictionary:
			failures.append("%s.spawn_profiles.%s: profile must be an object" % [context, profile_id])
			continue
		_validate_profile(profile as Dictionary, "%s.spawn_profiles.%s" % [context, profile_id], failures)


func _validate_profile(profile: Dictionary, context: String, failures: Array[String]) -> void:
	var pattern := String(profile.get("pattern", ""))
	var fields: Array[String] = ["pattern"]
	match pattern:
		"grid": fields += ["origin", "columns", "column_step", "row_step"]
		"alternating_rows": fields += ["origin", "columns", "x_step", "row_values"]
		"radial": fields += ["center", "radius", "start_angle_degrees"]
		"fan": fields += ["origin", "radius", "angles_degrees"]
		"approach_band": fields += ["origin", "distance", "offsets_y"]
		"explicit": fields += ["offsets"]
		_:
			failures.append("%s: unknown pattern '%s'" % [context, pattern])
			return
	_check_exact_fields(profile, fields, context, failures)
	if pattern in ["grid", "alternating_rows"]:
		_validate_vector(profile.get("origin", null), "%s.origin" % context, failures)
		if not _is_exact_integer(profile.get("columns", null)) or int(profile.get("columns", 0)) <= 0:
			failures.append("%s.columns: must be a positive integer" % context)
	if pattern == "grid":
		_validate_number(profile.get("column_step", null), "%s.column_step" % context, failures, true)
		_validate_number(profile.get("row_step", null), "%s.row_step" % context, failures, true)
	elif pattern == "alternating_rows":
		_validate_number(profile.get("x_step", null), "%s.x_step" % context, failures, true)
		_validate_number_array(profile.get("row_values", null), "%s.row_values" % context, failures, true)
	elif pattern == "radial":
		_validate_vector(profile.get("center", null), "%s.center" % context, failures)
		_validate_number(profile.get("radius", null), "%s.radius" % context, failures, true)
		_validate_number(profile.get("start_angle_degrees", null), "%s.start_angle_degrees" % context, failures, false)
	elif pattern == "fan":
		_validate_vector(profile.get("origin", null), "%s.origin" % context, failures)
		_validate_number(profile.get("radius", null), "%s.radius" % context, failures, true)
		_validate_number_array(profile.get("angles_degrees", null), "%s.angles_degrees" % context, failures, true)
	elif pattern == "approach_band":
		_validate_vector(profile.get("origin", null), "%s.origin" % context, failures)
		_validate_number(profile.get("distance", null), "%s.distance" % context, failures, true)
		_validate_number_array(profile.get("offsets_y", null), "%s.offsets_y" % context, failures, true)
	elif pattern == "explicit":
		_validate_vector_array(profile.get("offsets", null), "%s.offsets" % context, failures, true)


func _generate_profile(profile: Dictionary, count: int) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var pattern := String(profile.get("pattern", ""))
	match pattern:
		"grid":
			var grid_origin := _vector_from_array(profile.origin)
			var columns := maxi(1, int(profile.columns))
			for index in count:
				result.append(grid_origin + Vector2(float(index % columns) * float(profile.column_step), float(index / columns) * float(profile.row_step)))
		"alternating_rows":
			var alternating_origin := _vector_from_array(profile.origin)
			var row_values: Array = profile.row_values
			var columns := maxi(1, int(profile.columns))
			for index in count:
				result.append(Vector2(alternating_origin.x + float(index % columns) * float(profile.x_step), float(row_values[index % row_values.size()])))
		"radial":
			var radial_center := _vector_from_array(profile.center)
			var radial_radius := float(profile.radius)
			for index in count:
				var radial_angle := deg_to_rad(float(profile.start_angle_degrees)) + TAU * float(index) / float(maxi(1, count))
				result.append(radial_center + Vector2.from_angle(radial_angle) * radial_radius)
		"fan":
			var angles: Array = profile.angles_degrees
			if count > angles.size():
				return []
			var fan_origin := _vector_from_array(profile.origin)
			for index in count:
				result.append(fan_origin + Vector2.from_angle(deg_to_rad(float(angles[index]))) * float(profile.radius))
		"approach_band":
			var offsets: Array = profile.offsets_y
			if count > offsets.size():
				return []
			var band_origin := _vector_from_array(profile.origin)
			var band_distance := float(profile.distance)
			for index in count:
				var offset_y := float(offsets[index])
				var offset_x := sqrt(maxf(0.0, band_distance * band_distance - offset_y * offset_y))
				result.append(band_origin + Vector2(offset_x, offset_y))
		"explicit":
			var offsets: Array = profile.offsets
			if count > offsets.size():
				return []
			for index in count:
				result.append(_vector_from_array(offsets[index]))
	return result


func _room_layout_id(room: Dictionary) -> String:
	var layout_id := String(room.get("layout_id", "")).strip_edges()
	if layout_id.is_empty():
		layout_id = String(room.get("layout", "")).strip_edges()
	return layout_id


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "room_catalog: content file not found: %s" % path}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "room_catalog: cannot open content file: %s" % path}
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	if parse_error != OK:
		return {"ok": false, "error": "room_catalog: invalid JSON at line %d: %s" % [parser.get_error_line(), parser.get_error_message()]}
	return {"ok": true, "data": parser.data}


func _check_exact_fields(data: Dictionary, required: Array[String], context: String, failures: Array[String], optional: Array[String] = []) -> void:
	for field: String in required:
		if not data.has(field):
			failures.append("%s: missing_field:%s" % [context, field])
	for key: Variant in data.keys():
		var field := String(key)
		if field not in required and field not in optional:
			failures.append("%s: unknown_field:%s" % [context, field])


func _required_id(value: Variant, context: String, field: String, failures: Array[String]) -> String:
	if not value is String or String(value).strip_edges().is_empty():
		failures.append("%s: %s must be a non-empty string id" % [context, field])
		return ""
	var value_text := String(value)
	for index in value_text.length():
		var code := value_text.unicode_at(index)
		if not (code >= 97 and code <= 122) and not (code >= 48 and code <= 57) and code != 95 and code != 45:
			failures.append("%s: %s '%s' must use stable lowercase ASCII id characters" % [context, field, value_text])
			break
	return value_text


func _validate_vector(value: Variant, context: String, failures: Array[String]) -> void:
	if not value is Array or (value as Array).size() != 2:
		failures.append("%s: must be a two-number array" % context)
		return
	for component: Variant in value:
		if component is bool or (not component is int and not component is float) or not is_finite(float(component)):
			failures.append("%s: must contain only finite numbers" % context)


func _validate_number(value: Variant, context: String, failures: Array[String], positive: bool) -> void:
	if value is bool or (not value is int and not value is float) or not is_finite(float(value)) or (positive and float(value) <= 0.0):
		failures.append("%s: must be %s finite number" % [context, "a positive" if positive else "a"])


func _validate_number_array(value: Variant, context: String, failures: Array[String], require_non_empty: bool) -> void:
	if not value is Array or (require_non_empty and (value as Array).is_empty()):
		failures.append("%s: must be a %snumber array" % [context, "non-empty " if require_non_empty else ""])
		return
	for component: Variant in value:
		if component is bool or (not component is int and not component is float) or not is_finite(float(component)):
			failures.append("%s: must contain only finite numbers" % context)


func _validate_vector_array(value: Variant, context: String, failures: Array[String], require_non_empty: bool) -> void:
	if not value is Array or (require_non_empty and (value as Array).is_empty()):
		failures.append("%s: must be a %stwo-number array" % [context, "non-empty " if require_non_empty else ""])
		return
	for index in (value as Array).size():
		_validate_vector((value as Array)[index], "%s[%d]" % [context, index], failures)


func _vector_from_array(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1])) if value.size() == 2 else Vector2.ZERO


func _is_exact_integer(value: Variant) -> bool:
	if value is bool:
		return false
	if value is int:
		return true
	return value is float and is_finite(float(value)) and float(value) == floorf(float(value))
