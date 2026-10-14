class_name ActorMotor
extends RefCounted

## Fixed-tick, pure-data movement for a circular actor footprint.
##
## The motor never mutates a scene object.  Call move once for each simulation
## tick with the displacement for that tick.  Collision positions remain
## floating point values; there is no render-grid or pixel snapping step.

const GeometryQueryScript := preload("res://src/runtime/geometry/geometry_query.gd")

const MAX_ITERATIONS := 8
const MAX_CONTACT_PROJECTION_PASSES := 8
## A contact projection can lose a few ulps when an authored UV polygon is
## expanded by a circular footprint.  This tiny, query-verified separation is
## only applied after a valid start; it never repairs an invalid authored spawn.
const CLEARANCE_NUDGE := 0.001

var query
var radius := 0.0
var movement_boundary: Dictionary = {}


func _init(first: Variant = null, second: Variant = null) -> void:
	query = GeometryQueryScript.new()
	if first is GeometryQueryScript:
		query = first
		if _is_number(second):
			radius = maxf(0.0, float(second))
	elif _is_number(first):
		radius = maxf(0.0, float(first))
		if second is GeometryQueryScript:
			query = second
	elif second is GeometryQueryScript:
		query = second
	elif _is_number(second):
		radius = maxf(0.0, float(second))
func set_geometry_radius(value: float) -> bool:
	if is_finite(value):
		radius = maxf(0.0, value)
		return true
	return false


func set_boundary(value: Variant) -> bool:
	if value == null:
		movement_boundary = {}
		return true
	if not value is Dictionary:
		return false
	var candidate: Dictionary = value
	var kind := String(candidate.get("type", "")).strip_edges().to_lower()
	if kind not in ["rect", "corridor", "ring"]:
		return false
	if kind in ["rect", "corridor"]:
		if not candidate.get("rect", null) is Rect2 or not _valid_rect(candidate["rect"]):
			return false
		if kind == "corridor" and String(candidate.get("axis", "horizontal")) != "horizontal":
			return false
		if kind == "corridor" and (not _is_number(candidate.get("half_height", null)) or float(candidate["half_height"]) <= 0.0):
			return false
		movement_boundary = {
			"type": kind,
			"rect": candidate["rect"],
			"half_height": float(candidate.get("half_height", 0.0)),
		}
		return true
	if not candidate.get("center", null) is Vector2 or not (candidate["center"] as Vector2).is_finite():
		return false
	if not _is_number(candidate.get("inner_radius", null)) or not _is_number(candidate.get("outer_radius", null)):
		return false
	var inner := float(candidate["inner_radius"])
	var outer := float(candidate["outer_radius"])
	if inner < 0.0 or outer <= inner:
		return false
	movement_boundary = {
		"type": "ring",
		"center": candidate["center"],
		"inner_radius": inner,
		"outer_radius": outer,
	}
	return true


func register_rect(blocker_id: String, rect: Variant) -> bool:
	return query.register_rect(blocker_id, rect)


func register_circle(blocker_id: String, center: Variant, blocker_radius: float) -> bool:
	return query.register_circle(blocker_id, center, blocker_radius)


func register_polygon(blocker_id: String, points: Variant) -> bool:
	return query.register_polygon(blocker_id, points)


func unregister(blocker_id: String) -> bool:
	return query.unregister(blocker_id)


func clear_geometry() -> void:
	query.clear()


func snapshot() -> Array[Dictionary]:
	return query.snapshot()


func is_position_clear(position: Vector2, bounds: Rect2 = Rect2()) -> bool:
	if not position.is_finite():
		return false
	if not _inside_domain(position, bounds):
		return false
	return query.is_position_clear(position, radius)


## Returns static blocker and world-bound candidates in deterministic order.
## The array can include a t=0 contact that is being left; move filters that
## case without hiding the contact from callers using sweep directly.
func sweep(start: Vector2, displacement: Vector2, bounds: Rect2 = Rect2()) -> Array[Dictionary]:
	var hits: Array[Dictionary] = query.sweep(start, displacement, radius)
	for hit: Dictionary in _sweep_domain(start, displacement, bounds):
		hits.append(hit)
	return GeometryQueryScript.sort_hits(hits)


## Moves one fixed-tick displacement.  remaining is the part discarded only
## when the finite slide budget is exhausted or a penetration start is held.
func move(start: Vector2, displacement: Vector2, bounds: Rect2 = Rect2()) -> Dictionary:
	var position := start
	var remaining := displacement
	var contacts: Array[Dictionary] = []
	var blocked := false
	var iterations := 0
	var start_was_clear := is_position_clear(start, bounds)

	if not start.is_finite() or not displacement.is_finite():
		return _failure(_result(position, false, contacts, remaining, iterations), "invalid_motor_input")
	if not start_was_clear:
		for candidate: Dictionary in sweep(start, Vector2.ZERO, bounds):
			_append_contact(contacts, candidate)
		return _failure(_result(start, true, contacts, remaining, iterations), "invalid_motor_start")
	if remaining.length_squared() <= GeometryQueryScript.EPSILON * GeometryQueryScript.EPSILON:
		for candidate: Dictionary in sweep(position, Vector2.ZERO, bounds):
			if bool(candidate.get("initial", false)) or bool(candidate.get("penetrating", false)):
				_append_contact(contacts, candidate)
		blocked = not contacts.is_empty()
		return _result(position, blocked, contacts, Vector2.ZERO, iterations)

	for iteration in MAX_ITERATIONS:
		if remaining.length_squared() <= GeometryQueryScript.EPSILON * GeometryQueryScript.EPSILON:
			break
		iterations += 1
		var candidates := sweep(position, remaining, bounds)
		var blocking: Array[Dictionary] = []
		for candidate: Dictionary in candidates:
			if _blocks_motion(candidate, remaining):
				blocking.append(candidate)
		if blocking.is_empty():
			position += remaining
			remaining = Vector2.ZERO
			break

		var earliest_time := 1.0
		for candidate: Dictionary in blocking:
			earliest_time = minf(earliest_time, float(candidate.get("time", 1.0)))
		earliest_time = clampf(earliest_time, 0.0, 1.0)
		var simultaneous: Array[Dictionary] = []
		for candidate: Dictionary in blocking:
			if absf(float(candidate.get("time", 1.0)) - earliest_time) <= GeometryQueryScript.TIME_EPSILON:
				simultaneous.append(candidate)
		simultaneous = GeometryQueryScript.sort_hits(simultaneous)

		var travel := remaining * earliest_time
		position += travel
		var after := remaining * (1.0 - earliest_time)
		blocked = true
		for candidate: Dictionary in simultaneous:
			var contact := candidate.duplicate(true)
			contact["position"] = position
			_append_contact(contacts, contact)

		var projected := _project_against_contacts(after, simultaneous)
		projected = _outer_slide_continuation(position, projected, simultaneous)
		remaining = projected
		if remaining.length_squared() <= GeometryQueryScript.EPSILON * GeometryQueryScript.EPSILON:
			remaining = Vector2.ZERO
			break
		# A penetrating start has no valid nearest-walkable projection.  Keep the
		# authored position and stop this move rather than silently teleporting it.
		if earliest_time <= GeometryQueryScript.TIME_EPSILON and _has_penetration(simultaneous) and projected.distance_squared_to(after) <= GeometryQueryScript.EPSILON * GeometryQueryScript.EPSILON:
			remaining = Vector2.ZERO
			break

	return _result(position, blocked, contacts, remaining, iterations, start_was_clear, bounds)



func _result(
	position: Vector2,
	blocked: bool,
	contacts: Array[Dictionary],
	remaining: Vector2,
	iterations: int,
	enforce_clear: bool = false,
	bounds: Rect2 = Rect2()
) -> Dictionary:
	if enforce_clear and not is_position_clear(position, bounds):
		position = _repair_clear_position(position, contacts, bounds)
	var ordered_contacts := GeometryQueryScript.sort_hits(contacts)
	var result := {
		"ok": true,
		"error": "",
		"position": position,
		"blocked": blocked,
		"contacts": ordered_contacts,
		"remaining": remaining,
		"iterations": iterations,
	}
	if enforce_clear and not is_position_clear(position, bounds):
		return _failure(result, "invalid_motor_clearance")
	return result


func _failure(result: Dictionary, error: String) -> Dictionary:
	result["ok"] = false
	result["error"] = error
	return result


## A tangent line at the outer circle immediately leaves the allowed disk.
## Retract that contact's projected endpoint radially, then let the next normal
## sweep resolve the resulting chord against ALL blockers and the inner hole.
## This is part of contact response, never a post-move clamp or spawn repair.
func _outer_slide_continuation(position: Vector2, motion: Vector2, contacts: Array[Dictionary]) -> Vector2:
	var outer_contact := false
	for contact: Dictionary in contacts:
		if String(contact.get("kind", "")) == "ring_boundary" and String(contact.get("feature_key", "")) == "outer":
			outer_contact = true
			break
	if not outer_contact or motion.length_squared() <= GeometryQueryScript.EPSILON * GeometryQueryScript.EPSILON:
		return motion
	var center: Vector2 = movement_boundary["center"]
	var limit := float(movement_boundary["outer_radius"]) - radius
	var endpoint := position + motion
	var x := float(endpoint.x) - float(center.x)
	var y := float(endpoint.y) - float(center.y)
	var distance := sqrt(x * x + y * y)
	if distance <= limit:
		return motion
	var scale := limit / distance
	var retracted := Vector2(float(center.x) + x * scale, float(center.y) + y * scale)
	return retracted - position


func _repair_clear_position(position: Vector2, contacts: Array[Dictionary], bounds: Rect2) -> Vector2:
	var candidates := contacts.duplicate(true)
	for candidate: Dictionary in sweep(position, Vector2.ZERO, bounds):
		_append_contact(candidates, candidate)
	var repaired := position
	for _pass in MAX_CONTACT_PROJECTION_PASSES:
		if is_position_clear(repaired, bounds):
			return repaired
		var changed := false
		for contact: Dictionary in GeometryQueryScript.sort_hits(candidates):
			var normal: Vector2 = contact.get("normal", Vector2.ZERO)
			if normal.length_squared() <= GeometryQueryScript.EPSILON * GeometryQueryScript.EPSILON:
				continue
			normal = normal.normalized()
			var trial := repaired + normal * CLEARANCE_NUDGE
			if is_position_clear(trial, bounds):
				repaired = trial
				changed = true
				break
			if not trial.is_equal_approx(repaired):
				repaired = trial
				changed = true
				break
		if not changed:
			break
	return repaired


func _blocks_motion(contact: Dictionary, motion: Vector2) -> bool:
	if bool(contact.get("penetrating", false)):
		return true
	var normal: Vector2 = contact.get("normal", Vector2.RIGHT)
	if String(contact.get("kind", "")) == "ring_boundary" and String(contact.get("feature_key", "")) == "outer":
		# The circle sweep returns only disk EXITs, including a t=0 tangent.
		# Retesting a rounded Vector2 normal can misclassify that tangent as
		# leaving the contact. Inward reversal has no exit within the segment.
		return true
	return motion.dot(normal) < -GeometryQueryScript.EPSILON


func _project_against_contacts(value: Vector2, contacts: Array[Dictionary]) -> Vector2:
	var result := value
	for _pass in MAX_CONTACT_PROJECTION_PASSES:
		var changed := false
		for contact: Dictionary in contacts:
			var normal: Vector2 = contact.get("normal", Vector2.RIGHT)
			if normal.length_squared() <= GeometryQueryScript.EPSILON * GeometryQueryScript.EPSILON:
				continue
			normal = normal.normalized()
			var inward := result.dot(normal)
			if inward < -GeometryQueryScript.EPSILON:
				result -= normal * inward
				changed = true
		if not changed:
			break
	return result


func _append_contact(target: Array[Dictionary], candidate: Dictionary) -> void:
	var candidate_id := String(candidate.get("blocker_id", candidate.get("id", "")))
	var candidate_normal: Vector2 = candidate.get("normal", Vector2.RIGHT)
	for existing: Dictionary in target:
		if String(existing.get("blocker_id", existing.get("id", ""))) == candidate_id:
			var existing_normal: Vector2 = existing.get("normal", Vector2.RIGHT)
			if existing_normal.distance_squared_to(candidate_normal) <= GeometryQueryScript.CONTACT_EPSILON * GeometryQueryScript.CONTACT_EPSILON:
				return
	target.append(candidate)


func _has_penetration(contacts: Array[Dictionary]) -> bool:
	for contact: Dictionary in contacts:
		if bool(contact.get("penetrating", false)):
			return true
	return false


func _inside_bounds(position: Vector2, bounds: Rect2) -> bool:
	if not _bounds_enabled(bounds):
		return true
	var rect := _normalized_rect(bounds)
	var minimum := rect.position + Vector2.ONE * radius
	var maximum := rect.end - Vector2.ONE * radius
	if maximum.x < minimum.x - GeometryQueryScript.CONTACT_EPSILON or maximum.y < minimum.y - GeometryQueryScript.CONTACT_EPSILON:
		return false
	return position.x >= minimum.x - GeometryQueryScript.CONTACT_EPSILON \
		and position.x <= maximum.x + GeometryQueryScript.CONTACT_EPSILON \
		and position.y >= minimum.y - GeometryQueryScript.CONTACT_EPSILON \
		and position.y <= maximum.y + GeometryQueryScript.CONTACT_EPSILON


func _inside_domain(position: Vector2, bounds: Rect2) -> bool:
	if movement_boundary.is_empty():
		return _inside_bounds(position, bounds)
	match String(movement_boundary.get("type", "")):
		"rect":
			return _inside_bounds(position, movement_boundary["rect"])
		"corridor":
			var rect: Rect2 = movement_boundary["rect"]
			var half_height := float(movement_boundary["half_height"]) - radius
			var center_y := rect.get_center().y
			return half_height >= 0.0 \
				and position.x >= rect.position.x + radius - GeometryQueryScript.CONTACT_EPSILON \
				and position.x <= rect.end.x - radius + GeometryQueryScript.CONTACT_EPSILON \
				and position.y >= center_y - half_height - GeometryQueryScript.CONTACT_EPSILON \
				and position.y <= center_y + half_height + GeometryQueryScript.CONTACT_EPSILON
		"ring":
			var distance := position.distance_to(movement_boundary["center"])
			return distance >= float(movement_boundary["inner_radius"]) + radius - GeometryQueryScript.CONTACT_EPSILON \
				and distance <= float(movement_boundary["outer_radius"]) - radius + GeometryQueryScript.CONTACT_EPSILON
	return false


func _sweep_domain(start: Vector2, motion: Vector2, bounds: Rect2) -> Array[Dictionary]:
	if movement_boundary.is_empty():
		return _sweep_bounds(start, motion, bounds)
	match String(movement_boundary.get("type", "")):
		"rect":
			return _sweep_bounds(start, motion, movement_boundary["rect"])
		"corridor":
			var rect: Rect2 = movement_boundary["rect"]
			var half_height := float(movement_boundary["half_height"]) - radius
			if half_height < 0.0:
				return []
			var center_y := rect.get_center().y
			var minimum := Vector2(rect.position.x + radius, center_y - half_height)
			var maximum := Vector2(rect.end.x - radius, center_y + half_height)
			return _sweep_rect_limits(start, motion, minimum, maximum, "corridor")
		"ring":
			return _sweep_ring(start, motion)
	return []


func _sweep_rect_limits(start: Vector2, motion: Vector2, minimum: Vector2, maximum: Vector2, prefix: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if maximum.x < minimum.x or maximum.y < minimum.y:
		return result
	_append_boundary_hit(result, "%s:left" % prefix, start, motion, minimum.x, start.x, -motion.x, Vector2.RIGHT, "left")
	_append_boundary_hit(result, "%s:right" % prefix, start, motion, maximum.x, start.x, motion.x, Vector2.LEFT, "right")
	_append_boundary_hit(result, "%s:top" % prefix, start, motion, minimum.y, start.y, -motion.y, Vector2.DOWN, "top")
	_append_boundary_hit(result, "%s:bottom" % prefix, start, motion, maximum.y, start.y, motion.y, Vector2.UP, "bottom")
	return GeometryQueryScript.sort_hits(result)


func _sweep_ring(start: Vector2, motion: Vector2) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var center: Vector2 = movement_boundary["center"]
	var inner := float(movement_boundary["inner_radius"]) + radius
	var outer := float(movement_boundary["outer_radius"]) - radius
	_append_circle_boundary_hit(result, "ring:inner", start, motion, center, inner, false)
	_append_circle_boundary_hit(result, "ring:outer", start, motion, center, outer, true)
	return GeometryQueryScript.sort_hits(result)


func _append_circle_boundary_hit(target: Array[Dictionary], blocker_id: String, start: Vector2, motion: Vector2, center: Vector2, limit: float, outer_boundary: bool) -> void:
	if limit <= 0.0:
		return
	var offset := start - center
	var distance := offset.length()
	var normal := (-offset).normalized() if outer_boundary and distance > GeometryQueryScript.EPSILON else (offset.normalized() if distance > GeometryQueryScript.EPSILON else Vector2.RIGHT)
	var forbidden := (distance > limit + GeometryQueryScript.CONTACT_EPSILON) if outer_boundary else (distance < limit - GeometryQueryScript.CONTACT_EPSILON)
	var initial := absf(distance - limit) <= GeometryQueryScript.CONTACT_EPSILON
	if forbidden:
		target.append(_circle_hit(blocker_id, start, normal, 0.0, true, true, outer_boundary))
		return
	# Vector2 dot/length_squared round to real_t before returning a double.
	# Near a tangent, that error in c can erase both roots of the quadratic.
	# Form the coefficients from represented components in scalar precision.
	var x := float(start.x) - float(center.x)
	var y := float(start.y) - float(center.y)
	var mx := float(motion.x)
	var my := float(motion.y)
	var speed_squared := mx * mx + my * my
	if speed_squared <= GeometryQueryScript.EPSILON * GeometryQueryScript.EPSILON:
		if initial:
			target.append(_circle_hit(blocker_id, start, normal, 0.0, true, false, outer_boundary))
		return
	var radial_motion := x * mx + y * my
	if initial and ((outer_boundary and radial_motion >= -GeometryQueryScript.EPSILON * distance) or (not outer_boundary and radial_motion < 0.0)):
		target.append(_circle_hit(blocker_id, start, normal, 0.0, true, false, outer_boundary))
		return
	var b := 2.0 * radial_motion
	var c := x * x + y * y - limit * limit
	var discriminant := b * b - 4.0 * speed_squared * c
	if discriminant < -GeometryQueryScript.TIME_EPSILON:
		return
	discriminant = maxf(0.0, discriminant)
	var root := sqrt(discriminant)
	var first := (-b - root) / (2.0 * speed_squared)
	var second := (-b + root) / (2.0 * speed_squared)
	var time := second if outer_boundary else first
	if time < -GeometryQueryScript.TIME_EPSILON or time > 1.0 + GeometryQueryScript.TIME_EPSILON:
		return
	var contact_position := start + motion * clampf(time, 0.0, 1.0)
	var contact_offset := contact_position - center
	if contact_offset.length_squared() > GeometryQueryScript.EPSILON * GeometryQueryScript.EPSILON:
		normal = (-contact_offset).normalized() if outer_boundary else contact_offset.normalized()
	target.append(_circle_hit(blocker_id, contact_position, normal, clampf(time, 0.0, 1.0), initial, false, outer_boundary))


func _circle_hit(blocker_id: String, position: Vector2, normal: Vector2, time: float, initial: bool, penetrating: bool, outer_boundary: bool) -> Dictionary:
	return {
		"id": blocker_id,
		"blocker_id": blocker_id,
		"kind": "ring_boundary",
		"time": time,
		"position": position,
		"normal": normal,
		"initial": initial or penetrating,
		"penetrating": penetrating,
		"shape_key": "ring|%s|%s" % ["outer" if outer_boundary else "inner", String.num(time, 9)],
		"feature_key": "outer" if outer_boundary else "inner",
	}


func _sweep_bounds(start: Vector2, motion: Vector2, bounds: Rect2) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _bounds_enabled(bounds):
		return result
	var rect := _normalized_rect(bounds)
	var minimum := rect.position + Vector2.ONE * radius
	var maximum := rect.end - Vector2.ONE * radius
	if maximum.x < minimum.x or maximum.y < minimum.y:
		return result
	_append_boundary_hit(result, "bounds:left", start, motion, minimum.x, start.x, -motion.x, Vector2.RIGHT, "left")
	_append_boundary_hit(result, "bounds:right", start, motion, maximum.x, start.x, motion.x, Vector2.LEFT, "right")
	_append_boundary_hit(result, "bounds:top", start, motion, minimum.y, start.y, -motion.y, Vector2.DOWN, "top")
	_append_boundary_hit(result, "bounds:bottom", start, motion, maximum.y, start.y, motion.y, Vector2.UP, "bottom")
	return GeometryQueryScript.sort_hits(result)


func _append_boundary_hit(target: Array[Dictionary], blocker_id: String, start: Vector2, motion: Vector2, limit: float, coordinate: float, toward_speed: float, normal: Vector2, feature: String) -> void:
	var gap := (coordinate - limit) if normal == Vector2.RIGHT or normal == Vector2.DOWN else (limit - coordinate)
	var penetrating := gap < -GeometryQueryScript.CONTACT_EPSILON
	var initial := absf(gap) <= GeometryQueryScript.CONTACT_EPSILON
	if not penetrating and not initial and toward_speed <= GeometryQueryScript.EPSILON:
		return
	var time := 0.0
	if not penetrating and not initial:
		time = gap / toward_speed
		if time < -GeometryQueryScript.TIME_EPSILON or time > 1.0 + GeometryQueryScript.TIME_EPSILON:
			return
		time = clampf(time, 0.0, 1.0)
	var position := start + motion * time
	target.append({
		"id": blocker_id,
		"blocker_id": blocker_id,
		"kind": "bounds",
		"time": time,
		"position": position,
		"normal": normal,
		"initial": initial or penetrating,
		"penetrating": penetrating,
		"shape_key": "bounds|%s" % feature,
		"feature_key": feature,
	})


func _bounds_enabled(bounds: Rect2) -> bool:
	return bounds.size.x > GeometryQueryScript.EPSILON and bounds.size.y > GeometryQueryScript.EPSILON


func _normalized_rect(value: Rect2) -> Rect2:
	var position := value.position
	var size := value.size
	if size.x < 0.0:
		position.x += size.x
		size.x = -size.x
	if size.y < 0.0:
		position.y += size.y
		size.y = -size.y
	return Rect2(position, size)


func _is_number(value: Variant) -> bool:
	return (value is int or value is float) and not (value is bool) and is_finite(float(value))


func _valid_rect(value: Variant) -> bool:
	return value is Rect2 and (value as Rect2).position.is_finite() and (value as Rect2).size.is_finite() and (value as Rect2).size.x > GeometryQueryScript.EPSILON and (value as Rect2).size.y > GeometryQueryScript.EPSILON
