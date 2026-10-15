class_name ArenaGeometry
extends RefCounted

## One pure geometry contract for combat-room planning and authored movement
## boundaries. It has no Nodes, rendering state, or actor state. The static
## layout form is the canonical snapshot consumed by planning and replay; the
## instance form validates native boundary/blocker definitions used by room
## assembly and content tests.

const SCHEMA_VERSION: int = 1
const EPSILON: float = 0.000001
const CONTACT_EPSILON: float = 0.0000001
const NATIVE_CONTACT_EPSILON: float = 0.0001
const _FIELDS: Array[String] = [
	"schema_version", "kind", "bounds", "center", "corridor_half_height",
	"inner_radius", "outer_radius",
]
const _KINDS: Array[String] = ["rectangle", "corridor", "ring"]
const _SWALLOWED_DISPLACEMENT: float = 0.01
const _MIN_PROGRESS_FRACTION: float = 0.05
const _RING_DIRECTION_EPSILON: float = 0.001

var _boundary: Dictionary = {}
var _blockers: Array[Dictionary] = []


func _init(definition: Dictionary = {}) -> void:
	var normalized := normalize_definition(definition)
	if bool(normalized.get("ok", false)):
		_boundary = normalized["value"]["boundary"]
		_blockers = normalized["value"]["blockers"]


## Builds the stable canonical layout snapshot used by the combat planner.
## Padding is an authored footprint inset for the planning profile; the actual
## actor sweep still uses ActorMotor with its own footprint radius.
static func from_layout(layout_id: String, arena_rect: Rect2, padding: float) -> Dictionary:
	if not _valid_rect(arena_rect) or not _valid_number(padding) or padding < 0.0:
		return {}
	var bounds := arena_rect.grow(-padding)
	if not _valid_rect(bounds):
		return {}
	var kind := "rectangle" if layout_id in ["rectangle", "rectangle_arena"] else layout_id
	if kind not in _KINDS:
		return {}
	var corridor_half_height := 0.0
	var inner_radius := 0.0
	var outer_radius := 0.0
	if kind == "corridor":
		corridor_half_height = minf(72.0, bounds.size.y * 0.25)
	elif kind == "ring":
		var radius_basis := minf(bounds.size.x, bounds.size.y)
		inner_radius = radius_basis * 0.20
		outer_radius = radius_basis * 0.43
	return {
		"schema_version": SCHEMA_VERSION,
		"kind": kind,
		"bounds": bounds,
		"center": bounds.get_center(),
		"corridor_half_height": corridor_half_height,
		"inner_radius": inner_radius,
		"outer_radius": outer_radius,
	}


## Converts scene-authored geometry to the planner/presenter snapshot. Keep the
## v03 planning inset convention; ActorMotor applies the physical footprint to
## the unpadded native boundary independently.
static func from_native_boundary(boundary: Dictionary, arena_rect: Rect2, padding: float) -> Dictionary:
	if not _valid_rect(arena_rect) or not _valid_number(padding) or padding < 0.0:
		return {}
	var normalized := normalize_native_boundary(boundary)
	if not bool(normalized.get("ok", false)):
		return {}
	var native: Dictionary = normalized["value"]
	var bounds := arena_rect.grow(-padding)
	if not _valid_rect(bounds):
		return {}
	var kind := String(native["type"])
	var half_height := 0.0
	var inner := 0.0
	var outer := 0.0
	if kind in ["rect", "corridor"]:
		if not (native["rect"] as Rect2).is_equal_approx(arena_rect):
			return {}
		if kind == "corridor":
			half_height = minf(float(native["half_height"]), bounds.size.y * 0.25)
	elif kind == "ring":
		if not (native["center"] as Vector2).is_equal_approx(arena_rect.get_center()):
			return {}
		var basis := minf(arena_rect.size.x, arena_rect.size.y)
		if float(native["outer_radius"]) > basis * 0.5:
			return {}
		var inset_scale := minf(bounds.size.x, bounds.size.y) / basis
		inner = float(native["inner_radius"]) * inset_scale
		outer = float(native["outer_radius"]) * inset_scale
	var candidate := {
		"schema_version": SCHEMA_VERSION,
		"kind": "rectangle" if kind == "rect" else kind,
		"bounds": bounds,
		"center": bounds.get_center(),
		"corridor_half_height": half_height,
		"inner_radius": inner,
		"outer_radius": outer,
	}
	var result := normalize(candidate)
	return result["value"] if bool(result.get("ok", false)) else {}


## Converts a native boundary into the actual center-space available to one
## circular actor.  This is intentionally separate from from_native_boundary():
## the latter preserves the v03 planning inset used by replay/public snapshots,
## while this contract mirrors ActorMotor's footprint clearance exactly.
static func from_native_boundary_for_footprint(boundary: Dictionary, arena_rect: Rect2, radius: float) -> Dictionary:
	if not _valid_rect(arena_rect) or not _valid_number(radius) or radius < 0.0:
		return {}
	var normalized := normalize_native_boundary(boundary)
	if not bool(normalized.get("ok", false)):
		return {}
	var native: Dictionary = normalized["value"]
	var native_kind := String(native["type"])
	var bounds := arena_rect.grow(-radius)
	if not _valid_rect(bounds):
		return {}
	var half_height := 0.0
	var inner := 0.0
	var outer := 0.0
	if native_kind in ["rect", "corridor"]:
		if not (native["rect"] as Rect2).is_equal_approx(arena_rect):
			return {}
		if native_kind == "corridor":
			half_height = float(native["half_height"]) - radius
			if half_height <= 0.0:
				return {}
	else:
		if not (native["center"] as Vector2).is_equal_approx(arena_rect.get_center()):
			return {}
		var basis := minf(arena_rect.size.x, arena_rect.size.y)
		if float(native["outer_radius"]) > basis * 0.5:
			return {}
		inner = float(native["inner_radius"]) + radius
		outer = float(native["outer_radius"]) - radius
		if outer <= inner:
			return {}
	var candidate := {
		"schema_version": SCHEMA_VERSION,
		"kind": "rectangle" if native_kind == "rect" else native_kind,
		"bounds": bounds,
		"center": bounds.get_center(),
		"corridor_half_height": half_height,
		"inner_radius": inner,
		"outer_radius": outer,
	}
	var result := normalize(candidate)
	return result["value"] if bool(result.get("ok", false)) else {}


static func normalize(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _normalize_failure("invalid_geometry")
	var geometry: Dictionary = value
	if geometry.size() != _FIELDS.size():
		return _normalize_failure("invalid_fields")
	for field: String in _FIELDS:
		if not geometry.has(field):
			return _normalize_failure("invalid_fields")
	if not _valid_schema_version(geometry["schema_version"]):
		return _normalize_failure("invalid_schema_version")
	if not (geometry["kind"] is String or geometry["kind"] is StringName):
		return _normalize_failure("invalid_kind")
	var kind := String(geometry["kind"])
	if kind not in _KINDS:
		return _normalize_failure("invalid_kind")
	if not _valid_rect(geometry["bounds"]):
		return _normalize_failure("invalid_bounds")
	if not _valid_vector(geometry["center"]):
		return _normalize_failure("invalid_center")
	for field: String in ["corridor_half_height", "inner_radius", "outer_radius"]:
		if not _valid_number(geometry[field]):
			return _normalize_failure("invalid_%s" % field)

	var bounds: Rect2 = geometry["bounds"]
	var center: Vector2 = geometry["center"]
	if not center.is_equal_approx(bounds.get_center()):
		return _normalize_failure("invalid_center")
	var corridor_half_height := float(geometry["corridor_half_height"])
	var inner_radius := float(geometry["inner_radius"])
	var outer_radius := float(geometry["outer_radius"])
	match kind:
		"rectangle":
			if not is_zero_approx(corridor_half_height) or not is_zero_approx(inner_radius) or not is_zero_approx(outer_radius):
				return _normalize_failure("invalid_rectangle_parameters")
		"corridor":
			if corridor_half_height <= 0.0 or corridor_half_height > bounds.size.y * 0.5:
				return _normalize_failure("invalid_corridor_parameters")
			if not is_zero_approx(inner_radius) or not is_zero_approx(outer_radius):
				return _normalize_failure("invalid_corridor_parameters")
		"ring":
			var radius_basis := minf(bounds.size.x, bounds.size.y)
			if inner_radius <= 0.0 or outer_radius <= inner_radius or outer_radius > radius_basis * 0.5:
				return _normalize_failure("invalid_ring_parameters")
			if not is_zero_approx(corridor_half_height):
				return _normalize_failure("invalid_ring_parameters")

	return {
		"ok": true,
		"error": "",
		"value": {
			"schema_version": SCHEMA_VERSION,
			"kind": kind,
			"bounds": bounds,
			"center": center,
			"corridor_half_height": corridor_half_height,
			"inner_radius": inner_radius,
			"outer_radius": outer_radius,
		},
	}


## Native room definitions use a boundary object plus explicit convex blockers.
## Unknown fields are rejected so a typo can never silently create an open room.
static func build(definition: Dictionary) -> Dictionary:
	return normalize_definition(definition)


static func normalize_definition(definition: Variant) -> Dictionary:
	if not definition is Dictionary:
		return _definition_failure("definition_not_dictionary")
	var source: Dictionary = definition
	if not _has_only_fields(source, ["boundary", "blockers"]):
		return _definition_failure("invalid_fields")
	var boundary_value: Variant = source.get("boundary", null)
	if not boundary_value is Dictionary:
		return _definition_failure("missing_boundary")
	var boundary := _normalize_boundary(boundary_value)
	if boundary.is_empty():
		return _definition_failure("invalid_boundary")
	var blockers: Array[Dictionary] = []
	var raw_blockers: Variant = source.get("blockers", [])
	if not raw_blockers is Array:
		return _definition_failure("invalid_blockers")
	for raw: Variant in raw_blockers:
		var blocker := _normalize_blocker(raw)
		if blocker.is_empty():
			return _definition_failure("invalid_blocker")
		blockers.append(blocker)
	blockers.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left["id"]) < String(right["id"])
	)
	return {"ok": true, "error": "", "value": {"boundary": boundary, "blockers": blockers}}


func is_position_clear(position: Vector2) -> bool:
	if not position.is_finite() or not boundary_contains(position):
		return false
	for blocker: Dictionary in _blockers:
		if _point_in_convex_polygon(position, blocker["points"]):
			return false
	return true


func boundary_contains(position: Vector2) -> bool:
	return _boundary_contains(position, _boundary)


func boundary_snapshot() -> Dictionary:
	return _boundary.duplicate(true)


func blocker_snapshot() -> Array[Dictionary]:
	return _blockers.duplicate(true)


func snapshot() -> Dictionary:
	return {"boundary": boundary_snapshot(), "blockers": blocker_snapshot()}


## Static boundary/blocker export used when a room assembles ActorMotor. The
## outer Rect2 is passed separately to the motor; these shapes represent only
## the extra walls for a corridor or annulus and therefore preserve holes.
static func movement_blockers(layout_id: String, arena_rect: Rect2) -> Array[Dictionary]:
	if not _valid_rect(arena_rect):
		return []
	var result: Array[Dictionary] = []
	var center := arena_rect.get_center()
	if layout_id == "corridor":
		var half_height := minf(72.0, arena_rect.size.y * 0.25)
		var upper_end := center.y - half_height
		var lower_start := center.y + half_height
		var top_height := maxf(0.0, upper_end - arena_rect.position.y)
		var bottom_height := maxf(0.0, arena_rect.end.y - lower_start)
		if top_height > EPSILON:
			result.append({"id": "arena/corridor/top", "kind": "rect", "rect": Rect2(arena_rect.position, Vector2(arena_rect.size.x, top_height))})
		if bottom_height > EPSILON:
			result.append({"id": "arena/corridor/bottom", "kind": "rect", "rect": Rect2(arena_rect.position.x, lower_start, arena_rect.size.x, bottom_height)})
	elif layout_id == "ring":
		var basis := minf(arena_rect.size.x, arena_rect.size.y)
		result.append({"id": "arena/ring/inner-hole", "kind": "circle", "center": center, "radius": basis * 0.20})
	return result


static func movement_boundary(layout_id: String, arena_rect: Rect2) -> Dictionary:
	if not _valid_rect(arena_rect):
		return {}
	match layout_id:
		"rectangle", "rectangle_arena":
			return {"type": "rect", "rect": arena_rect}
		"corridor":
			return {
				"type": "corridor",
				"rect": arena_rect,
				"axis": "horizontal",
				"half_height": minf(72.0, arena_rect.size.y * 0.25),
			}
		"ring":
			var basis := minf(arena_rect.size.x, arena_rect.size.y)
			return {
				"type": "ring",
				"center": arena_rect.get_center(),
				"inner_radius": basis * 0.20,
				"outer_radius": basis * 0.43,
			}
		_:
			return {}


## Normalizes the raw boundary emitted by SpatialManifest into the same strict
## shape contract that ActorMotor consumes. This is intentionally separate from
## the padded planning snapshot above: a native ring keeps its inner hole and a
## native corridor keeps its authored half-height instead of becoming a generic
## rectangle.
static func normalize_native_boundary(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {"ok": false, "error": "invalid_native_boundary", "value": {}}
	var source: Dictionary = value
	var kind := String(source.get("type", source.get("kind", ""))).strip_edges().to_lower()
	var type_key := "type" if source.has("type") else ("kind" if source.has("kind") else "")
	if type_key.is_empty():
		return {"ok": false, "error": "invalid_native_boundary", "value": {}}
	match kind:
		"rect", "rectangle":
			if not _has_only_fields(source, [type_key, "rect"]):
				return {"ok": false, "error": "invalid_native_fields", "value": {}}
			var rect := _native_rect(source.get("rect", null))
			if not _valid_rect(rect):
				return {"ok": false, "error": "invalid_native_rect", "value": {}}
			return {"ok": true, "error": "", "value": {"type": "rect", "rect": rect}}
		"corridor":
			if not _has_only_fields(source, [type_key, "rect", "axis", "half_height"]):
				return {"ok": false, "error": "invalid_native_fields", "value": {}}
			var corridor := _native_rect(source.get("rect", null))
			var half_height_value: Variant = source.get("half_height", null)
			var axis := String(source.get("axis", "")).strip_edges().to_lower()
			if not _valid_rect(corridor) or axis != "horizontal" or not _valid_number(half_height_value):
				return {"ok": false, "error": "invalid_native_corridor", "value": {}}
			var half_height := float(half_height_value)
			if half_height <= 0.0 or half_height > corridor.size.y * 0.5:
				return {"ok": false, "error": "invalid_native_corridor", "value": {}}
			return {
				"ok": true,
				"error": "",
				"value": {"type": "corridor", "rect": corridor, "axis": "horizontal", "half_height": half_height},
			}
		"ring":
			if not _has_only_fields(source, [type_key, "center", "inner_radius", "outer_radius"]):
				return {"ok": false, "error": "invalid_native_fields", "value": {}}
			var center := _native_vector(source.get("center", null))
			var inner_value: Variant = source.get("inner_radius", null)
			var outer_value: Variant = source.get("outer_radius", null)
			if not _valid_vector(center) or not _valid_number(inner_value) or not _valid_number(outer_value):
				return {"ok": false, "error": "invalid_native_ring", "value": {}}
			var inner := float(inner_value)
			var outer := float(outer_value)
			if inner <= 0.0 or outer <= inner:
				return {"ok": false, "error": "invalid_native_ring", "value": {}}
			return {
				"ok": true,
				"error": "",
				"value": {"type": "ring", "center": center, "inner_radius": inner, "outer_radius": outer},
			}
	return {"ok": false, "error": "unknown_native_boundary", "value": {}}


## A solid convex piece is separate from the outer movement boundary. Native
## scenes may emit JSON-safe points; no concave approximation is accepted here.
static func normalize_native_static_geometry(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {"ok": false, "error": "invalid_static_geometry", "value": {}}
	var source: Dictionary = value
	if not _has_only_fields(source, ["type", "points"]) or source.get("type", null) != "polygon":
		return {"ok": false, "error": "unknown_static_geometry", "value": {}}
	var raw: Variant = source.get("points", null)
	if not raw is Array or (raw as Array).size() < 3:
		return {"ok": false, "error": "invalid_static_points", "value": {}}
	var points := PackedVector2Array()
	for item: Variant in raw:
		var point := _native_vector(item)
		if not point.is_finite():
			return {"ok": false, "error": "invalid_static_points", "value": {}}
		points.append(point)
	if not _valid_convex_polygon(points) or Geometry2D.triangulate_polygon(points).size() != (points.size() - 2) * 3:
		return {"ok": false, "error": "non_convex_static_polygon", "value": {}}
	return {"ok": true, "error": "", "value": {"type": "polygon", "points": points}}


static func expected_kind_for_layout(layout_id: String) -> String:
	match layout_id.strip_edges():
		"rectangle", "rectangle_arena": return "rectangle"
		"corridor": return "corridor"
		"ring": return "ring"
	return ""


## Native SpatialManifest boundaries keep the short "rect" spelling consumed by
## ActorMotor. Planner and presenter snapshots use the canonical "rectangle"
## spelling above, so the two representations cannot be confused silently.
static func expected_native_kind_for_layout(layout_id: String) -> String:
	match layout_id.strip_edges():
		"rectangle", "rectangle_arena": return "rect"
		"corridor": return "corridor"
		"ring": return "ring"
	return ""


## Footprint clearance for authored spawn sockets, before any actor exists.
static func native_position_clear(point: Vector2, boundary: Dictionary, radius: float) -> bool:
	if not point.is_finite() or not _valid_number(radius) or radius < 0.0:
		return false
	var normalized := normalize_native_boundary(boundary)
	if not bool(normalized.get("ok", false)):
		return false
	var native: Dictionary = normalized["value"]
	match String(native["type"]):
		"rect", "corridor":
			var rect: Rect2 = native["rect"]
			if String(native["type"]) == "corridor":
				var half_height := float(native["half_height"])
				rect = Rect2(rect.position.x, rect.get_center().y - half_height, rect.size.x, half_height * 2.0)
			var clearance := rect.grow(-radius)
			return _valid_rect(clearance) and _rect_contains_inclusive(clearance, point)
		"ring":
			var distance := point.distance_to(native["center"])
			return distance + NATIVE_CONTACT_EPSILON >= float(native["inner_radius"]) + radius \
				and distance - NATIVE_CONTACT_EPSILON <= float(native["outer_radius"]) - radius
	return false


static func project(point: Variant, geometry: Variant) -> Dictionary:
	if not _valid_vector(point):
		return _project_failure("invalid_point")
	var normalized := normalize(geometry)
	if not bool(normalized["ok"]):
		return _project_failure(String(normalized["error"]))
	var valid: Dictionary = normalized["value"]
	var bounds: Rect2 = valid["bounds"]
	var position := Vector2(
		clampf((point as Vector2).x, bounds.position.x, bounds.end.x),
		clampf((point as Vector2).y, bounds.position.y, bounds.end.y)
	)
	var kind := String(valid["kind"])
	if kind == "corridor":
		var center: Vector2 = valid["center"]
		var half_height := float(valid["corridor_half_height"])
		position.y = clampf(position.y, center.y - half_height, center.y + half_height)
	elif kind == "ring":
		var center: Vector2 = valid["center"]
		var offset := position - center
		var distance := offset.length()
		var direction := offset.normalized() if distance > _RING_DIRECTION_EPSILON else Vector2.RIGHT
		position = center + direction * clampf(distance, float(valid["inner_radius"]), float(valid["outer_radius"]))
	return {"ok": true, "error": "", "position": position}


static func line_segment_walkable(from_point: Variant, to_point: Variant, geometry: Variant) -> Dictionary:
	if not _valid_vector(from_point):
		return _walkable_failure("invalid_from_point")
	if not _valid_vector(to_point):
		return _walkable_failure("invalid_to_point")
	var normalized := normalize(geometry)
	if not bool(normalized["ok"]):
		return _walkable_failure(String(normalized["error"]))
	var valid: Dictionary = normalized["value"]
	var start := from_point as Vector2
	var finish := to_point as Vector2
	if not _contains_canonical(start, valid) or not _contains_canonical(finish, valid):
		return _walkable_success(false)
	if String(valid["kind"]) != "ring":
		return _walkable_success(true)
	var center: Vector2 = valid["center"]
	var segment := finish - start
	var length_squared := segment.length_squared()
	var closest := start
	if length_squared > 0.0:
		var parameter := clampf((center - start).dot(segment) / length_squared, 0.0, 1.0)
		closest = start + segment * parameter
	var inner_radius := float(valid["inner_radius"])
	return _walkable_success(closest.distance_to(center) + CONTACT_EPSILON >= inner_radius)


static func candidate_directions(desired: Vector2, stable_sign: int) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var base := desired.normalized() if _valid_vector(desired) and not desired.is_zero_approx() else Vector2.ZERO
	var sign := -1.0 if stable_sign < 0 else 1.0
	result.append(base)
	for magnitude: float in [PI / 8.0, PI / 4.0, PI * 3.0 / 8.0, PI / 2.0]:
		result.append(base.rotated(sign * magnitude))
		result.append(base.rotated(-sign * magnitude))
	return result


static func choose_feasible_direction(position: Vector2, desired: Vector2, lookahead: float, geometry: Variant, stable_sign: int) -> Dictionary:
	if not _valid_vector(position):
		return _choice_failure("invalid_position")
	if not _valid_vector(desired):
		return _choice_failure("invalid_desired")
	if not _valid_number(lookahead) or lookahead < 0.0:
		return _choice_failure("invalid_lookahead")
	var normalized := normalize(geometry)
	if not bool(normalized["ok"]):
		return _choice_failure(String(normalized["error"]))
	var directions := candidate_directions(desired, stable_sign)
	var direct_result := project(position + directions[0] * lookahead, normalized["value"])
	var direct_position: Vector2 = direct_result["position"]
	var direct_displacement := position.distance_to(direct_position)
	if _has_meaningful_progress(direct_displacement, lookahead):
		return _choice_success(directions[0], direct_position, direct_displacement, false)
	for index in range(1, directions.size()):
		var projected := project(position + directions[index] * lookahead, normalized["value"])
		var projected_position: Vector2 = projected["position"]
		var displacement := position.distance_to(projected_position)
		if _has_meaningful_progress(displacement, lookahead):
			return _choice_success(directions[index], projected_position, displacement, true)
	return _choice_success(directions[0], direct_position, direct_displacement, false)


static func _normalize_boundary(source: Dictionary) -> Dictionary:
	var kind := String(source.get("type", source.get("kind", ""))).to_lower()
	match kind:
		"rect", "rectangle":
			var rect := _rect(source.get("rect", null))
			return {} if rect == Rect2() else {"type": "rect", "rect": rect}
		"corridor":
			var corridor := _rect(source.get("rect", null))
			var axis := String(source.get("axis", "horizontal")).to_lower()
			if corridor == Rect2() or axis not in ["horizontal", "vertical"]:
				return {}
			return {"type": "corridor", "rect": corridor, "axis": axis}
		"ring":
			var center: Variant = source.get("center", Vector2.ZERO)
			var inner: Variant = source.get("inner_radius", -1.0)
			var outer: Variant = source.get("outer_radius", -1.0)
			if not _valid_vector(center) or not _valid_number(inner) or not _valid_number(outer) or float(inner) < 0.0 or float(outer) <= float(inner):
				return {}
			return {"type": "ring", "center": center, "inner_radius": float(inner), "outer_radius": float(outer)}
	return {}


static func _normalize_blocker(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var source: Dictionary = raw
	var id := String(source.get("id", "")).strip_edges()
	var kind := String(source.get("kind", "convex")).to_lower()
	var points_value: Variant = source.get("points", null)
	if id.is_empty() or kind not in ["convex", "polygon"] or not points_value is Array or (points_value as Array).size() < 3:
		return {}
	var points := PackedVector2Array()
	for value: Variant in points_value:
		if not _valid_vector(value):
			return {}
		points.append(value)
	if not _valid_convex_polygon(points):
		return {}
	return {"id": id, "kind": "convex", "points": points}


static func _valid_convex_polygon(points: PackedVector2Array) -> bool:
	if points.size() < 3:
		return false
	var orientation := 0
	var area := 0.0
	for index in points.size():
		var edge := points[(index + 1) % points.size()] - points[index]
		var next_edge := points[(index + 2) % points.size()] - points[(index + 1) % points.size()]
		if edge.length_squared() <= EPSILON * EPSILON:
			return false
		var cross := edge.cross(next_edge)
		area += points[index].cross(points[(index + 1) % points.size()])
		if absf(cross) <= EPSILON:
			continue
		var current := 1 if cross > 0.0 else -1
		if orientation == 0:
			orientation = current
		elif current != orientation:
			return false
	return orientation != 0 and absf(area) > EPSILON


static func _boundary_contains(position: Vector2, boundary: Dictionary) -> bool:
	if boundary.is_empty() or not position.is_finite():
		return false
	match String(boundary.get("type", "")):
		"rect", "corridor":
			return _rect_contains_inclusive(boundary.get("rect", Rect2()), position)
		"ring":
			var distance := position.distance_to(boundary["center"])
			return distance + EPSILON >= float(boundary["inner_radius"]) and distance - EPSILON <= float(boundary["outer_radius"])
	return false


static func _point_in_convex_polygon(point: Vector2, points: PackedVector2Array) -> bool:
	var orientation := 0
	for index in points.size():
		var cross := (points[(index + 1) % points.size()] - points[index]).cross(point - points[index])
		if absf(cross) <= EPSILON:
			continue
		var current := 1 if cross > 0.0 else -1
		if orientation == 0:
			orientation = current
		elif orientation != current:
			return false
	return true


static func _contains_canonical(point: Vector2, geometry: Dictionary) -> bool:
	if not _valid_vector(point):
		return false
	var bounds: Rect2 = geometry["bounds"]
	if not _rect_contains_inclusive(bounds, point):
		return false
	match String(geometry["kind"]):
		"corridor":
			return absf(point.y - float((geometry["center"] as Vector2).y)) <= float(geometry["corridor_half_height"]) + CONTACT_EPSILON
		"ring":
			var distance := point.distance_to(geometry["center"])
			return distance + CONTACT_EPSILON >= float(geometry["inner_radius"]) and distance - CONTACT_EPSILON <= float(geometry["outer_radius"])
	return true


static func _has_meaningful_progress(displacement: float, lookahead: float) -> bool:
	return displacement > maxf(_SWALLOWED_DISPLACEMENT, lookahead * _MIN_PROGRESS_FRACTION)


static func _rect_contains_inclusive(value: Variant, point: Vector2) -> bool:
	if not value is Rect2 or not _valid_vector(point):
		return false
	var rect: Rect2 = value
	return point.x >= rect.position.x - CONTACT_EPSILON and point.x <= rect.end.x + CONTACT_EPSILON \
		and point.y >= rect.position.y - CONTACT_EPSILON and point.y <= rect.end.y + CONTACT_EPSILON


static func _rect(value: Variant) -> Rect2:
	return value if _valid_rect(value) else Rect2()


static func _native_rect(value: Variant) -> Rect2:
	if value is Rect2:
		return value as Rect2
	if value is Array:
		var values: Array = value as Array
		if values.size() == 4 and values.all(func(item: Variant) -> bool: return _valid_number(item)):
			return Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))
	return Rect2()


static func _native_vector(value: Variant) -> Vector2:
	if value is Vector2:
		return value as Vector2
	if value is Array:
		var values: Array = value as Array
		if values.size() == 2 and values.all(func(item: Variant) -> bool: return _valid_number(item)):
			return Vector2(float(values[0]), float(values[1]))
	return Vector2(INF, INF)


static func _has_only_fields(value: Dictionary, allowed: Array[String]) -> bool:
	for key: Variant in value.keys():
		if String(key) not in allowed:
			return false
	return true


static func _valid_schema_version(value: Variant) -> bool:
	return value is int and not (value is bool) and int(value) == SCHEMA_VERSION


static func _valid_vector(value: Variant) -> bool:
	return value is Vector2 and (value as Vector2).is_finite()


static func _valid_rect(value: Variant) -> bool:
	return value is Rect2 and _valid_vector((value as Rect2).position) and _valid_vector((value as Rect2).size) and (value as Rect2).size.x > 0.0 and (value as Rect2).size.y > 0.0


static func _valid_number(value: Variant) -> bool:
	return (value is int or value is float) and not (value is bool) and is_finite(float(value))


static func _normalize_failure(error: String) -> Dictionary:
	return {"ok": false, "error": error, "value": {}}


static func _definition_failure(error: String) -> Dictionary:
	return {"ok": false, "error": error, "value": {}}


static func _project_failure(error: String) -> Dictionary:
	return {"ok": false, "error": error, "position": Vector2.ZERO}


static func _walkable_failure(error: String) -> Dictionary:
	return {"ok": false, "error": error, "walkable": false}


static func _walkable_success(walkable: bool) -> Dictionary:
	return {"ok": true, "error": "", "walkable": walkable}


static func _choice_failure(error: String) -> Dictionary:
	return {"ok": false, "error": error, "direction": Vector2.ZERO, "projected_position": Vector2.ZERO, "actual_displacement": 0.0, "detour": false}


static func _choice_success(direction: Vector2, projected_position: Vector2, actual_displacement: float, detour: bool) -> Dictionary:
	return {"ok": true, "error": "", "direction": direction, "projected_position": projected_position, "actual_displacement": actual_displacement, "detour": detour}
