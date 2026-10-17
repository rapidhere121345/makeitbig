class_name StaticSpatialIndex
extends RefCounted

## Immutable per-channel index over authored world geometry.
##
## Built once from the WorldAsset spatial payload; there is no mutation API.
## Construction fails closed: unknown fields, duplicate or empty ids, unknown
## channels, non-convex polygons, non-finite numbers and invalid boundaries
## are load errors and produce no index.  Query inputs are the caller's first
## validation gate; resolvers validate before calling through.

const SCHEMA_VERSION: int = 1

const Shape := preload("res://src/runtime/geometry/spatial_shape.gd")
const Sweep := preload("res://src/runtime/geometry/spatial_sweep.gd")
const Channels := preload("res://src/runtime/spatial/spatial_channels.gd")
const Contact := preload("res://src/runtime/spatial/spatial_contact.gd")

const ASSET_FIELDS: Array[String] = ["schema_version", "asset_id", "surfaces", "movement_boundary"]
const SURFACE_FIELDS: Array[String] = ["id", "shape", "channels", "opaque", "vision_mode", "attenuation", "occlusion_rank"]
const VISION_MODES: Array[String] = ["opaque", "attenuate"]
const BOUNDARY_KINDS: Array[String] = ["rect", "ring", "corridor"]

var _asset_id := ""
var _surfaces: Array[Dictionary] = []
var _surfaces_by_id: Dictionary = {}
var _surfaces_by_channel: Dictionary = {}
var _movement_boundary: Dictionary = {}
var _errors: Array[String] = []
var _valid := false


static func build(asset: Variant) -> Dictionary:
	var index: StaticSpatialIndex = load("res://src/runtime/spatial/static_spatial_index.gd").new(asset)
	if not index.is_valid():
		return {"ok": false, "errors": index.validation_errors(), "value": null}
	return {"ok": true, "errors": [], "value": index}


func _init(asset: Variant = null) -> void:
	if asset == null:
		return
	_errors = _validate_asset(asset)
	if not _errors.is_empty():
		return
	var source: Dictionary = asset
	_asset_id = String(source["asset_id"])
	var boundary_value: Variant = source.get("movement_boundary", null)
	_movement_boundary = _normalize_boundary(boundary_value)["value"] if boundary_value != null else {}
	var surfaces: Array = source["surfaces"]
	for entry: Variant in surfaces:
		var surface: Dictionary = entry
		var normalized := _normalize_surface(surface)
		var stored: Dictionary = normalized["value"]
		_surfaces.append(stored)
		_surfaces_by_id[String(stored["id"])] = stored
		for channel: StringName in stored["channels"]:
			if not _surfaces_by_channel.has(channel):
				_surfaces_by_channel[channel] = []
			(_surfaces_by_channel[channel] as Array).append(stored)
	_surfaces.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left["id"]) < String(right["id"])
	)
	for channel: Variant in _surfaces_by_channel.keys():
		(_surfaces_by_channel[channel] as Array).sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			return String(left["id"]) < String(right["id"])
		)
	_valid = true


func is_valid() -> bool:
	return _valid


func validation_errors() -> Array[String]:
	return _errors.duplicate()


func asset_id() -> String:
	return _asset_id


func surface(surface_id: String) -> Dictionary:
	return (_surfaces_by_id.get(surface_id, {}) as Dictionary).duplicate(true)


func surface_ids(channel: StringName = &"") -> Array[String]:
	var ids: Array[String] = []
	if channel == StringName(&""):
		for surface: Dictionary in _surfaces:
			ids.append(String(surface["id"]))
		return ids
	if not Channels.is_valid(channel):
		return ids
	for surface: Dictionary in _surfaces_by_channel.get(channel, []):
		ids.append(String(surface["id"]))
	return ids


func movement_boundary() -> Dictionary:
	return _movement_boundary.duplicate(true)


## Continuous sweep of a circular body against one channel's surfaces.
func sweep(channel: StringName, start: Vector2, displacement: Vector2, radius: float) -> Array:
	var contacts: Array = []
	if not _valid or not Channels.is_valid(channel):
		return contacts
	if not (start.is_finite() and displacement.is_finite()) or not is_finite(radius) or radius < 0.0:
		return contacts
	for surface: Dictionary in _surfaces_by_channel.get(channel, []):
		var raw := _sweep_shape(surface["shape"], start, displacement, radius)
		if raw.is_empty():
			continue
		contacts.append(Contact.from_raw(raw, channel, Contact.KIND_STATIC_SURFACE, String(surface["id"]), 0))
	return Contact.sort_contacts(contacts)


## Overlapping (penetrating) contacts for a placed circular body.
func overlaps(channel: StringName, position: Vector2, radius: float) -> Array:
	var contacts: Array = []
	if not _valid or not Channels.is_valid(channel):
		return contacts
	if not position.is_finite() or not is_finite(radius) or radius < 0.0:
		return contacts
	for surface: Dictionary in _surfaces_by_channel.get(channel, []):
		var overlap := Shape.circle_shape_overlap(position, radius, surface["shape"])
		if not bool(overlap["overlaps"]):
			continue
		contacts.append(Contact.from_raw({
			"toi": 0.0,
			"point": overlap["point"],
			"normal": overlap["normal"],
			"feature": overlap["feature"],
			"penetrating": true,
			"initial": true,
		}, channel, Contact.KIND_STATIC_SURFACE, String(surface["id"]), 0))
	return Contact.sort_contacts(contacts)


## Fail-closed clearance: invalid input is never clear.
func is_position_clear(channel: StringName, position: Vector2, radius: float) -> bool:
	return overlaps(channel, position, radius).is_empty()


## Movement-domain boundary sweep.  Empty when the asset has no boundary.
func boundary_sweep(start: Vector2, displacement: Vector2, radius: float) -> Array:
	var contacts: Array = []
	if not _valid or _movement_boundary.is_empty():
		return contacts
	var raw_hits := Sweep.sweep_boundary(start, displacement, radius, _movement_boundary)
	for raw: Dictionary in raw_hits:
		contacts.append(Contact.from_raw(raw, Channels.MOVEMENT, Contact.KIND_BOUNDARY, "boundary", 0))
	return Contact.sort_contacts(contacts)


func snapshot() -> Dictionary:
	var surfaces: Array[Dictionary] = []
	for surface: Dictionary in _surfaces:
		surfaces.append(_surface_snapshot(surface))
	return {
		"schema_version": SCHEMA_VERSION,
		"asset_id": _asset_id,
		"immutable": true,
		"contract": Shape.coordinate_contract(),
		"surface_count": surfaces.size(),
		"surfaces": surfaces,
		"movement_boundary": _boundary_snapshot(_movement_boundary),
	}


func _surface_snapshot(surface: Dictionary) -> Dictionary:
	return {
		"id": String(surface["id"]),
		"shape": _shape_snapshot(surface["shape"]),
		"channels": surface["channels"].duplicate(),
		"opaque": bool(surface["opaque"]),
		"vision_mode": String(surface["vision_mode"]),
		"attenuation": float(surface["attenuation"]),
		"occlusion_rank": int(surface["occlusion_rank"]),
	}


static func _shape_snapshot(shape: Dictionary) -> Dictionary:
	match String(shape["kind"]):
		"rect":
			var rect: Rect2 = shape["rect"]
			return {
				"kind": "rect",
				"rect": {"position": [rect.position.x, rect.position.y], "size": [rect.size.x, rect.size.y]},
			}
		"circle":
			var center: Vector2 = shape["center"]
			return {"kind": "circle", "center": [center.x, center.y], "radius": float(shape["radius"])}
		"polygon":
			var points: Array = []
			for point: Vector2 in shape["points"]:
				points.append([point.x, point.y])
			return {"kind": "polygon", "points": points}
	return {"kind": "invalid"}


static func _boundary_snapshot(boundary: Dictionary) -> Dictionary:
	if boundary.is_empty():
		return {}
	match String(boundary["kind"]):
		"rect":
			var rect: Rect2 = boundary["rect"]
			return {
				"kind": "rect",
				"rect": {"position": [rect.position.x, rect.position.y], "size": [rect.size.x, rect.size.y]},
			}
		"ring":
			var center: Vector2 = boundary["center"]
			return {
				"kind": "ring",
				"center": [center.x, center.y],
				"inner_radius": float(boundary["inner_radius"]),
				"outer_radius": float(boundary["outer_radius"]),
			}
		"corridor":
			var rect: Rect2 = boundary["rect"]
			return {
				"kind": "corridor",
				"rect": {"position": [rect.position.x, rect.position.y], "size": [rect.size.x, rect.size.y]},
				"half_height": float(boundary["half_height"]),
			}
	return {}


static func _sweep_shape(shape: Dictionary, start: Vector2, displacement: Vector2, radius: float) -> Dictionary:
	var result := {}
	match String(shape["kind"]):
		"circle":
			var hits := Sweep.sweep_circle_circle(start, displacement, radius, shape["center"], float(shape["radius"]), "circle", false)
			if not hits.is_empty():
				result = hits
		"rect", "polygon":
			var hits := Sweep.sweep_circle_polygon(start, displacement, radius, shape["points"])
			if not hits.is_empty():
				result = hits[0]
	return result


func _validate_asset(asset: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not asset is Dictionary:
		return ["asset:invalid_type"]
	var source: Dictionary = asset
	for field: String in ASSET_FIELDS:
		if not source.has(field) and field != "movement_boundary":
			errors.append("asset:missing_field:%s" % field)
	for key: Variant in source.keys():
		var key_text := str(key)
		if not ASSET_FIELDS.has(key_text):
			errors.append("asset:unknown_field:%s" % key_text)
	if source.get("schema_version", 0) is int and int(source["schema_version"]) == SCHEMA_VERSION:
		pass
	else:
		errors.append("asset:invalid_schema_version")
	var asset_id := String(source.get("asset_id", ""))
	if asset_id.strip_edges().is_empty():
		errors.append("asset:invalid_asset_id")
	if not source.get("surfaces", null) is Array:
		errors.append("asset.surfaces:invalid_type")
		return errors
	var seen_ids: Dictionary = {}
	var surfaces: Array = source["surfaces"]
	for index: int in surfaces.size():
		var entry: Variant = surfaces[index]
		if not entry is Dictionary:
			errors.append("asset.surfaces[%d]:invalid_type" % index)
			continue
		var surface: Dictionary = entry
		var prefix := "asset.surfaces[%d]" % index
		for key: Variant in surface.keys():
			var surface_key := str(key)
			if not SURFACE_FIELDS.has(surface_key):
				errors.append("%s.unknown_field:%s" % [prefix, surface_key])
		var surface_id := String(surface.get("id", ""))
		if surface_id.strip_edges().is_empty():
			errors.append("%s.id:invalid" % prefix)
		elif seen_ids.has(surface_id):
			errors.append("%s.id:duplicate:%s" % [prefix, surface_id])
		else:
			seen_ids[surface_id] = true
		var shape_result := Shape.normalize(surface.get("shape", null))
		if not bool(shape_result["ok"]):
			for error: String in shape_result["errors"]:
				errors.append("%s.%s" % [prefix, error])
		errors.append_array(_surface_flag_errors(surface, prefix))
	if source.has("movement_boundary") and source["movement_boundary"] != null:
		var boundary_result := _normalize_boundary(source["movement_boundary"])
		if not bool(boundary_result["ok"]):
			for error: String in boundary_result["errors"]:
				errors.append("asset.movement_boundary.%s" % error)
	return errors


static func _surface_flag_errors(surface: Dictionary, prefix: String) -> Array[String]:
	var errors: Array[String] = []
	errors.append_array(Channels.validate_list(surface.get("channels", null), "%s.channels" % prefix))
	var opaque_value: Variant = surface.get("opaque", true)
	if not opaque_value is bool:
		errors.append("%s.opaque:invalid_type" % prefix)
	var vision_mode := String(surface.get("vision_mode", "opaque"))
	if not VISION_MODES.has(vision_mode):
		errors.append("%s.vision_mode:unknown:%s" % [prefix, vision_mode])
	var attenuation_value: Variant = surface.get("attenuation", 0.0)
	if attenuation_value is float or attenuation_value is int:
		var attenuation := float(attenuation_value)
		if not is_finite(attenuation) or attenuation < 0.0 or attenuation > 1.0:
			errors.append("%s.attenuation:out_of_range" % prefix)
	else:
		errors.append("%s.attenuation:invalid_type" % prefix)
	var rank_value: Variant = surface.get("occlusion_rank", 0)
	if not rank_value is int:
		errors.append("%s.occlusion_rank:invalid_type" % prefix)
	return errors


static func _normalize_surface(surface: Dictionary) -> Dictionary:
	var shape_result := Shape.normalize(surface["shape"])
	var shape: Dictionary = shape_result["value"]
	var channels: Array[StringName] = Channels.sorted_copy(surface["channels"])
	return {
		"ok": true,
		"errors": [],
		"value": {
			"id": String(surface["id"]),
			"shape": shape,
			"shape_key": Shape.shape_key(shape),
			"channels": channels,
			"opaque": bool(surface.get("opaque", true)),
			"vision_mode": StringName(String(surface.get("vision_mode", "opaque"))),
			"attenuation": float(surface.get("attenuation", 0.0)),
			"occlusion_rank": int(surface.get("occlusion_rank", 0)),
		},
	}


static func _normalize_boundary(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {"ok": false, "errors": ["invalid_type"], "value": {}}
	var source: Dictionary = value
	var kind := String(source.get("kind", ""))
	if not BOUNDARY_KINDS.has(kind):
		return {"ok": false, "errors": ["unknown_kind:%s" % kind], "value": {}}
	match kind:
		"rect":
			if not source.get("rect", null) is Rect2:
				return {"ok": false, "errors": ["rect:invalid_type"], "value": {}}
			var rect: Rect2 = source["rect"]
			if not (rect.position.is_finite() and rect.size.is_finite()) or rect.size.x <= 0.0 or rect.size.y <= 0.0:
				return {"ok": false, "errors": ["rect:invalid"], "value": {}}
			return {"ok": true, "errors": [], "value": {"kind": "rect", "rect": rect}}
		"ring":
			if not source.get("center", null) is Vector2 or not (source["center"] as Vector2).is_finite():
				return {"ok": false, "errors": ["center:invalid"], "value": {}}
			var center: Vector2 = source["center"]
			if not (source.get("inner_radius", null) is float or source.get("inner_radius", null) is int) or not (source.get("outer_radius", null) is float or source.get("outer_radius", null) is int):
				return {"ok": false, "errors": ["radius:invalid"], "value": {}}
			var inner := float(source["inner_radius"])
			var outer := float(source["outer_radius"])
			if not (is_finite(inner) and is_finite(outer)) or inner < 0.0 or outer <= inner:
				return {"ok": false, "errors": ["ring:invalid_radii"], "value": {}}
			return {"ok": true, "errors": [], "value": {"kind": "ring", "center": center, "inner_radius": inner, "outer_radius": outer}}
		"corridor":
			if not source.get("rect", null) is Rect2:
				return {"ok": false, "errors": ["rect:invalid_type"], "value": {}}
			var corridor_rect: Rect2 = source["rect"]
			if not (corridor_rect.position.is_finite() and corridor_rect.size.is_finite()) or corridor_rect.size.x <= 0.0 or corridor_rect.size.y <= 0.0:
				return {"ok": false, "errors": ["rect:invalid"], "value": {}}
			if not (source.get("half_height", null) is float or source.get("half_height", null) is int):
				return {"ok": false, "errors": ["half_height:invalid_type"], "value": {}}
			var half_height := float(source["half_height"])
			if not is_finite(half_height) or half_height <= 0.0 or half_height > corridor_rect.size.y * 0.5:
				return {"ok": false, "errors": ["half_height:invalid"], "value": {}}
			return {"ok": true, "errors": [], "value": {"kind": "corridor", "rect": corridor_rect, "half_height": half_height}}
	return {"ok": false, "errors": ["unknown_kind:%s" % kind], "value": {}}
