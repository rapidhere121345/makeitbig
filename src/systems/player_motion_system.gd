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
	if int(values.dash_remaining_ticks) > 0:
		facing = values.dash_direction
		displacement = facing * (Skill.DASH_TOTAL_DISTANCE / float(state.scaled_ticks(Skill.DASH_DURATION_TICKS, "dash_duration_multiplier")))
	elif int(values.dodge_remaining_ticks) > 0:
		displacement = values.dodge_direction * Skill.DODGE_SPEED * SIM_STEP_SECONDS
	elif direction != Vector2.ZERO:
		var phase := state._timeline.phase_at(tick)
		var action_scale := 0.38 if phase == "windup" else (0.72 if phase == "recovery" else 1.0)
		if phase == "idle":
			facing = direction
		displacement = direction * PLAYER_SPEED * speed_scale * action_scale * SIM_STEP_SECONDS
	var result: Dictionary = state._registry.move_actor(state._ranger_id, displacement, tick)
	if bool(result.get("ok", false)):
		values.player_facing = facing
		values.player_last_displacement = result.displacement
	return result.duplicate(true)
