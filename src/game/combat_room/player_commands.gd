class_name RoomPlayerCommands
extends RefCounted

## Player command sourcing extracted from MainArena: the Manual/Auto command
## collection for the fixed tick, loot-pickup commands, the proxy snapshots and
## the typed command builders used by the command-source port. Room state stays
## owned by MainArena and is reached through the typed owner reference.

const ProxyDecisionScript = preload("res://src/systems/proxy_decision.gd")
const CombatCommandProtocolScript = preload("res://src/systems/combat_command_protocol.gd")
const CombatLootPickupProtocolScript := preload("res://src/systems/combat_loot_pickup_protocol.gd")

var _main: MainArena


func _init(main: MainArena) -> void:
	_main = main


func _simulation_collect_commands() -> Array[Dictionary]:
	var snapshot := _main.gameplay_snapshot()
	var loot_command: Dictionary = _main.input_adapter.collect_loot_pickup_command(snapshot)
	if loot_command.is_empty() and _main.selected_mode == "Auto":
		loot_command = _auto_loot_pickup_command(snapshot)
	if not loot_command.is_empty():
		_submit_loot_pickup_command(loot_command)
	if _main.automation_smoke and _main.selected_mode == "Manual":
		var result: Dictionary = _main.smoke_input_driver.decide({
			"player": _main.player_combat_state.snapshot(_main.sim_tick), "targets": _main._read_only_targets(),
			"hazards": _main.hazard_states.duplicate(true), "targeting_distance": _main.locked_targeting_distance,
			"boss": {"impact_tick": _main.boss.impact_tick, "target_shape": _main.boss.target_shape.duplicate(true)} if _main.boss != null else {},
		}, _main.command_sequence)
		_main.command_sequence = int(result.next_sequence)
		return result.commands
	return _auto_commands() if _main.selected_mode == "Auto" else _main.input_adapter.collect_commands(_main.gameplay_snapshot())


func _submit_loot_pickup_command(command: Dictionary) -> Dictionary:
	var arbitration: Dictionary = CombatLootPickupProtocolScript.arbitrate([command], _main.sim_tick, "ranger")
	var receipts: Array = arbitration.get("receipts", [])
	var receipt: Dictionary = receipts[0].duplicate(true) if not receipts.is_empty() and receipts[0] is Dictionary else {"status": "rejected", "reason": "invalid_receipt", "command": command.duplicate(true)}
	if String(receipt.get("status", "")) == CombatLootPickupProtocolScript.STATUS_ACCEPTED:
		var normalized: Dictionary = receipt.get("command", {})
		var room_receipt := _main.request_loot_pickup(String(normalized.get("loot_entity_id", "")))
		receipt["room_receipt"] = room_receipt.duplicate(true)
		if not bool(room_receipt.get("accepted", false)) and _main.selected_mode == "Manual" and _main.presentation != null and _main.presentation.feedback != null:
			_main.presentation.feedback.show_input_feedback("Loot out of reach · Move closer, then press F", _main.sim_tick)
	_main.last_loot_pickup_command_receipt = receipt.duplicate(true)
	return _main.last_loot_pickup_command_receipt.duplicate(true)


func _auto_loot_pickup_command(snapshot: Dictionary) -> Dictionary:
	if not bool(snapshot.get("in_arena", false)) or (bool(snapshot.get("battle_over", false)) and not bool(snapshot.get("battle_victory", false))):
		return {}
	var room_loot_value: Variant = snapshot.get("room_loot", {})
	if not room_loot_value is Dictionary:
		return {}
	var room_loot: Dictionary = room_loot_value
	var pending_ids: Dictionary = {}
	for pending_value: Variant in room_loot.get("pending_pickup_requests", []):
		if pending_value is Dictionary:
			pending_ids[String((pending_value as Dictionary).get("loot_entity_id", ""))] = true
	var player_position_value: Variant = snapshot.get("player_position", Vector2.ZERO)
	var player_position := player_position_value as Vector2 if player_position_value is Vector2 else Vector2.ZERO
	var nearest_id := ""
	var nearest_distance := INF
	for entity_value: Variant in room_loot.get("entities", []):
		if not entity_value is Dictionary:
			continue
		var entity: Dictionary = entity_value
		var loot_id := String(entity.get("loot_entity_id", "")).strip_edges()
		if loot_id.is_empty() or String(entity.get("state", "")) != "available" or pending_ids.has(loot_id):
			continue
		var position_value: Variant = entity.get("position", Vector2.ZERO)
		var position := position_value as Vector2 if position_value is Vector2 else Vector2.ZERO
		var radius := maxf(0.0, float(entity.get("pickup_radius", 0.0)))
		var distance := player_position.distance_squared_to(position)
		if distance > radius * radius + 0.000001:
			continue
		if distance < nearest_distance or (is_equal_approx(distance, nearest_distance) and (nearest_id.is_empty() or loot_id < nearest_id)):
			nearest_distance = distance
			nearest_id = loot_id
	if nearest_id.is_empty():
		return {}
	return _loot_pickup_command(nearest_id)


func _auto_commands() -> Array[Dictionary]:
	var observation := _public_proxy_snapshot()
	var collision_geometry := _main._collision_geometry(14.0)
	if not collision_geometry.is_empty():
		observation["walkable_geometry"] = collision_geometry
	var result: Dictionary = _main.proxy_intent_system.decide(observation, _main.command_sequence)
	if not bool(result.get("ok", false)):
		return []
	_main.command_sequence = int(result.get("next_sequence", _main.command_sequence))
	return (result.get("commands", []) as Array).duplicate(true)


func _proxy_failure_snapshot() -> Dictionary:
	if _main.proxy_intent_system == null:
		return {}
	return _main.proxy_intent_system.failure_snapshot()


func _proxy_trace_snapshot() -> Array[String]:
	if _main.proxy_intent_system == null:
		return []
	return _main.proxy_intent_system.trace_snapshot()


func _public_proxy_snapshot() -> Dictionary:
	var player := _main.player_combat_state.snapshot(_main.sim_tick)
	var public_geometry := _main._walkable_geometry(14.0).duplicate(true)
	## Public geometry describes only the space the actor may occupy. Route and
	## room identifiers remain private even if a future helper revision carries
	## spatial metadata alongside the geometric primitives.
	public_geometry.erase("layout_id")
	var observations: Array = _main.framework_resolved_proxy_build.get("observation_contract", [])
	var include_classification := "enemy.public_classification_tags" in observations
	var visible: Array[Dictionary] = []
	for enemy: CombatEnemyState in _main.enemies:
		var entry := {
			"entity_id": enemy.entity_id,
			"position": enemy.position,
			"health": enemy.health,
			## Action legality is part of enemy.basic. It reveals no barrier rule,
			## phase duration, or future opening tick.
			"targetable": _main.encounter_director.is_targetable(enemy) and _main._is_enemy_actor_active(enemy),
		}
		if include_classification:
			var classification_tags: Array[String] = []
			if enemy.is_boss:
				classification_tags.append("boss")
			if enemy.entity_id == _main.elite_entity_id:
				classification_tags.append("elite")
			if enemy.entity_id == player["marked_entity_id"]:
				classification_tags.append("marked")
			entry["classification_tags"] = classification_tags
		visible.append(entry)
	return {
		"snapshot_version": ProxyDecisionScript.SNAPSHOT_VERSION,
		"tick": _main.sim_tick,
		"actor_id": "ranger",
		"player_position": _main.player_position,
		"facing": player["player_facing"],
		"action_state": _player_authority_action_state(),
		"attack_ready_tick": _main.sim_tick + player["attack_cooldown_ticks"],
		"targeting_distance": _main.locked_targeting_distance,
		"visible_enemies": visible,
		"walkable_geometry": public_geometry,
	}


func _player_authority_action_state() -> String:
	var player := _main.player_combat_state.snapshot(_main.sim_tick)
	if player["dodge_remaining_ticks"] > 0:
		return "dodge"
	if player["dash_remaining_ticks"] > 0:
		return "dash"
	return String(player["action_phase"])


func _move_command(direction: Vector2, speed_scale: float) -> Dictionary:
	var milli := _direction_to_milli(direction)
	var result := CombatCommandProtocolScript.move(_main.sim_tick, "ranger", _main.command_sequence, milli.x, milli.y, clampi(roundi(speed_scale * 1000.0), 1, 1000))
	_main.command_sequence += 1
	return result


func _dodge_command(direction: Vector2) -> Dictionary:
	var milli := _direction_to_milli(direction)
	var result := CombatCommandProtocolScript.dodge(_main.sim_tick, "ranger", _main.command_sequence, milli.x, milli.y)
	_main.command_sequence += 1
	return result


func _cast_command(ability_id: String, target_entity_id: int, direction: Vector2 = Vector2.ZERO) -> Dictionary:
	var result: Dictionary
	if ability_id in ["dash", "piercing_arrow"]:
		var direction_milli := _direction_to_milli(direction)
		result = CombatCommandProtocolScript.cast(_main.sim_tick, "ranger", _main.command_sequence, ability_id, target_entity_id, direction_milli.x, direction_milli.y)
	else:
		result = CombatCommandProtocolScript.cast(_main.sim_tick, "ranger", _main.command_sequence, ability_id, target_entity_id)
	_main.command_sequence += 1
	return result


func _loot_pickup_command(loot_entity_id: String) -> Dictionary:
	var result := CombatLootPickupProtocolScript.make_request(_main.sim_tick, "ranger", _main.command_sequence, loot_entity_id)
	_main.command_sequence += 1
	return result


func _direction_to_milli(direction: Vector2) -> Vector2i:
	var player := _main.player_combat_state.snapshot(_main.sim_tick)
	var normalized: Vector2 = direction.normalized() if direction != Vector2.ZERO else (player["player_facing"] as Vector2).normalized()
	if normalized == Vector2.ZERO:
		normalized = Vector2.RIGHT
	return Vector2i(roundi(normalized.x * 1000.0), roundi(normalized.y * 1000.0))
