class_name PlayerMotionSystem
extends RefCounted

## One motor submission per real world tick, including a stationary tick.
## Mobility timers and actions belong to PlayerCombatRules, not callbacks.
const Skill := preload("res://src/systems/ranger_skill_rules.gd")
const PlayerState := preload("res://src/runtime/world/player_combat_state.gd")
const PLAYER_SPEED := 245.0
const SIM_STEP_SECONDS := 1.0 / float(Skill.TICKS_PER_SECOND)
const MOBILITY_INPUT_BUFFER_TICKS := 3


func advance_player(state: PlayerState, world, tick: int, direction: Vector2, speed_scale: float = 1.0) -> Dictionary:
	if world == null or tick != int(world.tick):
		return {"ok": false, "error": "uncommitted_world_tick"}
	if state.actor_snapshot().is_empty() or world.room_instance_id != state._room_instance_id or world.world_revision != state._world_revision:
		return {"ok": false, "error": "stale_player_room"}
	if not direction.is_finite() or not is_finite(speed_scale):
		return {"ok": false, "error": "invalid_motion"}
	var actor := state.actor_snapshot()
	if tick <= int(actor.last_motor_tick):
		return {"ok": false, "error": "non_monotonic_motor_tick"}
	var values := state._values
	var displacement := Vector2.ZERO
	var facing: Vector2 = values.player_facing
	var next_velocity := state.player_velocity()
	if int(values.dash_remaining_ticks) > 0:
		facing = values.dash_direction
		displacement = facing * (Skill.DASH_TOTAL_DISTANCE / float(state.scaled_ticks(Skill.DASH_DURATION_TICKS, "dash_duration_multiplier")))
		if state.uses_accelerated_movement():
			next_velocity = Vector2.ZERO
	elif int(values.dodge_remaining_ticks) > 0:
		displacement = values.dodge_direction * (state.dodge_distance() / float(maxi(1, state.dodge_duration_ticks())))
		if state.uses_accelerated_movement():
			next_velocity = Vector2.ZERO
	elif direction != Vector2.ZERO:
		var phase := state._timeline.phase_at(tick)
		var action_scale := 0.38 if phase == "windup" else (0.72 if phase == "recovery" else 1.0)
		if phase == "idle":
			facing = direction
		if state.uses_accelerated_movement():
			var desired_velocity := direction * state.move_speed() * speed_scale * action_scale
			next_velocity = _approach_velocity(next_velocity, desired_velocity, state.acceleration() * SIM_STEP_SECONDS)
			displacement = next_velocity * SIM_STEP_SECONDS
		else:
			displacement = direction * state.move_speed() * speed_scale * action_scale * SIM_STEP_SECONDS
	elif state.uses_accelerated_movement():
		# Releasing movement decelerates through the same fixed-tick stat rather
		# than stopping the actor at an arbitrary presentation-frame boundary.
		next_velocity = _approach_velocity(next_velocity, Vector2.ZERO, state.acceleration() * SIM_STEP_SECONDS)
		displacement = next_velocity * SIM_STEP_SECONDS
	var result: Dictionary = state._registry.move_actor(state._ranger_id, displacement, tick)
	if bool(result.get("ok", false)):
		values.player_facing = facing
		values.player_last_displacement = result.displacement
		if state.uses_accelerated_movement():
			# Collision can shorten the submitted displacement. Preserve the
			# actual committed movement as the next velocity so a wall cannot
			# accumulate an unobservable speed impulse.
			values.player_velocity = Vector2(result.displacement) / SIM_STEP_SECONDS
	return result.duplicate(true)


static func _approach_velocity(current: Vector2, target: Vector2, max_delta: float) -> Vector2:
	if not current.is_finite() or not target.is_finite() or not is_finite(max_delta) or max_delta < 0.0:
		return Vector2.ZERO
	var delta := target - current
	var distance := delta.length()
	if distance <= max_delta or distance <= 0.000001:
		return target
	return current + delta / distance * max_delta
