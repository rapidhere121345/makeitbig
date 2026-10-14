class_name SpatialManifest
extends RefCounted

const ArenaGeometryScript := preload("res://src/runtime/geometry/arena_geometry.gd")

## Pure, build-produced spatial data.  It describes authored relationships and
## channel capabilities; it never owns actors, node references or run state.

const FIELDS: Array[String] = [
	"coordinate_convention",
	"stable_bindings",
	"traversal_profiles",
	"regions_and_portals",
	"spawn_interaction_exit_sockets",
	"gameplay_spatial_metadata",
]
const CHANNELS: Array[String] = ["movement", "navigation", "vision", "projectile", "occlusion"]
const SOCKET_KINDS: Array[String] = ["spawn", "interaction", "exit"]
const _VOLATILE_KEYS: Array[String] = [
	"instance_id",
	"node_instance_id",
	"runtime_id",
	"runtime_state",
	"node_instance",
]

var coordinate_convention: Dictionary = {}
var stable_bindings: Array[Dictionary] = []
var traversal_profiles: Array[Dictionary] = []
var regions_and_portals: Array[Dictionary] = []
var spawn_interaction_exit_sockets: Array[Dictionary] = []
var gameplay_spatial_metadata: Dictionary = {}


func _init(value: Variant = {}) -> void:
	if value is Dictionary:
		var normalized := _canonical_payload(value as Dictionary)
		coordinate_convention = normalized["coordinate_convention"]
		stable_bindings = normalized["stable_bindings"]
		traversal_profiles = normalized["traversal_profiles"]
		regions_and_portals = normalized["regions_and_portals"]
		spawn_interaction_exit_sockets = normalized["spawn_interaction_exit_sockets"]
		gameplay_spatial_metadata = normalized["gameplay_spatial_metadata"]
	else:
		_reset()


static func from_dict(value: Variant) -> SpatialManifest:
	return SpatialManifest.new(value if value is Dictionary else {})


## Returns a detached canonical payload.  The six top-level keys are always
## emitted in the same order, and stable collections are ordered by authored
## stable identifiers instead of engine instance ids.
func normalize() -> Dictionary:
	return _canonical_payload(snapshot())


func validate() -> Array[String]:
	return _validate_payload(snapshot())


func is_valid() -> bool:
	return validate().is_empty()


func validation_result() -> Dictionary:
	var errors := validate()
	return {"ok": errors.is_empty(), "errors": errors, "value": snapshot()}


func snapshot() -> Dictionary:
	return _canonical_payload({
		"coordinate_convention": coordinate_convention,
		"stable_bindings": stable_bindings,
		"traversal_profiles": traversal_profiles,
		"regions_and_portals": regions_and_portals,
		"spawn_interaction_exit_sockets": spawn_interaction_exit_sockets,
		"gameplay_spatial_metadata": gameplay_spatial_metadata,
	})


## The digest input is a detached, JSON-safe semantic payload.  Runtime-only
## keys are dropped recursively so adding an actor instance cannot alter a
## build digest.
func digest_input() -> Dictionary:
	return _canonicalize(snapshot())


func digest_sha256() -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(JSON.stringify(digest_input()).to_utf8_buffer()) != OK:
		return ""
	return context.finish().hex_encode()


func bindings_for_channel(channel: String) -> Array[Dictionary]:
	if not CHANNELS.has(channel):
		return []
	var result: Array[Dictionary] = []
	for binding: Dictionary in stable_bindings:
		var channels: Dictionary = binding.get("channels", {})
		if bool(channels.get(channel, false)):
			result.append(binding.duplicate(true))
	return result


func movement_bindings() -> Array[Dictionary]:
	return bindings_for_channel("movement")


## Converts the authored movement binding into the runtime boundary contract.
## JSON manifests use plain arrays; the motor receives Rect2/Vector2 values only
## after this explicit conversion. The first movement binding is canonical after
## stable-id validation has established deterministic ordering.
func movement_geometry() -> Dictionary:
	for binding: Dictionary in movement_bindings():
		if binding.get("kind", "") == "static_blocker":
			continue
		var geometry: Variant = binding.get("geometry", null)
		var normalized := _normalize_movement_geometry(geometry)
		if not normalized.is_empty():
			return normalized
	return {}


func navigation_bindings() -> Array[Dictionary]:
	return bindings_for_channel("navigation")


func vision_occluders() -> Array[Dictionary]:
	return bindings_for_channel("vision")


func projectile_blockers() -> Array[Dictionary]:
	return bindings_for_channel("projectile")


func occlusion_bindings() -> Array[Dictionary]:
	return bindings_for_channel("occlusion")


static func normalize_data(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {"ok": false, "errors": ["invalid_type:spatial_manifest"], "value": {}}
	var candidate: Dictionary = value
	var errors := _validate_payload(candidate)
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "value": {}}
	return {"ok": true, "errors": [], "value": _canonical_payload(candidate)}


static func validate_data(value: Variant) -> Array[String]:
	if not value is Dictionary:
		return ["invalid_type:spatial_manifest"]
	return _validate_payload(value as Dictionary)


static func _validate_payload(data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for field: String in FIELDS:
		if not data.has(field):
			errors.append("missing_field:%s" % field)
	for key: Variant in data.keys():
		var text_key := str(key)
		if not FIELDS.has(text_key):
			errors.append("unknown_field:%s" % text_key)
	if not data.get("coordinate_convention", {}) is Dictionary:
		errors.append("invalid_type:coordinate_convention")
	for field: String in ["stable_bindings", "traversal_profiles", "regions_and_portals", "spawn_interaction_exit_sockets"]:
		if not data.get(field, []) is Array and not data.get(field, []) is Dictionary:
			errors.append("invalid_type:%s" % field)
	if not data.get("gameplay_spatial_metadata", {}) is Dictionary:
		errors.append("invalid_type:gameplay_spatial_metadata")
	_validate_collection(data.get("stable_bindings", []), "stable_bindings", errors, true)
	_validate_collection(data.get("traversal_profiles", []), "traversal_profiles", errors, false)
	_validate_collection(data.get("regions_and_portals", []), "regions_and_portals", errors, false)
	_validate_collection(data.get("spawn_interaction_exit_sockets", []), "spawn_interaction_exit_sockets", errors, false)
	_validate_unique_ids(data.get("stable_bindings", []), "stable_bindings", errors, "duplicate_stable_id", true)
	_validate_sockets(data.get("spawn_interaction_exit_sockets", []), errors)
	return errors


static func _validate_collection(value: Variant, field: String, errors: Array[String], check_channels: bool) -> void:
	var entries: Array = _collection_entries(value)
	for index in entries.size():
		if not entries[index] is Dictionary:
			errors.append("invalid_entry:%s[%d]" % [field, index])
			continue
		var entry: Dictionary = entries[index]
		if field == "stable_bindings":
			var identifier := _entry_id(entry)
			if identifier.is_empty():
				errors.append("missing_stable_id:%s[%d]" % [field, index])
		var movement_enabled := false
		if check_channels and entry.has("channels"):
			if not entry["channels"] is Dictionary:
				errors.append("invalid_channels:%s[%d]" % [field, index])
				continue
			for channel_key: Variant in (entry["channels"] as Dictionary).keys():
				var channel := str(channel_key)
				if not CHANNELS.has(channel):
					errors.append("unknown_channel:%s" % channel)
				elif not (entry["channels"] as Dictionary)[channel_key] is bool:
					errors.append("invalid_channel_value:%s" % channel)
			movement_enabled = bool((entry["channels"] as Dictionary).get("movement", false))
		if check_channels and movement_enabled:
			if not entry.has("geometry"):
				errors.append("missing_movement_geometry:%s[%d]" % [field, index])
			elif entry.get("kind", "") == "static_blocker":
				var solid := ArenaGeometryScript.normalize_native_static_geometry(entry["geometry"])
				if not bool(solid.get("ok", false)):
					errors.append("invalid_static_geometry:%s[%d]" % [field, index])
			elif _normalize_movement_geometry(entry.get("geometry", null)).is_empty():
				errors.append("invalid_movement_geometry:%s[%d]" % [field, index])


static func _validate_unique_ids(value: Variant, field: String, errors: Array[String], duplicate_error: String, require_id: bool) -> void:
	var seen: Dictionary = {}
	var entries: Array = _collection_entries(value)
	for index in entries.size():
		if not entries[index] is Dictionary:
			continue
		var identifier := _entry_id(entries[index] as Dictionary)
		if identifier.is_empty():
			if require_id and field == "stable_bindings":
				errors.append("missing_stable_id:%s[%d]" % [field, index])
			continue
		if seen.has(identifier):
			errors.append("%s:%s" % [duplicate_error, identifier])
		else:
			seen[identifier] = true


static func _validate_sockets(value: Variant, errors: Array[String]) -> void:
	var seen: Dictionary = {}
	var entries: Array = _collection_entries(value)
	for index in entries.size():
		if not entries[index] is Dictionary:
			continue
		var entry: Dictionary = entries[index]
		var identifier := _entry_id(entry)
		if identifier.is_empty():
			errors.append("missing_socket_id:spawn_interaction_exit_sockets[%d]" % index)
		else:
			if seen.has(identifier):
				errors.append("duplicate_socket_id:%s" % identifier)
			else:
				seen[identifier] = true
		var kind := String(entry.get("kind", "")).strip_edges().to_lower()
		if kind not in SOCKET_KINDS:
			errors.append("invalid_socket_kind:%s[%d]" % [kind if not kind.is_empty() else "missing", index])


static func _normalize_movement_geometry(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var source: Dictionary = value
	var kind := String(source.get("type", "")).strip_edges().to_lower()
	match kind:
		"rect":
			var rect := _rect_from(source.get("rect", null))
			if not _valid_rect(rect):
				return {}
			return {"type": "rect", "rect": rect}
		"corridor":
			var corridor := _rect_from(source.get("rect", null))
			var half_height_value: Variant = source.get("half_height", null)
			if not _valid_rect(corridor) or not _valid_number(half_height_value):
				return {}
			var half_height := float(half_height_value)
			if String(source.get("axis", "horizontal")).to_lower() != "horizontal" or half_height <= 0.0 or half_height > corridor.size.y * 0.5:
				return {}
			return {
				"type": "corridor",
				"rect": corridor,
				"axis": "horizontal",
				"half_height": half_height,
			}
		"ring":
			var center := _vector2_from(source.get("center", null))
			var inner_value: Variant = source.get("inner_radius", null)
			var outer_value: Variant = source.get("outer_radius", null)
			if not _valid_vector(center) or not _valid_number(inner_value) or not _valid_number(outer_value):
				return {}
			var inner := float(inner_value)
			var outer := float(outer_value)
			if inner < 0.0 or outer <= inner:
				return {}
			return {
				"type": "ring",
				"center": center,
				"inner_radius": inner,
				"outer_radius": outer,
			}
	return {}


static func _rect_from(value: Variant) -> Rect2:
	if value is Rect2:
		return value as Rect2
	if value is Array:
		var values: Array = value as Array
		if values.size() == 4 and values.all(func(item: Variant) -> bool: return _valid_number(item)):
			return Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))
	return Rect2()


static func _vector2_from(value: Variant) -> Vector2:
	if value is Vector2:
		return value as Vector2
	if value is Array:
		var values: Array = value as Array
		if values.size() == 2 and values.all(func(item: Variant) -> bool: return _valid_number(item)):
			return Vector2(float(values[0]), float(values[1]))
	return Vector2.INF


static func _valid_rect(value: Rect2) -> bool:
	return value.position.is_finite() and value.size.is_finite() and value.size.x > 0.0 and value.size.y > 0.0


static func _valid_vector(value: Vector2) -> bool:
	return value.is_finite()


static func _valid_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _canonical_payload(data: Dictionary) -> Dictionary:
	return {
		"coordinate_convention": _canonicalize(data.get("coordinate_convention", {})),
		"stable_bindings": _canonical_collection(data.get("stable_bindings", []), true),
		"traversal_profiles": _canonical_collection(data.get("traversal_profiles", []), false),
		"regions_and_portals": _canonical_collection(data.get("regions_and_portals", []), false),
		"spawn_interaction_exit_sockets": _canonical_collection(data.get("spawn_interaction_exit_sockets", []), false),
		"gameplay_spatial_metadata": _canonicalize(data.get("gameplay_spatial_metadata", {})),
	}


static func _canonical_collection(value: Variant, stable_by_id: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_entry: Variant in _collection_entries(value):
		if raw_entry is Dictionary:
			var entry: Dictionary = _canonicalize(raw_entry)
			if stable_by_id and not entry.has("binding_id"):
				var identifier := _entry_id(raw_entry)
				if not identifier.is_empty():
					entry["binding_id"] = identifier
			result.append(entry)
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return _entry_less(left, right)
	)
	return result


static func _entry_less(left: Dictionary, right: Dictionary) -> bool:
	var left_id := _entry_id(left)
	var right_id := _entry_id(right)
	if left_id != right_id:
		return left_id < right_id
	return JSON.stringify(_canonicalize(left)) < JSON.stringify(_canonicalize(right))


static func _collection_entries(value: Variant) -> Array:
	if value is Array:
		return value as Array
	if value is Dictionary:
		var entries: Array = []
		var keys: Array[String] = []
		for key: Variant in (value as Dictionary).keys():
			keys.append(str(key))
		keys.sort()
		for key: String in keys:
			var raw: Variant = (value as Dictionary).get(key, {})
			if raw is Dictionary:
				var entry: Dictionary = raw.duplicate(true)
				if not entry.has("binding_id") and not entry.has("stable_id") and not entry.has("id"):
					entry["binding_id"] = key
				entries.append(entry)
		return entries
	return []


static func _entry_id(entry: Dictionary) -> String:
	for key: String in ["binding_id", "stable_id", "id", "socket_id", "profile_id", "region_id", "portal_id"]:
		if entry.has(key) and (entry[key] is String or entry[key] is StringName):
			var identifier := String(entry[key]).strip_edges()
			if not identifier.is_empty():
				return identifier
	return ""


static func _canonicalize(value: Variant) -> Variant:
	if value is Dictionary:
		var source: Dictionary = value
		var keys: Array[String] = []
		var original_keys: Dictionary = {}
		for raw_key: Variant in source.keys():
			var key := str(raw_key)
			if _VOLATILE_KEYS.has(key):
				continue
			keys.append(key)
			original_keys[key] = raw_key
		keys.sort()
		var result := {}
		for key: String in keys:
			result[key] = _canonicalize(source[original_keys[key]])
		return result
	if value is Array:
		var array_result: Array = []
		for item: Variant in value:
			array_result.append(_canonicalize(item))
		return array_result
	if value is PackedStringArray:
		var strings: Array[String] = []
		for item: String in value:
			strings.append(item)
		return strings
	return value


func _reset() -> void:
	coordinate_convention = {}
	stable_bindings = []
	traversal_profiles = []
	regions_and_portals = []
	spawn_interaction_exit_sockets = []
	gameplay_spatial_metadata = {}
