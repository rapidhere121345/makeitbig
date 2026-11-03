class_name CombatStateSnapshotBuilder
extends RefCounted

## Canonical authoritative snapshot builder for combat replay/state hashes.
##
## The room entry point owns lifecycle and the simulation owns tick progression;
## neither should also define which fields constitute gameplay state. This
## service reads the runtime after a committed tick, orders entity collections,
## preserves the existing replay geometry encoding and delegates the final byte ordering to CombatStateCodec.
## Class-owned keys are not listed here: the runtime's kit provides them as its
## `hash_slice`, merged at the top level. Presentation-only fields are
## intentionally absent from this snapshot.

const CombatStateCodecScript := preload("res://src/game/combat_state_codec.gd")
const RangerKitScript := preload("res://src/game/classes/ranger/ranger_kit.gd")


static func hash_runtime(runtime: Object, result: String) -> String:
	return CombatStateCodecScript.sha256_canonical(build_runtime_state(runtime, result))


static func build_runtime_state(runtime: Object, result: String, player_slice: Dictionary = {}) -> Dictionary:
	# Authority state lives on the room's RoomSession and the encounter fields on
	# its EncounterDirector; the view (MainArena) still owns the hazard domain,
	# the manual input adapter, the attack-intent edge and the walkable
	# geometry. A runtime without a session (test doubles) is its own source.
	var session := _authority(runtime)
	var director_value: Variant = _runtime_value(session, "encounter_director")
	var director: Object = director_value if director_value is Object else runtime
	var player := player_slice.duplicate(true)
	if player.is_empty():
		var domain: Variant = _runtime_value(session, "player_combat_state")
		assert(domain is PlayerCombatState, "player_combat_state is required for an authoritative snapshot")
		if domain == null:
			return {}
		player = domain.snapshot(int(_runtime_value(session, "sim_tick", 0)))
	var combat: Variant = _runtime_value(session, "combat_system")
	assert(combat is CombatSystem, "combat_system outcome authority is required for an authoritative snapshot")
	if not combat is CombatSystem:
		return {}
	var outcome: Dictionary = combat.outcome_snapshot()
	var enemy_state: Array[Dictionary] = []
	var enemy_value: Variant = _runtime_value(director, "enemies")
	var ordered_enemies: Array = (enemy_value as Array).duplicate() if enemy_value is Array else []
	ordered_enemies.sort_custom(func(left, right) -> bool: return int(left.entity_id) < int(right.entity_id))
	for enemy in ordered_enemies:
		var part_state := _enemy_parts_state(enemy)
		var enemy_entry := {
			"action_instance_id": enemy.action_instance_id,
			"action_id": enemy.action_id,
			"action_state": enemy.action_state,
			"boss": enemy.is_boss,
			"charge": CombatStateCodecScript.geometry_state(enemy.charge_origin, enemy.charge_direction, enemy.charge_length, enemy.charge_width),
			"core_open": enemy.core_open,
			"core_vulnerable": enemy.core_vulnerable,
			"entity_id": enemy.entity_id,
			"facing_x_milli": roundi(enemy.facing.x * 1000.0),
			"facing_y_milli": roundi(enemy.facing.y * 1000.0),
			"fan": CombatStateCodecScript.geometry_state(enemy.fan_origin, enemy.fan_direction, enemy.fan_radius, enemy.fan_half_angle),
			"health_milli": roundi(enemy.health * 1000.0),
			"hit_flash_until_tick": enemy.hit_flash_until_tick,
			"impact_resolved": enemy.impact_resolved,
			"impact_tick": enemy.impact_tick,
			"kind_id": enemy.kind_id,
			"maximum_health_milli": roundi(enemy.maximum_health * 1000.0),
			"left_hand_x_milli": roundi(enemy.left_hand_position.x * 1000.0),
			"left_hand_y_milli": roundi(enemy.left_hand_position.y * 1000.0),
			"motion_state": enemy.motion_state,
			"next_action_index": enemy.next_action_index,
			"next_action_ready_tick": enemy.next_action_ready_tick,
			"parts": part_state.parts,
			"pending_part_transitions": part_state.pending_part_transitions,
			"phase_id": enemy.phase_id,
			"phase_state": enemy.phase_state,
			"right_hand_x_milli": roundi(enemy.right_hand_position.x * 1000.0),
			"right_hand_y_milli": roundi(enemy.right_hand_position.y * 1000.0),
			"state_ends_tick": enemy.state_ends_tick,
			"state_started_tick": enemy.state_started_tick,
			"tactic_reason": enemy.tactic_reason,
			"tactic_state": enemy.tactic_state,
			"target_shape": CombatStateCodecScript.target_shape_state(enemy.target_shape),
			"x_millipixels": roundi(enemy.position.x * 1000.0),
			"y_millipixels": roundi(enemy.position.y * 1000.0),
		}
		if enemy is CombatEnemyState:
			var effects: Variant = enemy.status_effects_snapshot(int(_runtime_value(session, "sim_tick", 0)))
			if effects is Dictionary and bool((effects as Dictionary).get("ok", false)) and not ((effects as Dictionary).get("effects", []) as Array).is_empty():
				enemy_entry["status_effects"] = CombatStateCodecScript.hash_safe(effects)
		enemy_state.append(enemy_entry)

	var hazard_state: Array[Dictionary] = []
	var hazard_value: Variant = _runtime_value(runtime, "hazard_states")
	if hazard_value is Array:
		for hazard: Dictionary in hazard_value:
			var direction: Vector2 = hazard.get("direction", Vector2.ZERO) as Vector2
			var origin: Vector2 = hazard.get("origin", Vector2.ZERO) as Vector2
			hazard_state.append({
				"cycle": int(hazard.get("cycle", 0)),
				"cycle_tick": int(hazard.get("cycle_tick", 0)),
				"direction_x_milli": roundi(direction.x * 1000.0),
				"direction_y_milli": roundi(direction.y * 1000.0),
				"id": String(hazard.get("id", "")),
				"last_hit_cycle": int(hazard.get("last_hit_cycle", -1)),
				"length_milli": roundi(float(hazard.get("length", 0.0)) * 1000.0),
				"origin_x_milli": roundi(origin.x * 1000.0),
				"origin_y_milli": roundi(origin.y * 1000.0),
				"phase": String(hazard.get("phase", "")),
				"radius_milli": roundi(float(hazard.get("radius", 0.0)) * 1000.0),
				"width_milli": roundi(float(hazard.get("width", 0.0)) * 1000.0),
			})

	var manual_input_state: Dictionary = {}
	var manual_input_value: Variant = _runtime_value(runtime, "manual_combat_input")
	if String(_runtime_value(session, "selected_mode", "")) == "Manual" and bool(_runtime_value(session, "in_arena", false)) and not _battle_flag(session, "is_battle_over", "battle_over") and manual_input_value is Object:
		var input_snapshot_value: Variant = (manual_input_value as Object).snapshot()
		if input_snapshot_value is Dictionary:
			var input_state: Dictionary = input_snapshot_value as Dictionary
			var pointer_sources_value: Variant = input_state.get("pointer_sources", {})
			var non_pointer_sources_value: Variant = input_state.get("non_pointer_sources", {})
			var pointer_world_count := 0
			var pointer_hud_count := 0
			if pointer_sources_value is Dictionary:
				for world_owned: Variant in (pointer_sources_value as Dictionary).values():
					if bool(world_owned):
						pointer_world_count += 1
					else:
						pointer_hud_count += 1
			manual_input_state = {
				"assisted_held_count": (non_pointer_sources_value as Dictionary).size() if non_pointer_sources_value is Dictionary else 0,
				"pointer_world_held_count": pointer_world_count,
				"pointer_hud_owned_count": pointer_hud_count,
			}

	var projectile_state: Array[Dictionary] = []
	var projectile_value: Variant = _runtime_value(runtime, "projectiles")
	var ordered_projectiles: Array = (projectile_value as Array).duplicate() if projectile_value is Array else []
	ordered_projectiles.sort_custom(func(left, right) -> bool: return int(left.action_instance_id) < int(right.action_instance_id))
	for projectile in ordered_projectiles:
		projectile_state.append({
			"action_instance_id": projectile.action_instance_id,
			"target_entity_id": projectile.target_entity_id,
			"spawned_tick": projectile.spawned_tick,
			"origin_x_milli": roundi(projectile.origin.x * 1000.0),
			"origin_y_milli": roundi(projectile.origin.y * 1000.0),
			"direction_x_milli": roundi(projectile.direction.x * 1000.0),
			"direction_y_milli": roundi(projectile.direction.y * 1000.0),
			"position_x_milli": roundi(projectile.position.x * 1000.0),
			"position_y_milli": roundi(projectile.position.y * 1000.0),
			"previous_x_milli": roundi(projectile.previous_position.x * 1000.0),
			"previous_y_milli": roundi(projectile.previous_position.y * 1000.0),
			"distance_milli": roundi(projectile.distance_travelled * 1000.0),
			"maximum_range_milli": roundi(projectile.maximum_range * 1000.0),
			"speed_milli": roundi(projectile.speed * 1000.0),
			"ordinary_damage_milli": roundi(projectile.ordinary_damage * 1000.0),
			"aggregate_damage": CombatStateCodecScript.big_value_state(projectile.aggregate_damage),
			"event_count": CombatStateCodecScript.big_value_state(projectile.event_count),
			"payload_milli": roundi(projectile.payload * 1000.0),
		})

	var boss: Variant = _runtime_value(director, "boss")
	var boss_damage: Variant = outcome.boss_damage
	var destiny_forge: Variant = _runtime_value(runtime, "destiny_forge")
	var proxy_runtime: Variant = _runtime_value(session, "proxy_runtime")
	var proxy_intent_system: Variant = _runtime_value(session, "proxy_intent_system")
	var proxy_intent_diagnostic := _object_snapshot(proxy_intent_system, "diagnostic_snapshot")
	var combat_event_stream: Variant = _runtime_value(session, "combat_event_stream")
	var locked_build: Variant = _runtime_value(session, "locked_build")
	var framework_proxy_build: Variant = _runtime_value(session, "framework_resolved_proxy_build")
	var state := {
		"arena_geometry": CombatStateCodecScript.hash_safe({
			"player": _walkable_geometry(runtime, 14.0),
			"enemy": _walkable_geometry(runtime, 16.0),
		}),
		"boss_damage": CombatStateCodecScript.big_value_state(boss_damage),
		"boss_health_milli": roundi(boss.health * 1000.0) if boss != null else -1,
		"boss_x_millipixels": roundi(boss.position.x * 1000.0) if boss != null else 0,
		"boss_y_millipixels": roundi(boss.position.y * 1000.0) if boss != null else 0,
		"battle_victory": _battle_flag(session, "is_battle_victory", "battle_victory"),
		"action_timeline": CombatStateCodecScript.hash_safe(player.get("timeline", {})),
		"command_sequence": int(_runtime_value(session, "command_sequence", 0)),
		"command_receipts": CombatStateCodecScript.hash_safe(_runtime_value(session, "last_command_receipts", [])),
		"combat_events": CombatStateCodecScript.hash_safe(_object_snapshot(combat_event_stream, "snapshot")),
		"content_hash": _content_hash(session),
		"contract_wins": int(_runtime_value(runtime, "contract_wins", 0)),
		"defeated": int(outcome.defeated),
		"enemies": enemy_state,
		"elite_barrier_active": bool(_runtime_value(director, "elite_barrier_active", false)),
		"elite_entity_id": int(_runtime_value(director, "elite_entity_id", 0)),
		"elite_rule_ids": _runtime_value(director, "elite_rule_ids", []),
		"forge": _object_snapshot(destiny_forge, "state"),
		"last_drop": String(_runtime_value(runtime, "last_drop", "")),
		"last_drop_id": String(_runtime_value(runtime, "last_drop_id", "")),
		"last_loot_rng_state": _runtime_value(runtime, "last_loot_rng_state", {}),
		"last_attack_outcome": CombatStateCodecScript.hash_safe(_runtime_value(runtime, "last_attack_outcome", {})),
		"last_proxy_failure": proxy_intent_diagnostic.get("last_failure", {}),
		"hazards": hazard_state,
		"layout_id": String(_runtime_value(session, "layout_id", "")),
		"objective_id": String(_runtime_value(session, "objective_id", "")),
		"reinforcements_summoned": bool(_runtime_value(director, "reinforcements_summoned", false)),
		"room_drop_tags": _runtime_value(session, "room_drop_tags", []),
		"room_reward_snapshot": _runtime_value(runtime, "room_reward_snapshot", {}),
		"room_id": String(_runtime_value(session, "room_id", "")),
		"timed_bonus_available": bool(_runtime_value(director, "timed_bonus_available", false)),
		"build_fingerprint": String((locked_build as Dictionary).get("build_fingerprint", "diagnostic")) if locked_build is Dictionary else "diagnostic",
		"mode": String(_runtime_value(session, "selected_mode", "")).to_lower(),
		"manual_input": manual_input_state,
		"manual_attack_intent": {
			"edge_requested": bool(_runtime_value(runtime, "attack_requested", false)),
			"edge_source": String(_runtime_value(runtime, "attack_requested_source", "")),
			"edge_target_entity_id": int(_runtime_value(runtime, "attack_requested_target_entity_id", 0)),
			"pointer_target_entity_id": int(_runtime_value(runtime, "manual_pointer_target_entity_id", 0)),
		},
		"next_entity_id": int(_runtime_value(director, "next_entity_id", 0)),
		"next_enemy_action_instance_id": int(_runtime_value(director, "next_enemy_action_instance_id", 0)),
		"payload_milli": roundi(float(_runtime_value(session, "locked_payload", 0.0)) * 1000.0),
		"p_basis_points": roundi(float(_runtime_value(session, "locked_p", 0.0)) * 100.0),
		"player_health_milli": roundi(float(player.get("player_health", 0.0)) * 1000.0),
		"player_maximum_health_milli": roundi(float(player.get("player_maximum_health", 0.0)) * 1000.0),
		"player_facing_x_milli": roundi((player.get("player_facing", Vector2.RIGHT) as Vector2).x * 1000.0),
		"player_facing_y_milli": roundi((player.get("player_facing", Vector2.RIGHT) as Vector2).y * 1000.0),
		"player_last_displacement_x_milli": roundi((player.get("player_last_displacement", Vector2.ZERO) as Vector2).x * 1000.0),
		"player_last_displacement_y_milli": roundi((player.get("player_last_displacement", Vector2.ZERO) as Vector2).y * 1000.0),
		"player_x_millipixels": roundi((player.get("player_position", Vector2.ZERO) as Vector2).x * 1000.0),
		"player_y_millipixels": roundi((player.get("player_position", Vector2.ZERO) as Vector2).y * 1000.0),
		"proxy_mode": proxy_runtime.get("mode") if proxy_runtime is Object else "",
		"proxy_mode_locked": proxy_runtime.get("mode_locked") if proxy_runtime is Object else false,
		"proxy_build_fingerprint": String((framework_proxy_build as Dictionary).get("semantic_fingerprint", "")) if framework_proxy_build is Dictionary else "",
		"proxy_decision_state": CombatStateCodecScript.hash_safe(proxy_intent_diagnostic.get("decision_state", {})),
		"proxy_prediction": String(_runtime_value(session, "proxy_prediction", "unknown")),
		"projectiles": projectile_state,
		"result": result,
		"sim_protocol_version": 1,
		"targeting_distance_milli": roundi(float(_runtime_value(session, "locked_targeting_distance", 0.0)) * 1000.0),
		"tick": int(_runtime_value(session, "sim_tick", 0)),
	}
	if player.has("combat_stats"):
		state["combat_stats"] = CombatStateCodecScript.hash_safe(player.get("combat_stats", {}))
		var combat_stats_value: Variant = player.get("combat_stats", {})
		if combat_stats_value is Dictionary and String((combat_stats_value as Dictionary).get("movement_model", "direct")) == "accelerated":
			var velocity: Vector2 = player.get("player_velocity", Vector2.ZERO)
			state["player_velocity_x_milli"] = roundi(velocity.x * 1000.0)
			state["player_velocity_y_milli"] = roundi(velocity.y * 1000.0)
	var room_loot_value: Variant = _room_loot_snapshot(session)
	if room_loot_value is Dictionary and bool((room_loot_value as Dictionary).get("enabled", false)):
		state["room_loot"] = CombatStateCodecScript.hash_safe(room_loot_value)
	var kit := _state_kit(session)
	var kit_slice: Dictionary = kit.hash_slice(player, outcome)
	for key: String in kit_slice:
		if state.has(key):
			push_error("combat_state_snapshot_builder_kit_key_collision:%s" % key)
	state.merge(kit_slice, false)
	return state


static func _enemy_parts_state(enemy: Object) -> Dictionary:
	var source: Dictionary = enemy.gameplay_parts_snapshot()
	var parts: Array[Dictionary] = []
	for part: Dictionary in source.parts:
		var pose: Vector2 = part.get("pose", Vector2.ZERO)
		var resolved_pose: Vector2 = part.resolved_pose
		var hurtbox: Dictionary = part.get("hurtbox", {})
		parts.append({
			"part_id": String(part.part_id), "damage_group_id": String(part.get("damage_group_id", "")),
			"active": bool(part.get("active", true)), "broken": bool(part.get("broken", false)),
			"pose_source": String(part.get("pose_source", "")),
			"pose_x_milli": roundi(pose.x * 1000.0), "pose_y_milli": roundi(pose.y * 1000.0),
			"resolved_pose_x_milli": roundi(resolved_pose.x * 1000.0), "resolved_pose_y_milli": roundi(resolved_pose.y * 1000.0),
			"pose_x_f64_be": _float64_state(pose.x), "pose_y_f64_be": _float64_state(pose.y),
			"resolved_pose_x_f64_be": _float64_state(resolved_pose.x), "resolved_pose_y_f64_be": _float64_state(resolved_pose.y),
			"hurtbox": {"type": String(hurtbox.get("type", "")), "radius_milli": roundi(float(hurtbox.get("radius", 0.0)) * 1000.0), "radius_f64_be": _float64_state(float(hurtbox.get("radius", 0.0)))},
		})
	return {"parts": parts, "pending_part_transitions": source.pending_part_transitions}


## Incoming part geometry is queried at its actual floating point precision.
## Milli fields remain readable; fixed-endian IEEE-754 bytes prevent them from
## hiding sub-millipixel changes without quantizing the simulation itself.
static func _float64_state(value: float) -> String:
	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = true
	buffer.put_double(value)
	return buffer.data_array.hex_encode()


static func _runtime_value(runtime: Object, property: String, default_value: Variant = null) -> Variant:
	var value: Variant = runtime.get(property)
	return default_value if value == null else value


static func _authority(runtime: Object) -> Object:
	var session: Variant = _runtime_value(runtime, "session")
	return session if session is Object else runtime


## The view's walkable geometry (MainArena or a test double).
static func _walkable_geometry(view: Variant, padding: float) -> Dictionary:
	return view.walkable_geometry(padding)


static func _content_hash(session: Variant) -> String:
	return String(session.content_hash())


static func _battle_flag(session: Object, method: String, property: String) -> bool:
	if session.has_method(method):
		return bool(session.call(method))
	return bool(_runtime_value(session, property, false))


static func _room_loot_snapshot(session: Object) -> Variant:
	var room_loot: Variant = _runtime_value(session, "room_loot")
	if room_loot is CombatRoomLoot:
		return (room_loot as CombatRoomLoot).snapshot()
	return _runtime_value(session, "room_loot_snapshot", {})


static func _object_snapshot(value: Variant, method: String) -> Dictionary:
	if not value is Object or not (value as Object).has_method(method):
		return {}
	var snapshot: Variant = (value as Object).call(method)
	return snapshot.duplicate(true) if snapshot is Dictionary else {}


## The session's class kit owns the class slice of the hash; a source without a
## kit (test doubles) falls back to the Ranger kit so the hash is unchanged.
static func _state_kit(session: Object) -> ClassKit:
	var kit: Variant = _runtime_value(session, "kit")
	if kit is ClassKit:
		return kit
	return RangerKitScript.new()
