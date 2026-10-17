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
## The manifest vocabulary is explicitly closed: any channel name outside
## this list fails validation.  movement/navigation/vision/projectile/
## attack/hurtbox are gameplay truth; occlusion is presentation-only and
## can never be consumed as movement/vision/projectile truth.
const CHANNELS: Array[String] = ["movement", "navigation", "vision", "projectile", "attack", "hurtbox", "occlusion"]
const GAMEPLAY_CHANNELS: Array[String] = ["movement", "navigation", "vision", "projectile", "attack", "hurtbox"]
const PRESENTATION_CHANNELS: Array[String] = ["occlusion"]
## Solid channels describe collision truth and therefore always require a
## normalized collision shape on their binding.  navigation is derived
## data and may legally omit geometry.
const SOLID_CHANNELS: Array[String] = ["movement", "vision", "projectile", "attack", "hurtbox"]
const BINDING_FIELDS: Array[String] = [
	"binding_id", "stable_id", "id", "channels", "kind", "source",
	"geometry", "feet_anchor", "art_box", "overlay_id",
]
const FEET_ANCHOR_MODES: Array[String] = ["art_bottom_center"]
## The authored convention every bake must carry exactly.
const AUTHORING_COORDINATE_CONVENTION: Dictionary = {"units": "design_pixel", "up": "negative_y", "scale": 1.0}
## Runtime overlay contract for gates/destructibles.  Overlay entries are
## applied as a detached view; they never mutate an authored manifest.
const OVERLAY_SOURCE := "world.overlay.v1"
const OVERLAY_KINDS: Array[String] = ["gate", "destructible"]
const OVERLAY_FIELDS: Array[String] = ["overlay_id", "kind", "channels", "geometry"]
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
			_validate_entry_fields(entry, index, errors)
			_validate_art_anchor(entry, index, errors)
		var solid_channel := ""
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
				elif bool((entry["channels"] as Dictionary)[channel_key]) and SOLID_CHANNELS.has(channel) and solid_channel.is_empty():
					solid_channel = channel
			if not solid_channel.is_empty():
				_validate_solid_geometry(entry, solid_channel, field, index, errors)


static func _validate_entry_fields(entry: Dictionary, index: int, errors: Array[String]) -> void:
	for key: Variant in entry.keys():
		var field_name := str(key)
		if not BINDING_FIELDS.has(field_name):
			errors.append("unknown_binding_field:%s[%d]" % [field_name, index])


static func _validate_art_anchor(entry: Dictionary, index: int, errors: Array[String]) -> void:
	var has_art := entry.has("art_box")
	var anchor_value: Variant = entry.get("feet_anchor", null)
	if has_art and not anchor_value is Dictionary:
		errors.append("missing_feet_anchor:stable_bindings[%d]" % index)
		return
	if not has_art:
		if anchor_value != null:
			errors.append("orphan_feet_anchor:stable_bindings[%d]" % index)
		return
	var anchor: Dictionary = anchor_value
	var anchor_keys: Array[String] = []
	for key: Variant in anchor.keys():
		anchor_keys.append(str(key))
	anchor_keys.sort()
	if anchor_keys.size() != 1 or anchor_keys[0] != "mode":
		errors.append("invalid_feet_anchor:stable_bindings[%d]" % index)
		return
	var mode := String(anchor.get("mode", ""))
	if not FEET_ANCHOR_MODES.has(mode):
		errors.append("invalid_feet_anchor:%s" % mode)
		return
	var box := _rect_from(entry["art_box"])
	if not _valid_rect(box):
		errors.append("invalid_art_box:stable_bindings[%d]" % index)
		return
	if mode == "art_bottom_center":
		var anchor_offset := Vector2(box.position.x + box.size.x * 0.5, box.position.y + box.size.y)
		if not is_zero_approx(anchor_offset.x) or not is_zero_approx(anchor_offset.y):
			errors.append("art_box_anchor_mismatch:stable_bindings[%d]" % index)


static func _validate_solid_geometry(entry: Dictionary, channel: String, field: String, index: int, errors: Array[String]) -> void:
	if not entry.has("geometry"):
		if channel == "movement":
			errors.append("missing_movement_geometry:%s[%d]" % [field, index])
		else:
			errors.append("missing_solid_geometry:%s:%s[%d]" % [channel, field, index])
		return
	if entry.get("kind", "") == "static_blocker":
		var solid := ArenaGeometryScript.normalize_native_static_geometry(entry["geometry"])
		if not bool(solid.get("ok", false)):
			errors.append("invalid_static_geometry:%s[%d]" % [field, index])
		return
	if _normalize_movement_geometry(entry.get("geometry", null)).is_empty():
		if channel == "movement":
			errors.append("invalid_movement_geometry:%s[%d]" % [field, index])
		else:
			errors.append("invalid_solid_geometry:%s:%s[%d]" % [channel, field, index])


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
	for key: String in ["binding_id", "stable_id", "id", "socket_id", "profile_id", "region_id", "portal_id", "overlay_id"]:
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


## ------------------------------------------------------------------
## Authoring contract (offline bake gate).  Stricter than the runtime
## data contract above: an authored manifest must carry the canonical
## coordinate convention, fully positioned sockets, real traversal
## radii and unique collection identifiers.  The baker fails closed on
## any error here.

static func validate_authoring_data(value: Variant) -> Array[String]:
	var errors := validate_data(value)
	if not value is Dictionary:
		return errors
	var data: Dictionary = value
	_validate_authoring_convention(data.get("coordinate_convention", {}), errors)
	_validate_authoring_traversal(data.get("traversal_profiles", []), errors)
	_validate_authoring_regions(data.get("regions_and_portals", []), errors)
	_validate_authoring_sockets(data.get("spawn_interaction_exit_sockets", []), errors)
	return errors


static func _validate_authoring_convention(value: Variant, errors: Array[String]) -> void:
	if not value is Dictionary:
		errors.append("invalid_coordinate_convention")
		return
	var convention: Dictionary = value
	for key: String in AUTHORING_COORDINATE_CONVENTION.keys():
		if not convention.has(key):
			errors.append("missing_coordinate_field:%s" % key)
	for key: Variant in convention.keys():
		var field := str(key)
		if not AUTHORING_COORDINATE_CONVENTION.has(field):
			errors.append("unknown_coordinate_field:%s" % field)
			continue
		var expected: Variant = AUTHORING_COORDINATE_CONVENTION[field]
		var actual: Variant = convention[key]
		if expected is String:
			if not actual is String or String(actual) != String(expected):
				errors.append("invalid_coordinate_convention:%s" % field)
		elif not (actual is int or actual is float) or not is_equal_approx(float(actual), float(expected)):
			errors.append("invalid_coordinate_convention:%s" % field)


static func _validate_authoring_traversal(value: Variant, errors: Array[String]) -> void:
	var entries: Array = _collection_entries(value)
	var seen: Dictionary = {}
	for index in entries.size():
		if not entries[index] is Dictionary:
			errors.append("invalid_entry:traversal_profiles[%d]" % index)
			continue
		var profile: Dictionary = entries[index]
		var identifier := _entry_id(profile)
		if identifier.is_empty():
			errors.append("missing_profile_id:traversal_profiles[%d]" % index)
		elif seen.has(identifier):
			errors.append("duplicate_profile_id:%s" % identifier)
		else:
			seen[identifier] = true
		var radius_value: Variant = profile.get("radius", null)
		if not _valid_number(radius_value) or float(radius_value) <= 0.0:
			errors.append("invalid_traversal_radius:traversal_profiles[%d]" % index)


static func _validate_authoring_regions(value: Variant, errors: Array[String]) -> void:
	var entries: Array = _collection_entries(value)
	var seen: Dictionary = {}
	for index in entries.size():
		if not entries[index] is Dictionary:
			errors.append("invalid_entry:regions_and_portals[%d]" % index)
			continue
		var region: Dictionary = entries[index]
		var identifier := _entry_id(region)
		if identifier.is_empty():
			errors.append("missing_region_id:regions_and_portals[%d]" % index)
		elif seen.has(identifier):
			errors.append("duplicate_region_id:%s" % identifier)
		else:
			seen[identifier] = true


static func _validate_authoring_sockets(value: Variant, errors: Array[String]) -> void:
	var entries: Array = _collection_entries(value)
	for index in entries.size():
		if not entries[index] is Dictionary:
			errors.append("invalid_entry:spawn_interaction_exit_sockets[%d]" % index)
			continue
		var socket: Dictionary = entries[index]
		var position_value: Variant = socket.get("position", null)
		if position_value is Array:
			var coordinates: Array = position_value
			if coordinates.size() != 2 or not coordinates.all(func(item: Variant) -> bool: return _valid_number(item)):
				errors.append("invalid_socket_position:spawn_interaction_exit_sockets[%d]" % index)
		else:
			errors.append("missing_socket_position:spawn_interaction_exit_sockets[%d]" % index)


## ------------------------------------------------------------------
## Digest separation.  Gameplay and presentation digests are computed
## from detached halves of the canonical manifest.  Bindings carrying
## any gameplay channel feed the gameplay digest; bindings carrying
## occlusion feed the presentation digest.  A mixed binding lands in
## both halves on purpose: changing it changes both truths, while a
## pure-presentation piece can never move the gameplay digest.

static func gameplay_digest_input(value: Variant) -> Dictionary:
	var payload := _canonical_payload(value if value is Dictionary else {})
	return {
		"coordinate_convention": payload["coordinate_convention"],
		"stable_bindings": _digest_bindings(payload["stable_bindings"], true),
		"traversal_profiles": payload["traversal_profiles"],
		"regions_and_portals": payload["regions_and_portals"],
		"spawn_interaction_exit_sockets": payload["spawn_interaction_exit_sockets"],
		"gameplay_spatial_metadata": payload["gameplay_spatial_metadata"],
	}


static func presentation_digest_input(value: Variant) -> Dictionary:
	var payload := _canonical_payload(value if value is Dictionary else {})
	return {
		"coordinate_convention": payload["coordinate_convention"],
		"stable_bindings": _digest_bindings(payload["stable_bindings"], false),
	}


static func _digest_bindings(bindings_value: Variant, gameplay: bool) -> Array:
	var result: Array = []
	for binding: Variant in bindings_value:
		if not binding is Dictionary:
			continue
		var channels: Dictionary = (binding as Dictionary).get("channels", {})
		if gameplay:
			for channel: String in GAMEPLAY_CHANNELS:
				if bool(channels.get(channel, false)):
					result.append(binding)
					break
		elif bool(channels.get("occlusion", false)):
			result.append(binding)
	return result


func gameplay_digest_sha256() -> String:
	return digest_payload_sha256(gameplay_digest_input(snapshot()))


func presentation_digest_sha256() -> String:
	return digest_payload_sha256(presentation_digest_input(snapshot()))


static func digest_payload_sha256(value: Variant) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(JSON.stringify(_canonicalize(value)).to_utf8_buffer()) != OK:
		return ""
	return context.finish().hex_encode()


## ------------------------------------------------------------------
## Runtime overlay contract.  Runtime gates and destructibles are open
## truth that arrives after the bake: they are applied through this
## detached overlay, which returns a NEW manifest view.  The authored
## manifest is never mutated and overlay data never enters a bake.

static func overlay_validate(entries_value: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not entries_value is Array:
		errors.append("invalid_type:world_overlay")
		return errors
	var seen: Dictionary = {}
	for index in (entries_value as Array).size():
		var raw: Variant = (entries_value as Array)[index]
		if not raw is Dictionary:
			errors.append("invalid_entry:world_overlay[%d]" % index)
			continue
		var entry: Dictionary = raw
		for key: Variant in entry.keys():
			if not OVERLAY_FIELDS.has(str(key)):
				errors.append("unknown_overlay_field:%s[%d]" % [str(key), index])
		for field: String in OVERLAY_FIELDS:
			if not entry.has(field):
				errors.append("missing_overlay_field:%s[%d]" % [field, index])
		var identifier := _entry_id(entry)
		if identifier.is_empty():
			errors.append("missing_overlay_id:world_overlay[%d]" % index)
		elif seen.has(identifier):
			errors.append("duplicate_overlay_id:%s" % identifier)
		else:
			seen[identifier] = true
		var kind := String(entry.get("kind", ""))
		if not OVERLAY_KINDS.has(kind):
			errors.append("invalid_overlay_kind:%s[%d]" % [kind if not kind.is_empty() else "missing", index])
		var channels_value: Variant = entry.get("channels", null)
		if not channels_value is Dictionary:
			errors.append("invalid_channels:world_overlay[%d]" % index)
		else:
			var has_solid := false
			for channel_key: Variant in (channels_value as Dictionary).keys():
				var channel := str(channel_key)
				if not CHANNELS.has(channel):
					errors.append("unknown_channel:%s" % channel)
				elif not (channels_value as Dictionary)[channel_key] is bool:
					errors.append("invalid_channel_value:%s" % channel)
				elif bool((channels_value as Dictionary)[channel_key]) and SOLID_CHANNELS.has(channel):
					has_solid = true
			if not has_solid:
				errors.append("overlay_without_solid_channel:world_overlay[%d]" % index)
		if entry.has("geometry") and _normalize_movement_geometry(entry["geometry"]).is_empty():
			errors.append("invalid_overlay_geometry:world_overlay[%d]" % index)
	return errors


static func overlay_normalize(entries_value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not entries_value is Array:
		return result
	for raw: Variant in entries_value:
		if not raw is Dictionary:
			continue
		var entry: Dictionary = _canonicalize(raw)
		if entry.has("geometry"):
			entry["geometry"] = _overlay_geometry_payload(entry["geometry"])
		result.append(entry)
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.get("overlay_id", "")) < String(right.get("overlay_id", ""))
	)
	return result


## Applies an overlay to a manifest payload or instance and returns a
## detached NEW manifest payload.  The input is never mutated.
static func overlay_apply(manifest_value: Variant, overlay_entries: Variant) -> Dictionary:
	var errors := overlay_validate(overlay_entries)
	if manifest_value is Dictionary:
		errors.append_array(validate_data(manifest_value))
	else:
		errors.append("invalid_type:spatial_manifest")
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "value": {}}
	var merged := _canonical_payload(manifest_value)
	var overlay_bindings: Array = []
	for raw: Variant in overlay_normalize(overlay_entries):
		var entry: Dictionary = raw
		var overlay_id := String(entry.get("overlay_id", ""))
		overlay_bindings.append({
			"binding_id": overlay_id,
			"overlay_id": overlay_id,
			"kind": String(entry.get("kind", "")),
			"source": OVERLAY_SOURCE,
			"channels": (entry.get("channels", {}) as Dictionary).duplicate(true),
			"geometry": (entry.get("geometry", {}) as Dictionary).duplicate(true),
		})
	var combined: Array = []
	for binding: Variant in merged["stable_bindings"]:
		combined.append(binding)
	combined.append_array(overlay_bindings)
	merged["stable_bindings"] = _canonical_collection(combined, true)
	return {"ok": true, "errors": [], "value": merged}


func with_overlay(overlay_entries: Variant) -> Dictionary:
	var applied := overlay_apply(snapshot(), overlay_entries)
	if not bool(applied.get("ok", false)):
		return applied
	return {"ok": true, "errors": [], "value": load("res://src/runtime/world/spatial_manifest.gd").new(applied["value"])}


static func _overlay_geometry_payload(value: Variant) -> Dictionary:
	var normalized := _normalize_movement_geometry(value)
	if normalized.is_empty():
		return {}
	var payload: Dictionary = {"type": normalized["type"]}
	if normalized.has("rect"):
		var rect: Rect2 = normalized["rect"]
		payload["rect"] = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	if normalized.has("axis"):
		payload["axis"] = normalized["axis"]
	if normalized.has("half_height"):
		payload["half_height"] = normalized["half_height"]
	if normalized.has("center"):
		var center: Vector2 = normalized["center"]
		payload["center"] = [center.x, center.y]
	if normalized.has("inner_radius"):
		payload["inner_radius"] = normalized["inner_radius"]
	if normalized.has("outer_radius"):
		payload["outer_radius"] = normalized["outer_radius"]
	return payload
