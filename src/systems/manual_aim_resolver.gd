class_name ManualAimResolver
extends RefCounted

## Pure-data pointer target selection for Manual combat. Selection uses the
## same deterministic body geometry exposed by target_anchor/target_radius.

const KIND_COLOSSUS := "threshold_colossus"
const NORMAL_ANCHOR_OFFSET := Vector2(0.0, -22.0)
const NORMAL_RADIUS := 34.0
const BOSS_ANCHOR_OFFSET := Vector2(0.0, -74.0)
const BOSS_RADIUS := 92.0


func resolve_pointer(
	pointer_gameplay: Variant,
	player_position: Variant,
	targeting_distance: Variant,
	candidates: Variant
) -> Dictionary:
	if not _valid_vector(pointer_gameplay):
		return _failure("invalid_pointer_gameplay")
	if not _valid_vector(player_position):
		return _failure("invalid_player_position")
	if not _valid_number(targeting_distance) or float(targeting_distance) < 0.0:
		return _failure("invalid_targeting_distance")
	if not (candidates is Array):
		return _failure("invalid_candidates")

	for candidate_value: Variant in candidates:
		var error := _candidate_error(candidate_value)
		if not error.is_empty():
			return _failure(error)

	var pointer: Vector2 = pointer_gameplay
	var best_candidate: Dictionary = {}
	var best_anchor := Vector2.ZERO
	var best_radius := 0.0
	var best_score := INF
	var best_entity_id := 0
	for candidate_value: Variant in candidates:
		var candidate: Dictionary = candidate_value
		if float(candidate["health"]) <= 0.0:
			continue
		var anchor := _anchor_for_valid_candidate(candidate)
		var radius := _radius_for_valid_candidate(candidate)
		var distance_squared := pointer.distance_squared_to(anchor)
		if distance_squared > radius * radius:
			continue
		var normalized_squared := distance_squared / (radius * radius)
		var entity_id := int(candidate["entity_id"])
		if normalized_squared < best_score or (normalized_squared == best_score and entity_id < best_entity_id):
			best_candidate = candidate
			best_anchor = anchor
			best_radius = radius
			best_score = normalized_squared
			best_entity_id = entity_id

	if best_candidate.is_empty():
		return _failure("no_pointer_target")

	var player: Vector2 = player_position
	var target_position: Vector2 = best_candidate["position"]
	var aim_delta := target_position - player
	var in_range := player.distance_squared_to(target_position) <= pow(float(targeting_distance), 2.0)
	return {
		"ok": true,
		"target_entity_id": best_entity_id,
		"aim_direction": aim_delta.normalized() if not aim_delta.is_zero_approx() else Vector2.ZERO,
		"pointer_gameplay": pointer,
		"target_anchor": best_anchor,
		"target_radius": best_radius,
		"in_range": in_range,
		"reason": "ok" if in_range else "target_out_of_range",
	}


func target_anchor(candidate: Variant) -> Vector2:
	if not _candidate_error(candidate).is_empty():
		return Vector2.ZERO
	return _anchor_for_valid_candidate(candidate as Dictionary)


func target_radius(candidate: Variant) -> float:
	if not _candidate_error(candidate).is_empty():
		return 0.0
	return _radius_for_valid_candidate(candidate as Dictionary)


func _anchor_for_valid_candidate(candidate: Dictionary) -> Vector2:
	return Vector2(candidate["position"]) + (BOSS_ANCHOR_OFFSET if _is_boss(candidate) else NORMAL_ANCHOR_OFFSET)


func _radius_for_valid_candidate(candidate: Dictionary) -> float:
	return BOSS_RADIUS if _is_boss(candidate) else NORMAL_RADIUS


func _is_boss(candidate: Dictionary) -> bool:
	return String(candidate["kind_id"]) == KIND_COLOSSUS or bool(candidate.get("is_boss", false))


func _candidate_error(candidate_value: Variant) -> String:
	if not (candidate_value is Dictionary):
		return "candidate_not_dictionary"
	var candidate: Dictionary = candidate_value
	for key in ["entity_id", "kind_id", "position", "health"]:
		if not candidate.has(key):
			return "candidate_missing_%s" % key
	if not (candidate["entity_id"] is int) or int(candidate["entity_id"]) <= 0:
		return "invalid_candidate_entity_id"
	if not (candidate["kind_id"] is String or candidate["kind_id"] is StringName) or String(candidate["kind_id"]).is_empty():
		return "invalid_candidate_kind_id"
	if not _valid_vector(candidate["position"]):
		return "invalid_candidate_position"
	if not _valid_number(candidate["health"]) or float(candidate["health"]) < 0.0:
		return "invalid_candidate_health"
	if candidate.has("is_boss") and not (candidate["is_boss"] is bool):
		return "invalid_candidate_is_boss"
	return ""


func _failure(reason: String) -> Dictionary:
	return {
		"ok": false,
		"target_entity_id": 0,
		"in_range": false,
		"reason": reason,
	}


func _valid_vector(value: Variant) -> bool:
	return value is Vector2 and is_finite((value as Vector2).x) and is_finite((value as Vector2).y)


func _valid_number(value: Variant) -> bool:
	return (value is int or value is float) and not (value is bool) and is_finite(float(value))
