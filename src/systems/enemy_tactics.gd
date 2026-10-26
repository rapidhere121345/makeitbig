class_name EnemyTactics
extends RefCounted

const ArenaGeometry := preload("res://src/runtime/geometry/arena_geometry.gd")

## Deterministic, scene-free enemy intent planner.
##
## Snapshot contract v2:
## {
##   "snapshot_version": 2,
##   "tick": int >= 0,
##   "player_position": Vector2,
##   "arena_rect": Rect2 with positive size,
##   "walkable_geometry": normalized ArenaGeometry with bounds == arena_rect,
##   "enemies": [{
##     "entity_id": int >= 0 (unique),
##     "kind_id": "melee_pursuer" | "charging_raider" | "fan_ranged" |
##                "threshold_colossus",
##     "position": Vector2,
##     "action_state": "idle" | "locomotion" | "range_hold" | "windup" |
##                     "active" | "recovery" | "transition",
##     "health": finite number >= 0,
##     "facing": optional non-zero Vector2,
##     "phase": required for threshold_colossus: "sealed" | "awakened",
##     "next_action_index": required for threshold_colossus: int >= 0
##   }],
##   "hazards": optional [{
##     "active_geometry": optional shape,
##     "warning_geometry": optional shape
##   }]
## }
## A shape is {"shape":"circle", "center":Vector2, "radius":number > 0}
## or {"shape":"rect", "rect":Rect2 with positive size}. Unknown enum values,
## shapes, or malformed required data fail closed. Extra spatial metadata is ignored.
## The planner never mutates the snapshot.

const SNAPSHOT_VERSION := 2

const KIND_MELEE := "melee_pursuer"
const KIND_CHARGER := "charging_raider"
const KIND_FAN := "fan_ranged"
const KIND_COLOSSUS := "threshold_colossus"

const LOCKED_ACTION_STATES := [&"windup", &"active", &"recovery", &"transition"]
const VALID_ACTION_STATES := [&"idle", &"locomotion", &"range_hold", &"windup", &"active", &"recovery", &"transition"]

## Dynamic actor bodies meet at the sum of their authored footprints (14 for
## the ranger and 16 for a normal enemy).  The melee action must therefore
## trigger at the same center distance that soft separation can actually
## reach; otherwise the planner keeps requesting inward movement forever.
const MELEE_RING_RADIUS := 20.0
const MELEE_ATTACK_RANGE := 30.25
const MELEE_SLOT_COUNT := 12
## Move-intent ticks without real progress before a melee re-slots to its own
## side of the room (see encounter_director's stuck clock).
const MELEE_STUCK_ESCAPE_TICKS := 40
const MELEE_SEPARATION_RADIUS := 28.0
const MELEE_SEPARATION_WEIGHT := 0.85
const MELEE_SPEED_SCALE := 1.0

const CHARGER_LAUNCH_MIN_RANGE := 88.0
const CHARGER_LAUNCH_MAX_RANGE := 190.0
const CHARGER_TOO_CLOSE_RANGE := 62.0
const CHARGER_CONTACT_RADIUS := 14.0
const CHARGER_SPEED_SCALE := 1.0
const CHARGER_CLOSE_STRAFE_WEIGHT := 0.65

const FAN_ENTER_MIN_RANGE := 132.0
const FAN_ENTER_MAX_RANGE := 220.0
const FAN_EXIT_MIN_RANGE := 112.0
const FAN_EXIT_MAX_RANGE := 242.0
const FAN_ATTACK_MIN_RANGE := 128.0
## Fan attacks have one authored reach. Planning, the frozen runtime shape and
## its later presentation/resolution all derive from this action rule.
const FAN_ATTACK_RADIUS := 175.0
const FAN_ATTACK_MAX_RANGE := FAN_ATTACK_RADIUS
const FAN_ATTACK_HALF_ANGLE := deg_to_rad(32.0)
const FAN_STRAFE_WEIGHT := 0.72
## Outside the authored attack radius, keep an obvious orbit but bias each
## hold step inward so a stationary target cannot keep a fan at empty range.
const FAN_INWARD_STRAFE_WEIGHT := 0.45
const FAN_SPEED_SCALE := 0.82

const CANDIDATE_LOOKAHEAD := 34.0
const ARENA_OUTSIDE_PENALTY := 10000.0
const CROWD_OVERLAP_PENALTY := 640.0
const ACTIVE_HAZARD_PENALTY := 2600.0
const WARNING_HAZARD_PENALTY := 520.0
const DIRECTION_DEVIATION_WEIGHT := 12.0
const GEOMETRY_STEP_LOSS_PENALTY := 20000.0
const GEOMETRY_BLOCKED_PENALTY := 1000000.0
const GEOMETRY_BLOCKED_DISPLACEMENT := 0.01
## Authored static blockers (ruins, gates, the tower) steer candidates the
## same way hazards do: approaching the blocker's padded shape is expensive,
## glancing contact stays affordable so crowded rooms keep moving.
const STATIC_BLOCKER_PENALTY := 2600.0
const STATIC_BLOCKER_MARGIN := 26.0
const QUANTIZATION_STEP := 0.001


func plan(snapshot: Variant) -> Dictionary:
	var error := _snapshot_error(snapshot)
	if not error.is_empty():
		return {"ok": false, "intents": [], "error": error}

	var safe_snapshot: Dictionary = (snapshot as Dictionary).duplicate(true)
	var normalized_geometry: Dictionary = ArenaGeometry.normalize(safe_snapshot["walkable_geometry"])
	safe_snapshot["walkable_geometry"] = normalized_geometry["value"]
	var sorted_enemies: Array = safe_snapshot["enemies"].duplicate(true)
	sorted_enemies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["entity_id"]) < int(b["entity_id"]))
	safe_snapshot["enemies"] = sorted_enemies

	# Phase one is deliberately independent of lane ownership: every enemy gets
	# the intent it would request when planned alone against the same snapshot.
	var candidate_intents: Array[Dictionary] = []
	for enemy: Dictionary in sorted_enemies:
		candidate_intents.append(_plan_enemy(safe_snapshot, enemy))

	# Phase two deterministically grants ordinary action lanes in entity order.
	# Existing windup/active actors reserve their kind before new candidates are
	# considered; recovery remains locked but releases the lane for a waiter.
	var occupied_lanes := _occupied_action_lanes(sorted_enemies)
	var intents: Array[Dictionary] = []
	for index in sorted_enemies.size():
		var enemy: Dictionary = sorted_enemies[index]
		var intent: Dictionary = candidate_intents[index]
		if _uses_action_lane(enemy) and not (StringName(enemy["action_state"]) in LOCKED_ACTION_STATES):
			var lane_key := String(enemy["kind_id"])
			var fan_outside_attack_radius := lane_key == KIND_FAN and Vector2(enemy["position"]).distance_to(Vector2(safe_snapshot["player_position"])) > FAN_ATTACK_RADIUS
			if occupied_lanes.has(lane_key) and (not String(intent.get("request_action", "")).is_empty() or fan_outside_attack_radius):
				intent = _action_lane_wait_intent(safe_snapshot, enemy)
			elif not String(intent.get("request_action", "")).is_empty():
				occupied_lanes[lane_key] = true
		intents.append(_normalized_intent(intent))
	return {"ok": true, "intents": intents, "error": ""}


func _occupied_action_lanes(enemies: Array) -> Dictionary:
	var occupied := {}
	for enemy_value: Variant in enemies:
		var enemy: Dictionary = enemy_value
		if not _uses_action_lane(enemy) or float(enemy["health"]) <= 0.0:
			continue
		var state := StringName(enemy["action_state"])
		if state == &"windup" or state == &"active":
			occupied[String(enemy["kind_id"])] = true
	return occupied


func _uses_action_lane(enemy: Dictionary) -> bool:
	return String(enemy["kind_id"]) in [KIND_MELEE, KIND_CHARGER, KIND_FAN]


func _action_lane_wait_intent(snapshot: Dictionary, enemy: Dictionary) -> Dictionary:
	match String(enemy["kind_id"]):
		KIND_MELEE:
			return _melee_between_actions_intent(snapshot, enemy, "melee_action_lane_occupied")
		KIND_CHARGER:
			return _charger_setup_intent(snapshot, enemy, "charger_action_lane_occupied")
		KIND_FAN:
			var distance := Vector2(enemy["position"]).distance_to(Vector2(snapshot["player_position"]))
			return _fan_strafe_intent(snapshot, enemy, "fan_action_lane_occupied", distance > FAN_ATTACK_RADIUS)
	return _idle_intent(int(enemy["entity_id"]), "action_lane_occupied")


func score_candidate_direction(snapshot: Dictionary, enemy: Dictionary, desired_direction: Vector2, candidate_direction: Vector2) -> float:
	var direction := candidate_direction.normalized() if not candidate_direction.is_zero_approx() else Vector2.ZERO
	var desired := desired_direction.normalized() if not desired_direction.is_zero_approx() else Vector2.ZERO
	var position := Vector2(enemy["position"])
	var raw_candidate := position + direction * CANDIDATE_LOOKAHEAD
	var score := (1.0 - clampf(direction.dot(desired), -1.0, 1.0)) * DIRECTION_DEVIATION_WEIGHT
	var arena: Rect2 = snapshot["arena_rect"]
	if not arena.has_point(raw_candidate):
		score += ARENA_OUTSIDE_PENALTY + _distance_outside_rect(raw_candidate, arena)
	for other_value: Variant in snapshot["enemies"]:
		var other: Dictionary = other_value
		if int(other["entity_id"]) == int(enemy["entity_id"]) or float(other["health"]) <= 0.0:
			continue
		var distance := raw_candidate.distance_to(Vector2(other["position"]))
		if distance < MELEE_SEPARATION_RADIUS:
			score += (MELEE_SEPARATION_RADIUS - distance) * CROWD_OVERLAP_PENALTY / MELEE_SEPARATION_RADIUS
	for hazard_value: Variant in snapshot.get("hazards", []):
		var hazard: Dictionary = hazard_value
		if hazard.has("active_geometry") and _shape_contains(hazard["active_geometry"], raw_candidate):
			score += ACTIVE_HAZARD_PENALTY
		if hazard.has("warning_geometry") and _shape_contains(hazard["warning_geometry"], raw_candidate):
			score += WARNING_HAZARD_PENALTY
	for blocker_value: Variant in snapshot.get("static_blockers", []):
		var blocker: Dictionary = blocker_value
		var blocker_center: Variant = blocker.get("center", null)
		if not blocker_center is Vector2:
			continue
		var clearance := float(blocker.get("radius", 0.0)) + STATIC_BLOCKER_MARGIN
		var blocker_distance := raw_candidate.distance_to(blocker_center)
		var points: Variant = blocker.get("points", null)
		if points is PackedVector2Array and points.size() >= 3:
			clearance = STATIC_BLOCKER_MARGIN
			blocker_distance = INF
			if Geometry2D.is_point_in_polygon(raw_candidate, points):
				blocker_distance = 0.0
			else:
				for edge: int in points.size():
					var nearest := Geometry2D.get_closest_point_to_segment(raw_candidate, points[edge], points[(edge + 1) % points.size()])
					blocker_distance = minf(blocker_distance, raw_candidate.distance_to(nearest))
		if blocker_distance < clearance:
			score += STATIC_BLOCKER_PENALTY * (1.0 - blocker_distance / clearance)

	var projection: Dictionary = ArenaGeometry.project(raw_candidate, snapshot["walkable_geometry"])
	if not bool(projection["ok"]):
		return score + GEOMETRY_BLOCKED_PENALTY
	var actual_displacement := position.distance_to(Vector2(projection["position"]))
	if actual_displacement <= GEOMETRY_BLOCKED_DISPLACEMENT:
		return score + GEOMETRY_BLOCKED_PENALTY
	var swallowed_distance := maxf(0.0, CANDIDATE_LOOKAHEAD - actual_displacement)
	if swallowed_distance > 0.0:
		score += swallowed_distance / CANDIDATE_LOOKAHEAD * GEOMETRY_STEP_LOSS_PENALTY
	return score


func choose_candidate_direction(snapshot: Dictionary, enemy: Dictionary, desired_direction: Vector2) -> Vector2:
	if desired_direction.is_zero_approx():
		return Vector2.ZERO
	var desired := desired_direction.normalized()
	var best_direction := desired
	var best_score := INF
	var stable_sign := 1 if posmod(int(enemy["entity_id"]), 2) == 0 else -1
	var candidates: Array[Vector2] = ArenaGeometry.candidate_directions(desired, stable_sign)
	for candidate: Vector2 in candidates:
		var score := score_candidate_direction(snapshot, enemy, desired, candidate)
		if score < best_score:
			best_score = score
			best_direction = candidate
	return best_direction.normalized()


func _plan_enemy(snapshot: Dictionary, enemy: Dictionary) -> Dictionary:
	var entity_id := int(enemy["entity_id"])
	if float(enemy["health"]) <= 0.0:
		return _idle_intent(entity_id, "defeated")
	if StringName(enemy["action_state"]) in LOCKED_ACTION_STATES:
		return _idle_intent(entity_id, "action_locked")
	match String(enemy["kind_id"]):
		KIND_MELEE:
			return _plan_melee(snapshot, enemy)
		KIND_CHARGER:
			return _plan_charger(snapshot, enemy)
		KIND_FAN:
			return _plan_fan(snapshot, enemy)
		KIND_COLOSSUS:
			return _plan_colossus(snapshot, enemy)
	return _idle_intent(entity_id, "unsupported_kind")


func _plan_melee(snapshot: Dictionary, enemy: Dictionary) -> Dictionary:
	var player: Vector2 = snapshot["player_position"]
	var position: Vector2 = enemy["position"]
	var to_player := player - position
	var distance := to_player.length()
	if distance <= MELEE_ATTACK_RANGE:
		if not _action_ready(snapshot, enemy):
			return _melee_between_actions_intent(snapshot, enemy, "melee_reposition_between_attacks")
		return _action_intent(int(enemy["entity_id"]), "melee_attack", to_player, "melee_in_range")

	var slot_index := posmod(int(enemy["entity_id"]), MELEE_SLOT_COUNT)
	var slot_reason := "melee_ring_slot"
	var stuck := int(enemy.get("stuck_ticks", 0))
	var desired := Vector2.ZERO
	if stuck >= MELEE_STUCK_ESCAPE_TICKS:
		var ring_geometry := (snapshot.get("walkable_geometry", {}) as Dictionary)
		var ring_center: Variant = ring_geometry.get("center", null)
		if String(ring_geometry.get("kind", "")) == "ring" and ring_center is Vector2:
			## In an annulus room the hole cuts every straight line across: the
			## only real path is the corridor itself. A trapped melee walks the
			## ring tangent toward the player's bearing instead of re-picking
			## slots that all ask for a hole crossing.
			var center: Vector2 = ring_center
			var to_enemy := position - center
			var angle_diff := wrapf((player - center).angle() - to_enemy.angle(), -PI, PI)
			var tangent := to_enemy.normalized().rotated((1.0 if angle_diff >= 0.0 else -1.0) * PI * 0.5)
			desired = tangent * MELEE_RING_RADIUS
			slot_reason = "melee_annulus_escape"
		else:
			## The fixed ring slot can sit on the far side of an authored blocker
			## pile, which the 34u local steering cannot round. A trapped enemy
			## re-slots to the wedge nearest its own bearing — always on its side
			## of the obstacle — and walks one slot further each escape period so
			## a still-blocked side slot keeps rotating.
			var bearing := (position - player).angle()
			var nearest := posmod(int(round(bearing / (TAU / float(MELEE_SLOT_COUNT)))), MELEE_SLOT_COUNT)
			slot_index = posmod(nearest + stuck / MELEE_STUCK_ESCAPE_TICKS - 1, MELEE_SLOT_COUNT)
			slot_reason = "melee_escape_slot"
	if desired.is_zero_approx():
		var slot := player + Vector2.RIGHT.rotated(TAU * float(slot_index) / float(MELEE_SLOT_COUNT)) * MELEE_RING_RADIUS
		desired = slot - position
	var separation := Vector2.ZERO
	for other_value: Variant in snapshot["enemies"]:
		var other: Dictionary = other_value
		if int(other["entity_id"]) == int(enemy["entity_id"]) or float(other["health"]) <= 0.0:
			continue
		var away := position - Vector2(other["position"])
		var gap := away.length()
		if gap > 0.0001 and gap < MELEE_SEPARATION_RADIUS:
			separation += away.normalized() * (1.0 - gap / MELEE_SEPARATION_RADIUS)
	desired += separation * MELEE_RING_RADIUS * MELEE_SEPARATION_WEIGHT
	return _move_intent(snapshot, enemy, desired, MELEE_SPEED_SCALE, slot_reason)


func _plan_charger(snapshot: Dictionary, enemy: Dictionary) -> Dictionary:
	var player: Vector2 = snapshot["player_position"]
	var position: Vector2 = enemy["position"]
	var to_player := player - position
	var distance := to_player.length()
	if distance >= CHARGER_LAUNCH_MIN_RANGE and distance <= CHARGER_LAUNCH_MAX_RANGE and _action_ready(snapshot, enemy):
		var contact_projection: Dictionary = ArenaGeometry.project(player, snapshot["walkable_geometry"])
		if not bool(contact_projection.get("ok", false)):
			return _charger_setup_intent(snapshot, enemy, "charger_contact_invalid")
		var contact_point: Vector2 = contact_projection.get("position", Vector2.ZERO)
		if player.distance_to(contact_point) > CHARGER_CONTACT_RADIUS:
			return _charger_setup_intent(snapshot, enemy, "charger_contact_unreachable")
		var path: Dictionary = ArenaGeometry.line_segment_walkable(position, contact_point, snapshot["walkable_geometry"])
		if not bool(path.get("ok", false)) or not bool(path.get("walkable", false)):
			return _charger_setup_intent(snapshot, enemy, "charger_path_blocked" if bool(path.get("ok", false)) else "charger_path_invalid")
		var contact_delta := contact_point - position
		var action_distance := _quantize(contact_delta.length())
		var serialized_direction := _quantized_vector(contact_delta.normalized())
		if action_distance <= 0.0 or serialized_direction.is_zero_approx():
			return _charger_setup_intent(snapshot, enemy, "charger_contact_invalid")
		# Main normalizes the serialized direction before moving. Reconstruct that
		# exact endpoint here so quantization cannot turn a valid tangent into a
		# live path that clips the ring or misses the contact tolerance.
		var execution_endpoint := position + serialized_direction.normalized() * action_distance
		if execution_endpoint.distance_to(player) > CHARGER_CONTACT_RADIUS:
			return _charger_setup_intent(snapshot, enemy, "charger_contact_unreachable")
		var execution_path: Dictionary = ArenaGeometry.line_segment_walkable(position, execution_endpoint, snapshot["walkable_geometry"])
		if not bool(execution_path.get("ok", false)) or not bool(execution_path.get("walkable", false)):
			return _charger_setup_intent(snapshot, enemy, "charger_path_blocked" if bool(execution_path.get("ok", false)) else "charger_path_invalid")
		return _action_intent(int(enemy["entity_id"]), "charge", contact_delta, "charger_launch_band", action_distance)
	if distance > CHARGER_LAUNCH_MAX_RANGE:
		return _move_intent(snapshot, enemy, to_player, CHARGER_SPEED_SCALE, "charger_approach")
	var away := -to_player.normalized() if distance > 0.0001 else _stable_axis(int(enemy["entity_id"]))
	var strafe := Vector2(-away.y, away.x) * _parity_sign(int(enemy["entity_id"]))
	if distance < CHARGER_TOO_CLOSE_RANGE:
		var escape := away + strafe * CHARGER_CLOSE_STRAFE_WEIGHT
		return _move_intent(snapshot, enemy, escape, CHARGER_SPEED_SCALE, "charger_create_space")
	return _charger_setup_intent(snapshot, enemy, "charger_strafe_for_band")


func _plan_fan(snapshot: Dictionary, enemy: Dictionary) -> Dictionary:
	var player: Vector2 = snapshot["player_position"]
	var position: Vector2 = enemy["position"]
	var to_player := player - position
	var distance := to_player.length()
	var holding := String(enemy["action_state"]) == "range_hold"
	var minimum := FAN_EXIT_MIN_RANGE if holding else FAN_ENTER_MIN_RANGE
	var maximum := FAN_EXIT_MAX_RANGE if holding else FAN_ENTER_MAX_RANGE
	if distance < minimum:
		return _move_intent(snapshot, enemy, -to_player, FAN_SPEED_SCALE, "fan_retreat")
	if distance > maximum:
		return _move_intent(snapshot, enemy, to_player, FAN_SPEED_SCALE, "fan_approach")
	if distance >= FAN_ATTACK_MIN_RANGE and distance <= FAN_ATTACK_RADIUS and _action_ready(snapshot, enemy):
		return _action_intent(int(enemy["entity_id"]), "fan_attack", to_player, "fan_legal_band")
	return _fan_strafe_intent(snapshot, enemy, "fan_strafe_hold", distance > FAN_ATTACK_RADIUS)


static func fan_attack_shape(origin: Vector2, direction: Vector2) -> Dictionary:
	var normalized_direction := direction.normalized()
	if normalized_direction.is_zero_approx():
		normalized_direction = Vector2.RIGHT
	return {
		"type": "fan",
		"origin": origin,
		"direction": normalized_direction,
		"half_angle": FAN_ATTACK_HALF_ANGLE,
		"radius": FAN_ATTACK_RADIUS,
	}


static func fan_attack_contains(shape: Dictionary, point: Vector2) -> bool:
	if String(shape.get("type", "")) != "fan":
		return false
	var origin: Vector2 = shape.get("origin", Vector2.ZERO)
	var direction: Vector2 = shape.get("direction", Vector2.ZERO)
	if direction.is_zero_approx():
		return false
	var offset := point - origin
	return offset.length() <= float(shape.get("radius", 0.0)) and (offset == Vector2.ZERO or absf(direction.angle_to(offset.normalized())) <= float(shape.get("half_angle", 0.0)))


func _melee_between_actions_intent(snapshot: Dictionary, enemy: Dictionary, reason: String) -> Dictionary:
	var to_player := Vector2(snapshot["player_position"]) - Vector2(enemy["position"])
	var radial := to_player.normalized() if not to_player.is_zero_approx() else _stable_axis(int(enemy["entity_id"]))
	var tangent := radial.rotated(_parity_sign(int(enemy["entity_id"])) * PI * 0.5)
	return _move_intent(snapshot, enemy, tangent, 0.55, reason)


func _charger_setup_intent(snapshot: Dictionary, enemy: Dictionary, reason: String) -> Dictionary:
	var to_player := Vector2(snapshot["player_position"]) - Vector2(enemy["position"])
	var distance := to_player.length()
	var away := -to_player.normalized() if distance > 0.0001 else _stable_axis(int(enemy["entity_id"]))
	var strafe := Vector2(-away.y, away.x) * _parity_sign(int(enemy["entity_id"]))
	var setup := strafe + away * CHARGER_CLOSE_STRAFE_WEIGHT
	return _move_intent(snapshot, enemy, setup, CHARGER_SPEED_SCALE, reason)


func _fan_strafe_intent(snapshot: Dictionary, enemy: Dictionary, reason: String, approach_attack_range: bool = false) -> Dictionary:
	var to_player := Vector2(snapshot["player_position"]) - Vector2(enemy["position"])
	var distance := to_player.length()
	var radial := to_player.normalized() if distance > 0.0001 else _stable_axis(int(enemy["entity_id"]))
	var strafe := Vector2(-radial.y, radial.x) * _parity_sign(int(enemy["entity_id"]))
	var desired := strafe * FAN_STRAFE_WEIGHT
	if approach_attack_range:
		desired += radial * FAN_INWARD_STRAFE_WEIGHT
	return _move_intent(snapshot, enemy, desired, FAN_SPEED_SCALE, reason)


func _plan_colossus(snapshot: Dictionary, enemy: Dictionary) -> Dictionary:
	var player: Vector2 = snapshot["player_position"]
	var direction := player - Vector2(enemy["position"])
	var action := "slam"
	if String(enemy["phase"]) == "awakened":
		var cycle := [&"slam", &"sweep", &"lane"]
		action = String(cycle[posmod(int(enemy["next_action_index"]), cycle.size())])
	return _action_intent(int(enemy["entity_id"]), action, direction, "colossus_cycle")


func _action_ready(snapshot: Dictionary, enemy: Dictionary) -> bool:
	return int(snapshot["tick"]) >= int(enemy.get("next_action_ready_tick", 0))


func _move_intent(snapshot: Dictionary, enemy: Dictionary, desired: Vector2, speed_scale: float, reason: String) -> Dictionary:
	var direction := choose_candidate_direction(snapshot, enemy, desired)
	return {
		"entity_id": int(enemy["entity_id"]),
		"move_direction": direction,
		"speed_scale": speed_scale,
		"request_action": "",
		"action_direction": Vector2.ZERO,
		"action_distance": 0.0,
		"reason": reason,
	}


func _action_intent(entity_id: int, action: String, direction: Vector2, reason: String, action_distance: float = 0.0) -> Dictionary:
	return {
		"entity_id": entity_id,
		"move_direction": Vector2.ZERO,
		"speed_scale": 0.0,
		"request_action": action,
		"action_direction": direction.normalized() if not direction.is_zero_approx() else _stable_axis(entity_id),
		"action_distance": action_distance,
		"reason": reason,
	}


func _idle_intent(entity_id: int, reason: String) -> Dictionary:
	return {
		"entity_id": entity_id,
		"move_direction": Vector2.ZERO,
		"speed_scale": 0.0,
		"request_action": "",
		"action_direction": Vector2.ZERO,
		"action_distance": 0.0,
		"reason": reason,
	}


func _normalized_intent(intent: Dictionary) -> Dictionary:
	var move := Vector2(intent.get("move_direction", Vector2.ZERO))
	var action := Vector2(intent.get("action_direction", Vector2.ZERO))
	if move.length_squared() > 1.0:
		move = move.normalized()
	if action.length_squared() > 1.0:
		action = action.normalized()
	var request_action := String(intent.get("request_action", ""))
	var action_distance_value: Variant = intent.get("action_distance", 0.0)
	var action_distance := float(action_distance_value) if _valid_number(action_distance_value) else 0.0
	var reason := String(intent.get("reason", "invalid_intent"))
	if request_action == "charge" and action_distance <= 0.0:
		request_action = ""
		action = Vector2.ZERO
		reason = "invalid_charge_distance"
	elif request_action != "charge":
		action_distance = 0.0
	return {
		"entity_id": int(intent.get("entity_id", -1)),
		"move_direction": _quantized_vector(move),
		"speed_scale": _quantize(clampf(float(intent.get("speed_scale", 0.0)), 0.0, 1.0)),
		"request_action": request_action,
		"action_direction": _quantized_vector(action),
		"action_distance": _quantize(action_distance),
		"reason": reason,
	}


func _snapshot_error(snapshot: Variant) -> String:
	if not (snapshot is Dictionary):
		return "snapshot_not_dictionary"
	var data: Dictionary = snapshot
	for key in ["snapshot_version", "tick", "player_position", "arena_rect", "walkable_geometry", "enemies"]:
		if not data.has(key):
			return "missing_%s" % key
	if not (data["snapshot_version"] is int) or int(data["snapshot_version"]) != SNAPSHOT_VERSION:
		return "unsupported_snapshot_version"
	if not (data["tick"] is int) or int(data["tick"]) < 0:
		return "invalid_tick"
	if not _valid_vector(data["player_position"]):
		return "invalid_player_position"
	if not _valid_rect(data["arena_rect"]):
		return "invalid_arena_rect"
	var normalized_geometry: Dictionary = ArenaGeometry.normalize(data["walkable_geometry"])
	if not bool(normalized_geometry["ok"]):
		return "invalid_walkable_geometry_%s" % String(normalized_geometry["error"])
	if Rect2(normalized_geometry["value"]["bounds"]) != Rect2(data["arena_rect"]):
		return "walkable_geometry_bounds_mismatch"
	if not (data["enemies"] is Array):
		return "invalid_enemies"
	if data.has("hazards"):
		if not (data["hazards"] is Array):
			return "invalid_hazards"
		for hazard_value: Variant in data["hazards"]:
			var hazard_error := _hazard_error(hazard_value)
			if not hazard_error.is_empty():
				return hazard_error
	var ids := {}
	for enemy_value: Variant in data["enemies"]:
		var enemy_error := _enemy_error(enemy_value)
		if not enemy_error.is_empty():
			return enemy_error
		var entity_id := int((enemy_value as Dictionary)["entity_id"])
		if ids.has(entity_id):
			return "duplicate_entity_id"
		ids[entity_id] = true
	return ""


func _enemy_error(enemy_value: Variant) -> String:
	if not (enemy_value is Dictionary):
		return "enemy_not_dictionary"
	var enemy: Dictionary = enemy_value
	for key in ["entity_id", "kind_id", "position", "action_state", "health"]:
		if not enemy.has(key):
			return "enemy_missing_%s" % key
	if not (enemy["entity_id"] is int) or int(enemy["entity_id"]) <= 0:
		return "invalid_entity_id"
	if not (enemy["kind_id"] is String or enemy["kind_id"] is StringName) or String(enemy["kind_id"]) not in [KIND_MELEE, KIND_CHARGER, KIND_FAN, KIND_COLOSSUS]:
		return "invalid_kind_id"
	if not _valid_vector(enemy["position"]):
		return "invalid_enemy_position"
	if not (enemy["action_state"] is String or enemy["action_state"] is StringName) or StringName(enemy["action_state"]) not in VALID_ACTION_STATES:
		return "invalid_action_state"
	if not _valid_number(enemy["health"]) or float(enemy["health"]) < 0.0:
		return "invalid_health"
	if enemy.has("facing") and (not _valid_vector(enemy["facing"]) or Vector2(enemy["facing"]).is_zero_approx()):
		return "invalid_facing"
	if enemy.has("next_action_ready_tick") and (not enemy["next_action_ready_tick"] is int or int(enemy["next_action_ready_tick"]) < 0):
		return "invalid_next_action_ready_tick"
	if String(enemy["kind_id"]) == KIND_COLOSSUS:
		if not enemy.has("phase") or String(enemy["phase"]) not in ["sealed", "awakened"]:
			return "invalid_colossus_phase"
		if not enemy.has("next_action_index") or not (enemy["next_action_index"] is int) or int(enemy["next_action_index"]) < 0:
			return "invalid_colossus_next_action_index"
	return ""


func _hazard_error(hazard_value: Variant) -> String:
	if not (hazard_value is Dictionary):
		return "hazard_not_dictionary"
	var hazard: Dictionary = hazard_value
	if not hazard.has("active_geometry") and not hazard.has("warning_geometry"):
		return "hazard_missing_geometry"
	for key in ["active_geometry", "warning_geometry"]:
		if hazard.has(key) and not _valid_shape(hazard[key]):
			return "invalid_%s" % key
	return ""


func _valid_shape(value: Variant) -> bool:
	if not (value is Dictionary):
		return false
	var shape: Dictionary = value
	match String(shape.get("shape", "")):
		"circle":
			return _valid_vector(shape.get("center")) and _valid_number(shape.get("radius")) and float(shape["radius"]) > 0.0
		"rect":
			return _valid_rect(shape.get("rect"))
	return false


func _shape_contains(shape_value: Variant, point: Vector2) -> bool:
	var shape: Dictionary = shape_value
	if String(shape["shape"]) == "circle":
		return point.distance_squared_to(Vector2(shape["center"])) <= pow(float(shape["radius"]), 2.0)
	return Rect2(shape["rect"]).has_point(point)


func _valid_vector(value: Variant) -> bool:
	return value is Vector2 and is_finite((value as Vector2).x) and is_finite((value as Vector2).y)


func _valid_rect(value: Variant) -> bool:
	return value is Rect2 and _valid_vector((value as Rect2).position) and _valid_vector((value as Rect2).size) and (value as Rect2).size.x > 0.0 and (value as Rect2).size.y > 0.0


func _valid_number(value: Variant) -> bool:
	return (value is int or value is float) and not (value is bool) and is_finite(float(value))


func _distance_outside_rect(point: Vector2, rect: Rect2) -> float:
	var nearest := Vector2(clampf(point.x, rect.position.x, rect.end.x), clampf(point.y, rect.position.y, rect.end.y))
	return point.distance_to(nearest)


func _stable_axis(entity_id: int) -> Vector2:
	return Vector2.RIGHT if posmod(entity_id, 2) == 0 else Vector2.LEFT


func _parity_sign(entity_id: int) -> float:
	return 1.0 if posmod(entity_id, 2) == 0 else -1.0


func _quantized_vector(value: Vector2) -> Vector2:
	return Vector2(_quantize(value.x), _quantize(value.y))


func _quantize(value: float) -> float:
	return snappedf(value, QUANTIZATION_STEP)
