class_name PlayerCombatRules
extends RefCounted

## Player-only fixed-tick rules. No Main callbacks or mutable target objects.
const State := preload("res://src/runtime/world/player_combat_state.gd")
const Skill := preload("res://src/systems/ranger_skill_rules.gd")
const Motion := preload("res://src/systems/player_motion_system.gd")
const Protocol := preload("res://src/systems/combat_command_protocol.gd")
const ArrowOrigin := preload("res://src/game/ranger_arrow_origin.gd")
const AimResolver := preload("res://src/systems/manual_aim_resolver.gd")
const Big := preload("res://src/core/big_value.gd")
const CoreResult := preload("res://src/core/result.gd")

var _state: State
var _world
var _stream
var _motor := Motion.new()
var _prepared_tick := -1
var _targets: Array[Dictionary] = []


func configure(state: State, world, event_stream) -> Dictionary:
	if state == null or world == null or event_stream == null or state.actor_snapshot().is_empty():
		return CoreResult.failure("player_rules_dependencies_unavailable")
	if int(world.tick_rate) != Skill.TICKS_PER_SECOND:
		return CoreResult.failure("invalid_player_tick_rate")
	if world.room_instance_id != state._room_instance_id or world.world_revision != state._world_revision or int(world.tick) != state._last_tick:
		return CoreResult.failure("stale_player_room")
	_state = state
	_world = world
	_stream = event_stream
	_prepared_tick = -1
	_targets.clear()
	return {"ok": true, "error": ""}


## Optional early phase for command/proxy collection to see decremented counters.
## advance_tick calls this itself when used without CombatSimulation.
func begin_tick(tick: int, read_only_targets: Array[Dictionary]) -> Dictionary:
	var error := _tick_error(tick, true)
	if not error.is_empty():
		return CoreResult.failure(error)
	if tick == _prepared_tick:
		return CoreResult.failure("duplicate_player_tick")
	_prepared_tick = tick
	_targets = read_only_targets.duplicate(true)
	var values := _state._values
	for key: String in ["attack_cooldown_ticks", "dodge_cooldown_ticks", "hunter_mark_cooldown_ticks", "dash_cooldown_ticks"]:
		values[key] = maxi(0, int(values[key]) - 1)
	for kind: String in ["dodge", "dash"]:
		var key := kind + "_remaining_ticks"
		if int(values[key]) > 0:
			values[key] = int(values[key]) - 1
			if int(values[key]) == 0:
				_stream.emit(tick, "displacement_ended", {"actor_id": _state._ranger_id, "kind": kind, "start_tick": int(values[kind + "_started_tick"]), "actual_to": _state.position()})
	var action_events := _advance_timeline(tick)
	var action_player := _state.snapshot(tick)
	update_mark(tick, _targets)
	if int(values.hunter_mark_candidate_entity_id) > 0 and tick > int(values.hunter_mark_candidate_expires_tick):
		values.hunter_mark_candidate_entity_id = 0
		values.hunter_mark_candidate_expires_tick = 0
	return {"ok": true, "error": "", "tick": tick, "action_events": action_events, "action_player": action_player, "player": _state.snapshot(tick)}


func advance_tick(tick: int, routed_intent: Dictionary, read_only_targets: Array[Dictionary]) -> Dictionary:
	var error := _tick_error(tick, true)
	if not error.is_empty():
		return CoreResult.failure(error)
	var requested_movement: Variant = routed_intent.get("movement", Vector2.ZERO)
	if not requested_movement is Vector2 or not (requested_movement as Vector2).is_finite() or not is_finite(float(routed_intent.get("speed_scale", 1.0))):
		return CoreResult.failure("invalid_motion")
	var action_events: Array[Dictionary] = []
	var action_batches: Array[Dictionary] = []
	if _prepared_tick != tick:
		var preparation := begin_tick(tick, read_only_targets)
		if not preparation.ok:
			return preparation
		action_events.append_array(preparation.action_events)
		action_batches.append({"player": preparation.action_player, "events": preparation.action_events})
	var pre_action_count := action_events.size()
	_targets = read_only_targets.duplicate(true)
	var commands: Array = routed_intent.get("commands", []).duplicate(true)
	var protocol_receipts: Array = routed_intent.get("receipts", []).duplicate(true)
	var buffered := _take_ready_mobility(tick)
	if not buffered.is_empty():
		commands.append(buffered)
		var arbitration := Protocol.arbitrate(commands, tick, _state.equipped_ability_ids())
		commands = arbitration.commands
		protocol_receipts.append_array(arbitration.receipts)
	var receipts: Array[Dictionary] = []
	for protocol_receipt: Dictionary in protocol_receipts:
		if String(protocol_receipt.get("status", "")) == "rejected":
			receipts.append(_command_receipt(tick, protocol_receipt.get("command", {}), protocol_receipt))
	var movement: Vector2 = routed_intent.get("movement", Vector2.ZERO)
	var speed_scale := float(routed_intent.get("speed_scale", 1.0))
	for command: Dictionary in commands:
		var receipt: Dictionary
		if String(command.get("actor_id", _state._ranger_id)) != _state._ranger_id:
			receipt = _rejected("wrong_actor")
		elif int(command.get("tick", tick)) != tick:
			receipt = _rejected("stale_tick")
		else:
			match String(command.get("kind", "")):
				Protocol.KIND_MOVE:
					movement = _direction(command)
					speed_scale = float(command.get("speed_milli", 1000)) / 1000.0
					receipt = _accepted()
				Protocol.KIND_STOP_MOVE:
					movement = Vector2.ZERO
					speed_scale = 0.0
					receipt = _accepted()
				Protocol.KIND_DODGE:
					receipt = request_cast(tick, "dodge", 0, _direction(command), _targets)
				Protocol.KIND_CAST:
					receipt = request_cast(tick, String(command.get("ability_id", "")), int(command.get("target_entity_id", 0)), _direction(command), _targets)
				_:
					receipt = _rejected("invalid_command")
		if String(receipt.get("reason", "")) == "mobility_conflict" and _buffer_mobility(tick, command):
			receipt = {"accepted": false, "status": "buffered", "reason": "mobility_buffered"}
		action_events.append_array(receipt.get("action_events", []))
		receipts.append(_command_receipt(tick, command, receipt))
	# Same-tick advance emits newly started actions; the existing timeline ensures
	# a previously emitted boundary is never repeated.
	action_events.append_array(_advance_timeline(tick))
	var action_player := _state.snapshot(tick)
	action_batches.append({"player": action_player, "events": action_events.slice(pre_action_count)})
	var motion := _motor.advance_player(_state, _world, tick, movement, speed_scale)
	if not bool(motion.get("ok", false)):
		return CoreResult.failure(String(motion.get("error", "player_motion_failed")))
	_state._last_tick = tick
	_prepared_tick = -1
	return {"ok": true, "error": "", "tick": tick, "player": _state.snapshot(tick), "receipts": receipts, "protocol_receipts": protocol_receipts, "action_events": action_events, "action_player": action_player, "action_batches": action_batches, "motion": motion}


## Input release discards only a queued mobility request. Executing gameplay
## continues on the existing world tick and produces no command or event.
func release_input(tick: int) -> Dictionary:
	var error := _tick_error(tick, false)
	if not error.is_empty():
		return {"ok": false, "error": error, "cleared": false}
	var cleared := not (_state._values.mobility_input_buffer as Dictionary).is_empty()
	_state._values.mobility_input_buffer = {}
	return {"ok": true, "error": "", "cleared": cleared}


func request_cast(tick: int, ability_id: String, target_entity_id: int = 0, direction: Vector2 = Vector2.ZERO, read_only_targets: Array[Dictionary] = []) -> Dictionary:
	var error := _tick_error(tick, false)
	if not error.is_empty():
		return _rejected(error)
	if not direction.is_finite():
		return _rejected("invalid_aim_direction")
	_targets = read_only_targets.duplicate(true)
	if float(_state._values.player_health) <= 0.0:
		return _rejected("player_dead")
	if ability_id in ["dodge", "dash"]:
		return _start_mobility(tick, ability_id, direction)
	if ability_id not in _state.equipped_ability_ids():
		return _rejected("ability_not_equipped" if ability_id in ["hunter_mark", "piercing_arrow"] else "invalid_ability")
	var target := _target(target_entity_id)
	var range_scale := Skill.HUNTER_MARK_RANGE_MULTIPLIER if ability_id == "hunter_mark" else 1.0
	if ability_id == "hunter_mark" and int(_state._values.hunter_mark_cooldown_ticks) > 0:
		return _rejected("cooldown_active")
	if ability_id == "hunter_mark" and target_entity_id <= 0:
		target = _nearest_target(_state.targeting_distance() * range_scale)
	if target.is_empty() or float(target.get("health", 0.0)) <= 0.0:
		return _rejected("target_invalid")
	if _state.position().distance_to(target.position) > _state.targeting_distance() * range_scale:
		return _rejected("target_out_of_range")
	var values := _state._values
	if ability_id == "hunter_mark":
		advance_three_skill_sequence("hunter_mark")
		values.marked_entity_id = int(target.entity_id)
		values.hunter_mark_expires_tick = tick + _state.scaled_ticks(Skill.HUNTER_MARK_DURATION_TICKS, "hunter_mark_duration_multiplier")
		values.hunter_mark_cooldown_ticks = Skill.HUNTER_MARK_COOLDOWN_TICKS
		return _accepted()
	var aim := direction.normalized() if direction != Vector2.ZERO else _state.position().direction_to(target.position)
	if aim == Vector2.ZERO:
		aim = values.player_facing if values.player_facing != Vector2.ZERO else Vector2.RIGHT
	var windup := Skill.PIERCING_ARROW_WINDUP_TICKS
	if bool(values.three_skill_bonus_ready):
		windup = clampi(int(round(float(values.talent_capabilities.get("three_skill_rhythm_windup_ticks", windup)))), 1, windup)
	var queued: Dictionary = _state._timeline.snapshot().buffered
	windup = mini(windup, int(queued.get("windup_ticks", Skill.PIERCING_ARROW_WINDUP_TICKS)))
	var receipt := _state._timeline.request_attack(tick, int(target.entity_id), aim, tick + int(values.attack_cooldown_ticks), windup)
	if bool(receipt.accepted):
		if bool(values.three_skill_bonus_ready):
			reset_three_skill_sequence()
		if String(receipt.status) == "started":
			values.attack_cooldown_ticks = _state.attack_cooldown_ticks()
			values.player_facing = aim
	return receipt


func interrupt_action(tick: int, reason: String) -> Dictionary:
	var error := _tick_error(tick, false)
	if not error.is_empty():
		return _rejected(error)
	var result := _state._timeline.interrupt(tick, reason)
	_process_action_events(result.events)
	return result.duplicate(true)


func apply_damage(tick: int, amount: float, source_id: String, source_position: Vector2) -> Dictionary:
	var error := _tick_error(tick, false)
	if not error.is_empty():
		return _rejected(error)
	if not is_finite(amount) or amount < 0.0 or not source_position.is_finite():
		return _rejected("invalid_damage")
	var values := _state._values
	if int(values.dodge_remaining_ticks) > 0:
		return _rejected("dodge_invulnerable")
	var before := float(values.player_health)
	values.player_health = snappedf(maxf(0.0, before - amount), 0.001)
	# Legacy source-less damage still changes health but emits no hit receipt.
	if source_id.is_empty() or float(values.player_health) >= before:
		return _rejected("source_unidentified" if source_id.is_empty() else "no_damage")
	values.last_damage_source_id = source_id
	values.last_damage_tick = tick
	values.last_damage_amount = before - float(values.player_health)
	values.last_damage_direction = source_position.direction_to(_state.position()) if source_position != _state.position() else Vector2.ZERO
	var events: Array[Dictionary] = [_stream.emit(tick, "damage_applied", {
		"source_id": source_id, "target_id": _state._ranger_id, "target_entity_id": 0,
		"amount": String.num(values.last_damage_amount, 3), "health_before_milli": roundi(before * 1000.0),
		"health_after_milli": roundi(float(values.player_health) * 1000.0), "contact_point": _state.position(),
		"incoming_direction": values.last_damage_direction,
	})]
	if float(values.player_health) <= 0.0:
		events.append(_stream.emit(tick, "death_applied", {"source_id": source_id, "target_id": _state._ranger_id, "target_entity_id": 0, "position": _state.position()}))
	return {"accepted": true, "status": "accepted", "reason": "ok", "events": events}


func update_mark(tick: int, read_only_targets: Array[Dictionary]) -> void:
	if not _tick_error(tick, false).is_empty():
		return
	_targets = read_only_targets.duplicate(true)
	var values := _state._values
	if int(values.marked_entity_id) == 0:
		return
	var target := _target(int(values.marked_entity_id))
	var alive := not target.is_empty() and float(target.get("health", 0.0)) > 0.0
	var candidate_ticks := int(round(float(values.talent_capabilities.get("lost_mark_candidate_ticks", 0.0))))
	if alive and _state.position().distance_to(target.position) > Skill.HUNTER_MARK_RANGE_MULTIPLIER * _state.targeting_distance():
		if candidate_ticks > 0 and tick < int(values.hunter_mark_expires_tick):
			values.hunter_mark_candidate_entity_id = int(target.entity_id)
			values.hunter_mark_candidate_expires_tick = tick + candidate_ticks
			values.marked_entity_id = 0
			values.hunter_mark_expires_tick = 0
		return
	if alive and tick < int(values.hunter_mark_expires_tick):
		return
	if alive and candidate_ticks > 0:
		values.hunter_mark_candidate_entity_id = int(target.entity_id)
		values.hunter_mark_candidate_expires_tick = tick + candidate_ticks
	else:
		values.hunter_mark_candidate_entity_id = 0
		values.hunter_mark_candidate_expires_tick = 0
	values.marked_entity_id = 0
	values.hunter_mark_expires_tick = 0


func advance_three_skill_sequence(kind: String) -> void:
	var values := _state._values
	if not values.talent_capabilities.has("three_skill_rhythm_windup_ticks") or bool(values.three_skill_bonus_ready):
		return
	var stage := int({"piercing_arrow": 1, "hunter_mark": 2, "dash": 3}.get(kind, 0))
	if stage != 1 + int(values.three_skill_sequence_stage):
		values.three_skill_sequence_stage = 1 if kind == "piercing_arrow" else 0
		return
	values.three_skill_sequence_stage = stage
	if stage == 3:
		values.three_skill_bonus_ready = true


func reset_three_skill_sequence() -> void:
	_state._values.three_skill_sequence_stage = 0
	_state._values.three_skill_bonus_ready = false


func cancel_buffered_target(entity_id: int) -> int:
	return _state._timeline.cancel_buffered_target(entity_id)


func consume_first_critical_bonus() -> int:
	var bonus := maxi(0, int(_state._values.talent_capabilities.get("first_critical_bonus_generations", 0)))
	if bool(_state._values.first_critical_bonus_used) or bonus == 0:
		return 0
	_state._values.first_critical_bonus_used = true
	return bonus


func retain_missed_arrow(aggregate: Big, ordinary: float) -> void:
	var ratio := clampf(float(_state._values.talent_capabilities.get("expiry_payload_retention", 0.0)), 0.0, 1.0)
	_state._values.retained_arrow_damage = (_state._values.retained_arrow_damage as Big).add(aggregate.multiply(Big.from_float(ratio)))
	_state._values.retained_arrow_ordinary_damage += ordinary * ratio


func take_retained_arrow() -> Dictionary:
	var result := {"aggregate": (_state._values.retained_arrow_damage as Big).duplicate_value(), "ordinary": float(_state._values.retained_arrow_ordinary_damage)}
	_state._values.retained_arrow_damage = Big.from_float(0.0)
	_state._values.retained_arrow_ordinary_damage = 0.0
	return result


func _start_mobility(tick: int, kind: String, input_direction: Vector2) -> Dictionary:
	var values := _state._values
	if kind == "dash" and kind not in _state.equipped_ability_ids():
		return _rejected("ability_not_equipped")
	if int(values[kind + "_cooldown_ticks"]) > 0:
		return _rejected("cooldown_active")
	if int(values.dash_remaining_ticks) > 0 or int(values.dodge_remaining_ticks) > 0:
		return _rejected("mobility_conflict")
	var interrupted_events: Array = []
	if not bool(values.talent_capabilities.get("mobility_preserves_mark_and_lineage", false)):
		interrupted_events = interrupt_action(tick, kind).get("events", [])
	var direction := input_direction.normalized() if input_direction != Vector2.ZERO else (values.player_facing as Vector2).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	var duration := _state.dodge_duration_ticks() if kind == "dodge" else _state.scaled_ticks(Skill.DASH_DURATION_TICKS, "dash_duration_multiplier")
	if kind == "dodge":
		values.player_facing = direction
	else:
		advance_three_skill_sequence("dash")
	values[kind + "_direction"] = direction
	values[kind + "_remaining_ticks"] = duration
	values[kind + "_cooldown_ticks"] = _state.dodge_cooldown() if kind == "dodge" else Skill.DASH_COOLDOWN_TICKS
	values[kind + "_started_tick"] = tick
	var distance := _state.dodge_distance() if kind == "dodge" else Skill.DASH_TOTAL_DISTANCE
	var event: Dictionary = _stream.emit(tick, "displacement_started", {"actor_id": _state._ranger_id, "kind": kind, "start_tick": tick, "end_tick": tick + duration, "from": _state.position(), "intended_to": _state.position() + direction * distance, "invulnerable": kind == "dodge"})
	var receipt := _accepted()
	receipt["events"] = [event]
	receipt["action_events"] = interrupted_events
	return receipt


func _advance_timeline(tick: int) -> Array[Dictionary]:
	var events := _state._timeline.advance(tick)
	_process_action_events(events)
	return events


func _process_action_events(events: Array) -> void:
	for event: Dictionary in events:
		var tick := int(event.tick)
		var id := int(event.get("action_instance_id", 0))
		match String(event.type):
			"buffered_started":
				_state._values.attack_cooldown_ticks = _state.attack_cooldown_ticks()
			"action_started":
				var aim_data: Dictionary = event.aim_direction_milli
				var aim := Vector2(float(aim_data.x), float(aim_data.y)) / 1000.0
				if aim != Vector2.ZERO:
					_state._values.player_facing = aim.normalized()
				var offset := ArrowOrigin.release_offset(_state._values.player_facing)
				var origin := _state.position() + offset
				var locked_direction: Vector2 = _state._values.player_facing
				var target := _target(int(event.target_entity_id))
				if not target.is_empty():
					var anchor := AimResolver.new().target_anchor(target)
					if origin.distance_squared_to(anchor) > 0.000001:
						locked_direction = origin.direction_to(anchor)
				_state._values.attack_origins[id] = {"actor_origin": _state.position(), "projectile_origin": origin, "release_offset": offset, "direction": locked_direction}
				_stream.emit(tick, "action_accepted", {"action_instance_id": id, "actor_id": _state._ranger_id, "action_id": "piercing_arrow", "target_entity_id": int(event.target_entity_id), "locked_origin": origin, "locked_direction": locked_direction, "impact_tick": tick + int(event.windup_ticks)})
			"action_ended", "action_interrupted":
				if String(event.type) == "action_interrupted":
					reset_three_skill_sequence()
				var payload := {"action_instance_id": id, "actor_id": _state._ranger_id, "action_id": "piercing_arrow"}
				if event.has("reason"):
					payload["reason"] = event.reason
				_stream.emit(tick, String(event.type), payload)
				_state._values.attack_origins.erase(id)


func _buffer_mobility(tick: int, command: Dictionary) -> bool:
	var remaining := maxi(int(_state._values.dodge_remaining_ticks), int(_state._values.dash_remaining_ticks))
	if remaining <= 0 or remaining > Motion.MOBILITY_INPUT_BUFFER_TICKS:
		return false
	if String(command.get("kind", "")) != Protocol.KIND_DODGE and not (String(command.get("kind", "")) == Protocol.KIND_CAST and String(command.get("ability_id", "")) == "dash"):
		return false
	var buffer := command.duplicate(true)
	buffer["request_tick"] = tick
	buffer["expires_tick"] = tick + Motion.MOBILITY_INPUT_BUFFER_TICKS
	_state._values.mobility_input_buffer = buffer
	return true


func _take_ready_mobility(tick: int) -> Dictionary:
	var buffer: Dictionary = _state._values.mobility_input_buffer
	if buffer.is_empty():
		return {}
	if tick > int(buffer.expires_tick):
		_state._values.mobility_input_buffer = {}
		return {}
	if int(_state._values.dodge_remaining_ticks) > 0 or int(_state._values.dash_remaining_ticks) > 0:
		return {}
	_state._values.mobility_input_buffer = {}
	var kind := "dodge" if String(buffer.get("kind", "")) == Protocol.KIND_DODGE else "dash"
	if int(_state._values[kind + "_cooldown_ticks"]) > 0 or (kind == "dash" and kind not in _state.equipped_ability_ids()):
		return {}
	var command := buffer.duplicate(true)
	command.erase("request_tick")
	command.erase("expires_tick")
	command["tick"] = tick
	return command


func _target(id: int) -> Dictionary:
	for target: Dictionary in _targets:
		if int(target.get("entity_id", 0)) == id:
			return target
	return {}


func _nearest_target(maximum: float) -> Dictionary:
	var nearest: Dictionary = {}
	var distance := maximum * maximum
	for target: Dictionary in _targets:
		if float(target.get("health", 0.0)) <= 0.0:
			continue
		var current := _state.position().distance_squared_to(target.position)
		if current <= distance and (nearest.is_empty() or current < distance or int(target.entity_id) < int(nearest.entity_id)):
			nearest = target
			distance = current
	return nearest


func _tick_error(tick: int, advancing: bool) -> String:
	if _state == null or _world == null:
		return "player_rules_not_configured"
	if _state.actor_snapshot().is_empty() or _world.room_instance_id != _state._room_instance_id or _world.world_revision != _state._world_revision:
		return "stale_player_room"
	if tick != int(_world.tick):
		return "uncommitted_world_tick"
	if advancing:
		if tick <= _state._last_tick:
			return "duplicate_player_tick"
		if tick != _state._last_tick + 1:
			return "skipped_player_tick"
		if tick <= int(_state.actor_snapshot().last_motor_tick):
			return "non_monotonic_motor_tick"
	elif tick != _state._last_tick and tick != _prepared_tick:
		return "player_tick_not_prepared"
	return ""


func _command_receipt(tick: int, command: Dictionary, receipt: Dictionary) -> Dictionary:
	var result := receipt.duplicate(true)
	result["command"] = command.duplicate(true)
	var accepted := bool(receipt.get("accepted", String(receipt.get("status", "")) == "accepted"))
	var status := "accepted" if accepted else ("buffered" if String(receipt.get("reason", "")) == "mobility_buffered" else "rejected")
	var reason := String(receipt.get("reason", ""))
	if accepted and String(command.get("ability_id", "")) == "piercing_arrow":
		reason = String(receipt.get("status", "accepted"))
	result["event_id"] = int(_stream.emit(tick, "command_receipt", {"command": command, "status": status, "reason": reason}).event_id)
	return result


static func _direction(command: Dictionary) -> Vector2:
	var value := Vector2(float(command.get("direction_x_milli", 0)), float(command.get("direction_y_milli", 0))) / 1000.0
	return value.normalized() if value != Vector2.ZERO else Vector2.ZERO


static func _accepted() -> Dictionary:
	return {"accepted": true, "status": "accepted", "reason": "ok"}


static func _rejected(reason: String) -> Dictionary:
	return {"accepted": false, "status": "rejected", "reason": reason}

