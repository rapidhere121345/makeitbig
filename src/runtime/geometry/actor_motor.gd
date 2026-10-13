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

var query
var radius := 0.0


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
func set_radius(value: float) -> void:
	if is_finite(value):
		radius = maxf(0.0, value)


func register(blocker_or_id: Variant, shape: Variant = null) -> bool:
	return query.register(blocker_or_id, shape)


func register_rect(blocker_id: String, rect: Variant) -> bool:
	return query.register_rect(blocker_id, rect)


func register_circle(blocker_id: String, center: Variant, blocker_radius: float) -> bool:
	return query.register_circle(blocker_id, center, blocker_radius)


func register_polygon(blocker_id: String, points: Variant) -> bool:
	return query.register_polygon(blocker_id, points)


func unregister(blocker_id: String) -> bool:
	return query.unregister(blocker_id)


func clear() -> void:
	query.clear()


func snapshot() -> Array[Dictionary]:
	return query.snapshot()


func is_position_clear(position: Vector2, bounds: Rect2 = Rect2()) -> bool:
	if not position.is_finite():
		return false
	if not _inside_bounds(position, bounds):
		return false
	return query.is_position_clear(position, radius)


## Returns static blocker and world-bound candidates in deterministic order.
## The array can include a t=0 contact that is being left; move filters that
## case without hiding the contact from callers using sweep directly.
func sweep(start: Vector2, displacement: Vector2, bounds: Rect2 = Rect2()) -> Array[Dictionary]:
	var hits: Array[Dictionary] = query.sweep(start, displacement, radius)
	for hit: Dictionary in _sweep_bounds(start, displacement, bounds):
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

	if not start.is_finite() or not displacement.is_finite():
		return _result(position, false, contacts, remaining, iterations)
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
		remaining = projected
		if remaining.length_squared() <= GeometryQueryScript.EPSILON * GeometryQueryScript.EPSILON:
			remaining = Vector2.ZERO
			break
		# A penetrating start has no valid nearest-walkable projection.  Keep the
		# authored position and stop this move rather than silently teleporting it.
		if earliest_time <= GeometryQueryScript.TIME_EPSILON and _has_penetration(simultaneous) and projected.distance_squared_to(after) <= GeometryQueryScript.EPSILON * GeometryQueryScript.EPSILON:
			remaining = Vector2.ZERO
			break

	return _result(position, blocked, contacts, remaining, iterations)


func _result(position: Vector2, blocked: bool, contacts: Array[Dictionary], remaining: Vector2, iterations: int) -> Dictionary:
	var ordered_contacts := GeometryQueryScript.sort_hits(contacts)
	return {
		"position": position,
		"blocked": blocked,
		"contacts": ordered_contacts,
		"remaining": remaining,
		"iterations": iterations,
	}


func _blocks_motion(contact: Dictionary, motion: Vector2) -> bool:
	if bool(contact.get("penetrating", false)):
		return true
	var normal: Vector2 = contact.get("normal", Vector2.RIGHT)
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
