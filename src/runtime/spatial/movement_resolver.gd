class_name MovementResolver
extends RefCounted

## The only authority that resolves and commits actor movement.
##
## One fixed-tick displacement for one circular body is resolved by continuous
## sweep-and-slide against the movement channel of the static index, the
## movement boundary and overlay surfaces, plus dynamic bodies through the
## body collision policy.  The resolver never touches a Node, the SceneTree or
## Godot physics, and it returns the committed position; callers own applying
## it to presentation state.

const Shape := preload("res://src/runtime/geometry/spatial_shape.gd")
const Channels := preload("res://src/runtime/spatial/spatial_channels.gd")
const Contact := preload("res://src/runtime/spatial/spatial_contact.gd")
const StaticSpatialIndexScript := preload("res://src/runtime/spatial/static_spatial_index.gd")
const DynamicSpatialIndexScript := preload("res://src/runtime/spatial/dynamic_spatial_index.gd")
const SpatialOverlayScript := preload("res://src/runtime/spatial/spatial_overlay.gd")
const BodyCollisionPolicyScript := preload("res://src/runtime/spatial/body_collision_policy.gd")

const MAX_SLIDES := 8
const REQUEST_FIELDS: Array[String] = [
	"start",
	"displacement",
	"radius",
	"source_id",
	"include_boundary",
	"include_dynamic",
	"policy",
]

var _static: StaticSpatialIndex
var _overlay: SpatialOverlay
var _dynamic: DynamicSpatialIndex
var _policy: BodyCollisionPolicy


static func make(
	static_index: Variant,
	overlay: Variant = null,
	dynamic_index: Variant = null,
	policy: Variant = null
) -> Dictionary:
	var errors: Array[String] = []
	if not static_index is StaticSpatialIndexScript:
		errors.append("resolver:static_index_required")
	if overlay != null and not overlay is SpatialOverlayScript:
		errors.append("resolver:overlay_invalid")
	if dynamic_index != null and not dynamic_index is DynamicSpatialIndexScript:
		errors.append("resolver:dynamic_index_invalid")
	if policy != null and not policy is BodyCollisionPolicyScript:
		errors.append("resolver:policy_invalid")
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "value": null}
	var resolver: MovementResolver = load("res://src/runtime/spatial/movement_resolver.gd").new()
	resolver._static = static_index
	resolver._overlay = overlay
	resolver._dynamic = dynamic_index
	resolver._policy = policy if policy != null else BodyCollisionPolicyScript.make_default()
	return {"ok": true, "errors": [], "value": resolver}


func move(request: Variant) -> Dictionary:
	var errors := _validate_request(request)
	if not errors.is_empty():
		return _failure(Vector2.ZERO, errors)
	var source: Dictionary = request
	var start: Vector2 = source["start"]
	var displacement: Vector2 = source["displacement"]
	var radius := float(source["radius"])
	var source_id := String(source.get("source_id", ""))
	var include_boundary := bool(source.get("include_boundary", true))
	var include_dynamic := bool(source.get("include_dynamic", true)) and _dynamic != null
	var policy: BodyCollisionPolicy = source.get("policy", null) if source.get("policy", null) != null else _policy
	if policy == null:
		policy = BodyCollisionPolicyScript.make_default()

	var position := start
	var remaining := displacement
	var contacts: Array = []
	var recorded: Dictionary = {}
	var blocked := false
	var iterations := 0

	var start_penetrations := _environment_overlaps(position, radius, include_boundary)
	if include_dynamic:
		for contact: Variant in _dynamic.overlaps(Channels.MOVEMENT, position, radius):
			var dynamic_contact := contact as SpatialContact
			if not source_id.is_empty() and dynamic_contact.source_id == source_id:
				continue
			var entry := policy.response_for(StringName(dynamic_contact.response.get("collision_class", "ghost")))
			if entry["response"] == BodyCollisionPolicyScript.RESPONSE_BLOCK:
				start_penetrations.append(dynamic_contact)
			elif bool(entry["record"]):
				_record_contact(contacts, recorded, dynamic_contact)
	start_penetrations = Contact.sort_contacts(start_penetrations)
	if not start_penetrations.is_empty():
		for contact: Variant in start_penetrations:
			_record_contact(contacts, recorded, contact)
		return {
			"ok": true,
			"errors": [],
			"mode": "start_penetrating",
			"position": start,
			"remaining": displacement,
			"contacts": Contact.sort_contacts(contacts),
			"blocked": true,
			"iterations": 0,
			"dynamic_revision": _dynamic_revision(),
		}

	var mode := "completed"
	for iteration: int in MAX_SLIDES:
		if remaining.length_squared() <= Shape.MIN_SHAPE_SIZE * Shape.MIN_SHAPE_SIZE:
			break
		iterations = iteration + 1
		var candidates := _environment_sweep(position, remaining, radius, include_boundary)
		var passing: Array = []
		if include_dynamic:
			for contact: Variant in _dynamic.sweep(Channels.MOVEMENT, position, remaining, radius):
				var dynamic_contact := contact as SpatialContact
				if not source_id.is_empty() and dynamic_contact.source_id == source_id:
					continue
				var entry := policy.response_for(StringName(dynamic_contact.response.get("collision_class", "ghost")))
				dynamic_contact.response["action"] = String(entry["response"])
				if entry["response"] == BodyCollisionPolicyScript.RESPONSE_BLOCK:
					candidates.append(dynamic_contact)
				elif bool(entry["record"]):
					passing.append(dynamic_contact)
		# Static candidates arrive sorted, but dynamic contacts are appended
		# afterwards; re-sort so the earliest contact wins regardless of source.
		candidates = Contact.sort_contacts(candidates)
		var blocking := _blocking_contacts(candidates, remaining)
		for contact: Variant in passing:
			_record_contact(contacts, recorded, contact)
		for contact: Variant in candidates:
			if not (contact as SpatialContact).response.has("action"):
				(contact as SpatialContact).response["action"] = "slide"
		if blocking.is_empty():
			position += remaining
			remaining = Vector2.ZERO
			break
		blocked = true
		var earliest := blocking[0] as SpatialContact
		var ties := _tie_group(blocking, earliest)
		position = position + remaining * earliest.toi + earliest.normal * Shape.CONTACT_SKIN
		remaining = remaining * (1.0 - earliest.toi)
		for contact: Variant in ties:
			var tie := contact as SpatialContact
			var into := remaining.dot(tie.normal)
			if into < 0.0:
				remaining -= tie.normal * into
			_record_contact(contacts, recorded, tie)
		if remaining.length_squared() <= Shape.MIN_SHAPE_SIZE * Shape.MIN_SHAPE_SIZE:
			remaining = Vector2.ZERO
			mode = "blocked"
			break
		if iteration == MAX_SLIDES - 1:
			mode = "slide_budget_exhausted"
	if mode == "completed" and blocked:
		mode = "blocked"

	if include_dynamic and _policy_has_separation(policy):
		position = _apply_soft_separation(position, radius, source_id, policy, contacts, recorded)
	# A straight slide along a curved boundary is a chord.  Its endpoint can
	# therefore be a few floating-point units outside the legal shell even when
	# every reported TOI was valid.  Re-project the final center through the
	# same authored movement boundary before returning it so the next tick never
	# starts in an illegal footprint.
	if include_boundary:
		position = _constrain_boundary_endpoint(position, radius)

	# A skin offset away from one face can enter a neighbouring rounded corner
	# by a few float32 units. Never publish an endpoint that the next tick's
	# start-overlap query rejects. The start was validated above; retaining it
	# rejects only this invalid step and preserves outward movement next tick.
	# An unmoved endpoint is the start position, whose environment overlaps were
	# already proven empty above (otherwise the start_penetrating return fired),
	# and no index changes inside this call; skip the identical second query.
	var endpoint_overlaps: Array = _environment_overlaps(position, radius, include_boundary) if position != start else []
	if not endpoint_overlaps.is_empty():
		for contact: Variant in endpoint_overlaps:
			_record_contact(contacts, recorded, contact)
		position = start
		remaining = displacement
		blocked = true
		mode = "blocked"

	return {
		"ok": true,
		"errors": [],
		"mode": mode,
		"position": position,
		"remaining": remaining,
		"contacts": Contact.sort_contacts(contacts),
		"blocked": blocked,
		"iterations": iterations,
		"dynamic_revision": _dynamic_revision(),
	}


func _apply_soft_separation(
	position: Vector2,
	radius: float,
	source_id: String,
	policy: BodyCollisionPolicy,
	contacts: Array,
	recorded: Dictionary
) -> Vector2:
	var resolved := position
	for body_entry: Dictionary in _dynamic.bodies(Channels.MOVEMENT):
		if not source_id.is_empty() and String(body_entry["entity_id"]) == source_id:
			continue
		if StringName(String(body_entry["collision_class"])) != BodyCollisionPolicyScript.CLASS_SOFT:
			continue
		var body_position: Vector2 = body_entry["position"]
		var combined := radius + float(body_entry["radius"])
		var distance := resolved.distance_to(body_position)
		if distance >= combined - Shape.DISTANCE_EPSILON:
			continue
		var normal := (resolved - body_position).normalized() if distance > Shape.MIN_SHAPE_SIZE else Vector2.ZERO
		var contact := Contact.from_raw({
			"toi": 1.0,
			"point": body_position,
			"normal": normal,
			"feature": "separation",
			"penetrating": true,
			"initial": true,
		}, Channels.MOVEMENT, Contact.KIND_DYNAMIC, String(body_entry["entity_id"]), int(body_entry["generation"]))
		if normal == Vector2.ZERO:
			contact.response = {"action": "separate", "applied": false, "reason": "concentric"}
			_record_contact(contacts, recorded, contact)
			continue
		var depth := combined - distance
		var candidate := resolved + normal * (depth + Shape.CONTACT_SKIN)
		# Separation must stay inside the authored movement boundary. The
		# static index's surface-only clearance does not know about the
		# corridor band or the ring hole, so a surface-clear candidate could
		# still push a body out of the walkable world.
		var valid := _environment_overlaps(candidate, radius, true).is_empty()
		contact.response = {"action": "separate", "applied": valid, "depth": depth}
		_record_contact(contacts, recorded, contact)
		if valid:
			resolved = candidate
	return resolved


func _overlay_clear(position: Vector2, radius: float) -> bool:
	if _overlay == null:
		return true
	for contact: Variant in _overlay.overlaps(Channels.MOVEMENT, position, radius):
		if not _overlay.is_suppressed((contact as SpatialContact).source_id):
			return false
	return true


static func _policy_has_separation(policy: BodyCollisionPolicy) -> bool:
	return policy.response_for(BodyCollisionPolicyScript.CLASS_SOFT)["response"] == BodyCollisionPolicyScript.RESPONSE_SEPARATE


func _environment_sweep(position: Vector2, displacement: Vector2, radius: float, include_boundary: bool) -> Array:
	var candidates: Array = []
	for contact: Variant in _static.sweep(Channels.MOVEMENT, position, displacement, radius):
		var static_contact := contact as SpatialContact
		if _overlay != null and _overlay.is_suppressed(static_contact.source_id):
			continue
		candidates.append(static_contact)
	if _overlay != null:
		for contact: Variant in _overlay.sweep(Channels.MOVEMENT, position, displacement, radius):
			candidates.append(contact)
	if include_boundary:
		for contact: Variant in _static.boundary_sweep(position, displacement, radius):
			candidates.append(contact)
	return Contact.sort_contacts(candidates)


func _environment_overlaps(position: Vector2, radius: float, include_boundary: bool) -> Array:
	var overlaps: Array = []
	for contact: Variant in _static.overlaps(Channels.MOVEMENT, position, radius):
		var static_contact := contact as SpatialContact
		if _overlay != null and _overlay.is_suppressed(static_contact.source_id):
			continue
		overlaps.append(static_contact)
	if _overlay != null:
		for contact: Variant in _overlay.overlaps(Channels.MOVEMENT, position, radius):
			overlaps.append(contact)
	if include_boundary:
		for contact: Variant in _static.boundary_sweep(position, Vector2.ZERO, radius):
			if (contact as SpatialContact).penetrating:
				overlaps.append(contact)
	return overlaps


func _constrain_boundary_endpoint(position: Vector2, radius: float) -> Vector2:
	if _static == null:
		return position
	var boundary := _static.movement_boundary()
	if boundary.is_empty():
		return position
	var margin := 0.0
	match String(boundary.get("kind", "")):
		"rect":
			var rect: Rect2 = boundary.get("rect", Rect2())
			var minimum := rect.position + Vector2(radius + margin, radius + margin)
			var maximum := rect.end - Vector2(radius + margin, radius + margin)
			if maximum.x <= minimum.x or maximum.y <= minimum.y:
				return position
			return Vector2(clampf(position.x, minimum.x, maximum.x), clampf(position.y, minimum.y, maximum.y))
		"corridor":
			var corridor: Rect2 = boundary.get("rect", Rect2())
			var half_height := float(boundary.get("half_height", 0.0))
			var x_min := corridor.position.x + radius + margin
			var x_max := corridor.end.x - radius - margin
			var y_min := corridor.get_center().y - half_height + radius + margin
			var y_max := corridor.get_center().y + half_height - radius - margin
			if x_max <= x_min or y_max <= y_min:
				return position
			return Vector2(clampf(position.x, x_min, x_max), clampf(position.y, y_min, y_max))
		"ring":
			var center: Vector2 = boundary.get("center", Vector2.ZERO)
			var inner := float(boundary.get("inner_radius", 0.0)) + radius
			var outer := float(boundary.get("outer_radius", 0.0)) - radius
			var safe_inner := inner + margin
			var safe_outer := outer - margin
			if safe_outer <= safe_inner:
				return position
			var offset := position - center
			var distance := offset.length()
			if distance <= Shape.MIN_SHAPE_SIZE:
				return center + Vector2.RIGHT * safe_inner
			var boundary_snap := Shape.DISTANCE_EPSILON * 2.0
			if absf(distance - safe_inner) <= boundary_snap:
				return center + offset / distance * safe_inner
			if absf(distance - safe_outer) <= boundary_snap:
				return center + offset / distance * safe_outer
			if distance < safe_inner:
				return center + offset / distance * safe_inner
			if distance > safe_outer:
				return center + offset / distance * safe_outer
	return position


static func _blocking_contacts(candidates: Array, remaining: Vector2) -> Array:
	var blocking: Array = []
	for contact: Variant in candidates:
		var candidate := contact as SpatialContact
		# A penetration found after a previous contact can be the tiny overlap
		# introduced by contact skin at a corner.  The initial penetration pass
		# already returned before entering the sweep loop; here a penetrating
		# candidate must still block when the remaining displacement points into
		# its push-out normal, otherwise a corner slide can enter the adjacent
		# face and leave the committed footprint invalid.
		if candidate.penetrating and (candidate.normal == Vector2.ZERO or remaining.dot(candidate.normal) >= -Shape.DIRECTION_EPSILON):
			continue
		if candidate.toi > 1.0 + Shape.TOI_EPSILON:
			continue
		if remaining.dot(candidate.normal) >= -Shape.DIRECTION_EPSILON:
			continue
		blocking.append(candidate)
	return blocking


static func _tie_group(blocking: Array, earliest: SpatialContact) -> Array:
	var earliest_key := Shape.fmt(earliest.toi)
	var ties: Array = []
	for contact: Variant in blocking:
		if Shape.fmt((contact as SpatialContact).toi) == earliest_key:
			ties.append(contact)
	return ties


static func _record_contact(contacts: Array, recorded: Dictionary, contact: SpatialContact) -> void:
	var key := contact.dedupe_key()
	if recorded.has(key):
		return
	recorded[key] = true
	contacts.append(contact)


func _dynamic_revision() -> int:
	return _dynamic.revision() if _dynamic != null else 0


func _validate_request(request: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not request is Dictionary:
		return ["move:invalid_type"]
	var source: Dictionary = request
	for field: String in ["start", "displacement", "radius"]:
		if not source.has(field):
			errors.append("move:missing_field:%s" % field)
	for key: Variant in source.keys():
		if not REQUEST_FIELDS.has(String(key)):
			errors.append("move:unknown_field:%s" % String(key))
	if not source.get("start", null) is Vector2 or not (source.get("start", null) as Vector2).is_finite():
		errors.append("move.start:invalid")
	if not source.get("displacement", null) is Vector2 or not (source.get("displacement", null) as Vector2).is_finite():
		errors.append("move.displacement:invalid")
	var radius_value: Variant = source.get("radius", null)
	if radius_value is float or radius_value is int:
		var radius := float(radius_value)
		if not is_finite(radius) or radius < 0.0:
			errors.append("move.radius:invalid")
	else:
		errors.append("move.radius:invalid_type")
	if source.has("source_id") and not (source["source_id"] is String or source["source_id"] is StringName):
		errors.append("move.source_id:invalid_type")
	if source.has("policy") and source["policy"] != null and not source["policy"] is BodyCollisionPolicyScript:
		errors.append("move.policy:invalid")
	return errors


static func _failure(position: Vector2, errors: Array[String]) -> Dictionary:
	return {
		"ok": false,
		"errors": errors,
		"mode": "invalid_request",
		"position": position,
		"remaining": Vector2.ZERO,
		"contacts": [],
		"blocked": false,
		"iterations": 0,
		"dynamic_revision": 0,
	}
