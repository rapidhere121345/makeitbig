class_name ProxyDecision
extends RefCounted

## Pure deterministic consumer of a validated ResolvedProxyBuild.

const ProxyBuild := preload("res://src/systems/proxy_build.gd")
const Protocol := preload("res://src/systems/combat_command_protocol.gd")
const WalkableGeometry := preload("res://src/systems/walkable_geometry.gd")

const SNAPSHOT_VERSION := 3
const STATE_VERSION := 1
const MOVE_SPEED_MILLI := 720
const SNAPSHOT_FIELDS: Array[String] = [
	"snapshot_version", "tick", "actor_id", "player_position", "facing",
	"action_state", "attack_ready_tick", "targeting_distance", "visible_enemies",
	"walkable_geometry",
]
const BASE_ENEMY_FIELDS: Array[String] = ["entity_id", "position", "health", "targetable"]
const CLASSIFICATION_FIELD := "classification_tags"
const CLASSIFICATION_CHANNEL := "enemy.public_classification_tags"
const CLASSIFICATION_TAGS: Array[String] = ["boss", "elite", "marked"]
const MOVEMENT_BANDS: Array[String] = ["retreat", "hold", "approach"]


static func initial_state(resolved_build: Variant) -> Dictionary:
	var normalized := ProxyBuild.normalize_resolved(resolved_build)
	if not normalized.ok:
		return {}
	var state := {"state_version": STATE_VERSION}
	for field in normalized.value.state_contract:
		match String(field):
			"target_entity_id": state[field] = 0
			"next_perception_tick": state[field] = 0
			"candidate_entity_ids": state[field] = []
			"last_committed_action": state[field] = "none"
			"movement_band": state[field] = "hold"
			_: return {}
	return state


static func decide(public_snapshot: Variant, resolved_build: Variant, prior_state: Variant, sequence_start: Variant) -> Dictionary:
	var sequence_result := _validate_sequence(sequence_start)
	if not sequence_result.ok:
		return _failure(String(sequence_result.error), 0)
	var sequence := int(sequence_start)
	var build_result := ProxyBuild.normalize_resolved(resolved_build)
	if not build_result.ok:
		return _failure(String(build_result.error), sequence)
	var build: Dictionary = build_result.value
	var snapshot_result := _normalize_snapshot(public_snapshot, build.observation_contract)
	if not snapshot_result.ok:
		return _failure(String(snapshot_result.error), sequence)
	var state_result := _normalize_state(prior_state, build)
	if not state_result.ok:
		return _failure(String(state_result.error), sequence)

	var snapshot: Dictionary = snapshot_result.value
	var state: Dictionary = state_result.value
	var perception_core := _core(build, "perception")
	var movement_core := _core(build, "movement")
	var execution_core := _core(build, "execution")
	var trace: Array[String] = []
	var target_result := _update_target(snapshot, state, perception_core, trace)
	if not target_result.ok:
		return _failure(String(target_result.error), sequence)
	var target: Dictionary = target_result.target
	var commands: Array[Dictionary] = []
	if target.is_empty():
		commands.append(Protocol.stop_move(int(snapshot.tick), String(snapshot.actor_id), sequence))
		sequence += 1
		state.movement_band = "hold"
		state.last_committed_action = "stop_move"
		trace.append("target:none")
		trace.append("movement:stop_no_target")
		trace.append("execution:no_target")
		return _success(commands, state, trace, sequence)

	var target_id := int(target.entity_id)
	var delta: Vector2 = target.position - snapshot.player_position
	var distance := delta.length()
	var target_direction := _stable_target_direction(delta, distance, snapshot.facing)
	trace.append("target:selected_%d" % target_id)
	var thresholds_result := _movement_thresholds(movement_core)
	if not thresholds_result.ok:
		return _failure(String(thresholds_result.error), sequence)
	var thresholds: Array = thresholds_result.value
	var distance_milli := roundi(distance * 1000.0)
	var targeting_distance := float(snapshot.targeting_distance)
	var retreat_enter := roundi(targeting_distance * float(thresholds[0]))
	var retreat_exit := roundi(targeting_distance * float(thresholds[1]))
	var approach_exit := roundi(targeting_distance * float(thresholds[2]))
	var approach_enter := roundi(targeting_distance * float(thresholds[3]))
	var prior_band := String(state.movement_band)
	var next_band := "hold"
	if distance_milli < retreat_enter:
		next_band = "retreat"
	elif prior_band == "retreat" and distance_milli < retreat_exit:
		next_band = "retreat"
	elif prior_band == "approach" and distance_milli > approach_exit:
		next_band = "approach"
	elif distance_milli > approach_enter:
		next_band = "approach"

	if next_band == "retreat":
		var retreat_result := _feasible_move_direction(snapshot.player_position, -target_direction, snapshot.walkable_geometry, target_id)
		if not retreat_result.ok:
			return _failure(String(retreat_result.error), sequence)
		sequence = _append_movement(commands, state, trace, snapshot, sequence, "retreat", retreat_result)
	elif next_band == "approach":
		var approach_result := _feasible_move_direction(snapshot.player_position, target_direction, snapshot.walkable_geometry, target_id)
		if not approach_result.ok:
			return _failure(String(approach_result.error), sequence)
		sequence = _append_movement(commands, state, trace, snapshot, sequence, "approach", approach_result)
	else:
		commands.append(Protocol.stop_move(int(snapshot.tick), String(snapshot.actor_id), sequence))
		sequence += 1
		state.movement_band = "hold"
		state.last_committed_action = "stop_move"
		trace.append("movement:hold")

	var ability_id := String(execution_core.capabilities.ability_id)
	var execution_reason := ""
	if distance > targeting_distance:
		execution_reason = "out_of_range"
	elif int(snapshot.attack_ready_tick) > int(snapshot.tick):
		execution_reason = "cooldown"
	elif String(snapshot.action_state) != "idle":
		execution_reason = "action_locked"
	else:
		commands.append(Protocol.cast(int(snapshot.tick), String(snapshot.actor_id), sequence, ability_id, target_id, _quantize_unit(target_direction.x), _quantize_unit(target_direction.y)))
		sequence += 1
		state.last_committed_action = ability_id
		execution_reason = "cast_skill_1"
	trace.append("execution:%s" % execution_reason)
	return _success(commands, state, trace, sequence)


static func _update_target(snapshot: Dictionary, state: Dictionary, perception_core: Dictionary, trace: Array[String]) -> Dictionary:
	var behavior := String(perception_core.behavior_id)
	var period := int(perception_core.capabilities.refresh_period_ticks)
	var enemies: Array = snapshot.visible_enemies
	var prior_target_id := int(state.target_entity_id)
	var target := _enemy_by_id(enemies, prior_target_id)
	var refresh_reason := ""
	if int(snapshot.tick) == 0:
		refresh_reason = "tick_zero"
	elif int(snapshot.tick) >= int(state.next_perception_tick):
		refresh_reason = "periodic"
	elif target.is_empty():
		if behavior == "marking_prism":
			for candidate_id in state.candidate_entity_ids:
				if int(candidate_id) == prior_target_id:
					continue
				var fallback := _enemy_by_id(enemies, int(candidate_id))
				if not fallback.is_empty():
					target = fallback
					state.target_entity_id = int(fallback.entity_id)
					trace.append("perception:fallback_candidate")
					_reset_movement_on_target_change(state, prior_target_id, trace)
					return {"ok": true, "target": target}
			refresh_reason = "candidates_missing"
		elif prior_target_id > 0:
			refresh_reason = "target_missing"

	if not refresh_reason.is_empty():
		if behavior == "marking_prism":
			var candidates := _marking_candidates(enemies, snapshot.player_position, int(perception_core.capabilities.candidate_limit))
			state.candidate_entity_ids = []
			for enemy in candidates:
				state.candidate_entity_ids.append(int(enemy.entity_id))
			target = candidates[0] if not candidates.is_empty() else {}
		else:
			target = _nearest_enemy(enemies, snapshot.player_position)
		state.target_entity_id = int(target.get("entity_id", 0))
		state.next_perception_tick = int(snapshot.tick) + period
		trace.append("perception:refresh_%s" % refresh_reason)
		_reset_movement_on_target_change(state, prior_target_id, trace)
	elif target.is_empty():
		trace.append("perception:retain_empty")
	else:
		trace.append("perception:retain_target")
	return {"ok": true, "target": target}


static func _reset_movement_on_target_change(state: Dictionary, prior_target_id: int, trace: Array[String]) -> void:
	if int(state.target_entity_id) != prior_target_id:
		state.movement_band = "hold"
		trace.append("movement:reset_target_change")


static func _marking_candidates(enemies: Array, player_position: Vector2, limit: int) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for enemy in enemies:
		candidates.append(enemy)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_priority := _classification_priority(a.classification_tags)
		var b_priority := _classification_priority(b.classification_tags)
		if a_priority != b_priority:
			return a_priority < b_priority
		var a_distance := player_position.distance_squared_to(a.position)
		var b_distance := player_position.distance_squared_to(b.position)
		if a_distance != b_distance:
			return a_distance < b_distance
		return int(a.entity_id) < int(b.entity_id)
	)
	return candidates.slice(0, mini(limit, candidates.size()))


static func _classification_priority(tags: Array) -> int:
	if "marked" in tags:
		return 0
	if "elite" in tags:
		return 1
	if "boss" in tags:
		return 2
	return 3


static func _movement_thresholds(movement_core: Dictionary) -> Dictionary:
	var caps: Dictionary = movement_core.capabilities
	if String(movement_core.behavior_id) == "direct_gait":
		return {"ok": true, "value": [caps.retreat_enter_targeting_distance_milli, caps.retreat_exit_targeting_distance_milli, caps.approach_exit_targeting_distance_milli, caps.approach_enter_targeting_distance_milli]}
	var band := String(movement_core.settings.distance_band)
	var key := "%s_band_milli" % band
	if not caps.has(key) or not caps[key] is Array:
		return {"ok": false, "error": "invalid_movement_contract"}
	return {"ok": true, "value": caps[key].duplicate(true)}


static func _append_movement(commands: Array[Dictionary], state: Dictionary, trace: Array[String], snapshot: Dictionary, sequence: int, band: String, direction_result: Dictionary) -> int:
	if bool(direction_result.no_progress):
		commands.append(Protocol.stop_move(int(snapshot.tick), String(snapshot.actor_id), sequence))
		state.last_committed_action = "stop_move"
		trace.append("movement:no_progress")
		return sequence + 1
	var direction: Vector2 = direction_result.direction
	commands.append(Protocol.move(int(snapshot.tick), String(snapshot.actor_id), sequence, _quantize_unit(direction.x), _quantize_unit(direction.y), MOVE_SPEED_MILLI))
	state.movement_band = band
	state.last_committed_action = "move"
	trace.append("movement:%s" % band)
	if bool(direction_result.detour):
		trace.append("movement:path_detour")
	return sequence + 1


static func _normalize_snapshot(value: Variant, observation_contract: Array) -> Dictionary:
	if not value is Dictionary:
		return {"ok": false, "error": "invalid_snapshot"}
	var snapshot: Dictionary = value
	if not _has_exact_fields(snapshot, SNAPSHOT_FIELDS):
		return {"ok": false, "error": "invalid_snapshot"}
	if not snapshot.snapshot_version is int or int(snapshot.snapshot_version) != SNAPSHOT_VERSION:
		return {"ok": false, "error": "wrong_snapshot_version"}
	if not snapshot.tick is int or int(snapshot.tick) < 0 or not snapshot.actor_id is String or String(snapshot.actor_id).strip_edges().is_empty():
		return {"ok": false, "error": "invalid_snapshot"}
	var position_result := _normalize_vector(snapshot.player_position)
	var facing_result := _normalize_vector(snapshot.facing)
	if not position_result.ok or not facing_result.ok or not snapshot.action_state is String or String(snapshot.action_state).is_empty():
		return {"ok": false, "error": "invalid_snapshot"}
	if not snapshot.attack_ready_tick is int or int(snapshot.attack_ready_tick) < 0 or not (snapshot.targeting_distance is int or snapshot.targeting_distance is float):
		return {"ok": false, "error": "invalid_snapshot"}
	var targeting_distance := float(snapshot.targeting_distance)
	if not _finite(targeting_distance) or targeting_distance <= 0.0 or not snapshot.visible_enemies is Array:
		return {"ok": false, "error": "invalid_snapshot"}
	var geometry_result: Dictionary = WalkableGeometry.normalize(snapshot.walkable_geometry)
	if not bool(geometry_result.get("ok", false)):
		return {"ok": false, "error": "invalid_walkable_geometry:%s" % String(geometry_result.get("error", "invalid_geometry"))}
	var allow_classification := CLASSIFICATION_CHANNEL in observation_contract
	var enemies: Array[Dictionary] = []
	var ids := {}
	for enemy_value in snapshot.visible_enemies:
		var enemy_result := _normalize_enemy(enemy_value, allow_classification)
		if not enemy_result.ok or ids.has(enemy_result.value.entity_id):
			return {"ok": false, "error": "invalid_snapshot"}
		var enemy: Dictionary = enemy_result.value
		ids[enemy.entity_id] = true
		if float(enemy.health) > 0.0 and bool(enemy.targetable):
			enemies.append(enemy)
	enemies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.entity_id) < int(b.entity_id))
	return {"ok": true, "value": {"snapshot_version": SNAPSHOT_VERSION, "tick": int(snapshot.tick), "actor_id": String(snapshot.actor_id), "player_position": position_result.value, "facing": facing_result.value, "action_state": String(snapshot.action_state), "attack_ready_tick": int(snapshot.attack_ready_tick), "targeting_distance": targeting_distance, "visible_enemies": enemies, "walkable_geometry": Dictionary(geometry_result.value).duplicate(true)}}


static func _normalize_enemy(value: Variant, allow_classification: bool) -> Dictionary:
	if not value is Dictionary:
		return {"ok": false, "value": {}}
	var enemy: Dictionary = value
	var expected: Array = BASE_ENEMY_FIELDS.duplicate()
	if allow_classification:
		expected.append(CLASSIFICATION_FIELD)
	if not _has_exact_fields(enemy, expected):
		return {"ok": false, "value": {}}
	if not enemy.entity_id is int or int(enemy.entity_id) <= 0 or not enemy.targetable is bool:
		return {"ok": false, "value": {}}
	var position_result := _normalize_vector(enemy.position)
	if not position_result.ok or not (enemy.health is int or enemy.health is float) or not _finite(float(enemy.health)):
		return {"ok": false, "value": {}}
	var normalized := {"entity_id": int(enemy.entity_id), "position": position_result.value, "health": float(enemy.health), "targetable": bool(enemy.targetable)}
	if allow_classification:
		if not enemy.classification_tags is Array:
			return {"ok": false, "value": {}}
		var tags: Array[String] = []
		for tag_value in enemy.classification_tags:
			if not tag_value is String or String(tag_value) not in CLASSIFICATION_TAGS or String(tag_value) in tags:
				return {"ok": false, "value": {}}
			tags.append(String(tag_value))
		tags.sort()
		normalized[CLASSIFICATION_FIELD] = tags
	return {"ok": true, "value": normalized}


static func _normalize_state(value: Variant, build: Dictionary) -> Dictionary:
	if not value is Dictionary:
		return {"ok": false, "error": "invalid_state"}
	var expected: Array = ["state_version"]
	expected.append_array(build.state_contract)
	var state: Dictionary = value
	if not _has_exact_fields(state, expected):
		return {"ok": false, "error": "invalid_state"}
	if not state.state_version is int or int(state.state_version) != STATE_VERSION:
		return {"ok": false, "error": "wrong_state_version"}
	if not state.target_entity_id is int or int(state.target_entity_id) < 0 or not state.next_perception_tick is int or int(state.next_perception_tick) < 0:
		return {"ok": false, "error": "invalid_state"}
	if not state.last_committed_action is String or String(state.last_committed_action) not in ["none", "move", "stop_move", Protocol.ABILITY_PIERCING_ARROW]:
		return {"ok": false, "error": "invalid_state"}
	if not state.movement_band is String or String(state.movement_band) not in MOVEMENT_BANDS:
		return {"ok": false, "error": "invalid_state"}
	var normalized := {"state_version": STATE_VERSION}
	for field in build.state_contract:
		normalized[field] = state[field].duplicate(true) if state[field] is Array or state[field] is Dictionary else state[field]
	if state.has("candidate_entity_ids"):
		if not state.candidate_entity_ids is Array or state.candidate_entity_ids.size() > 2:
			return {"ok": false, "error": "invalid_state"}
		var seen := {}
		for candidate in state.candidate_entity_ids:
			if not candidate is int or int(candidate) <= 0 or seen.has(candidate):
				return {"ok": false, "error": "invalid_state"}
			seen[candidate] = true
		if int(state.target_entity_id) > 0 and int(state.target_entity_id) not in state.candidate_entity_ids:
			return {"ok": false, "error": "invalid_state"}
	return {"ok": true, "value": normalized}


static func _core(build: Dictionary, slot: String) -> Dictionary:
	for core_value in build.cores:
		if String(core_value.slot) == slot:
			return core_value
	return {}


static func _has_exact_fields(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for field in expected:
		if not value.has(field):
			return false
	return true


static func _validate_sequence(value: Variant) -> Dictionary:
	if not value is int or int(value) < 0:
		return {"ok": false, "error": "invalid_sequence_start"}
	return {"ok": true}


static func _normalize_vector(value: Variant) -> Dictionary:
	var result := Vector2.ZERO
	if value is Vector2:
		result = value
	elif value is Dictionary:
		var data: Dictionary = value
		if not _has_exact_fields(data, ["x", "y"]) or not (data.x is int or data.x is float) or not (data.y is int or data.y is float):
			return {"ok": false}
		result = Vector2(float(data.x), float(data.y))
	else:
		return {"ok": false}
	if not _finite(result.x) or not _finite(result.y):
		return {"ok": false}
	return {"ok": true, "value": result}


static func _enemy_by_id(enemies: Array, entity_id: int) -> Dictionary:
	if entity_id <= 0:
		return {}
	for enemy in enemies:
		if int(enemy.entity_id) == entity_id:
			return enemy
	return {}


static func _nearest_enemy(enemies: Array, player_position: Vector2) -> Dictionary:
	var selected: Dictionary = {}
	var selected_distance := 0.0
	for enemy in enemies:
		var distance := player_position.distance_squared_to(enemy.position)
		if selected.is_empty() or distance < selected_distance:
			selected = enemy
			selected_distance = distance
	return selected


static func _quantize_unit(value: float) -> int:
	return clampi(roundi(value * 1000.0), -1000, 1000)


static func _feasible_move_direction(player_position: Vector2, desired_direction: Vector2, walkable_geometry: Dictionary, target_entity_id: int) -> Dictionary:
	var stable_sign := 1 if posmod(target_entity_id, 2) == 0 else -1
	var choice: Dictionary = WalkableGeometry.choose_feasible_direction(player_position, desired_direction, 24.0, walkable_geometry, stable_sign)
	if not bool(choice.get("ok", false)):
		return {"ok": false, "error": "walkable_geometry_choice_failed:%s" % String(choice.get("error", "unknown"))}
	if not WalkableGeometry._has_meaningful_progress(float(choice.actual_displacement), 24.0):
		return {"ok": true, "error": "", "direction": Vector2.ZERO, "detour": false, "no_progress": true}
	return {"ok": true, "error": "", "direction": Vector2(choice.direction), "detour": bool(choice.detour), "no_progress": false}


static func _stable_target_direction(delta: Vector2, distance: float, facing: Vector2) -> Vector2:
	if distance > 0.0:
		return delta / distance
	if facing.length() > 0.0:
		return facing.normalized()
	return Vector2.RIGHT


static func _finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)


static func _success(commands: Array[Dictionary], state: Dictionary, trace: Array[String], next_sequence: int) -> Dictionary:
	return {"ok": true, "error": "", "commands": commands.duplicate(true), "next_state": state.duplicate(true), "trace": trace.duplicate(true), "next_sequence": next_sequence}


static func _failure(error: String, next_sequence: int) -> Dictionary:
	return {"ok": false, "error": error, "commands": [], "next_state": {}, "trace": ["reject:%s" % error], "next_sequence": next_sequence}
