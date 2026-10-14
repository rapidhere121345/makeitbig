class_name SmokeInputDriver
extends RefCounted

## Deterministic Manual smoke inputs. This driver reads detached observations
## and emits the same protocol commands available to a player.
const Protocol := preload("res://src/systems/combat_command_protocol.gd")
const Timeline := preload("res://src/systems/player_action_timeline.gd")
const Skill := preload("res://src/systems/ranger_skill_rules.gd")
const Query := preload("res://src/runtime/geometry/combat_query.gd")


func decide(observation: Dictionary, next_sequence: int) -> Dictionary:
	var player: Dictionary = observation.player
	var position: Vector2 = player.player_position
	var target: Dictionary = {}
	var nearest := INF
	for candidate: Dictionary in observation.targets:
		if float(candidate.health) <= 0.0:
			continue
		var distance := position.distance_squared_to(candidate.position)
		if distance < nearest or (is_equal_approx(distance, nearest) and (target.is_empty() or int(candidate.entity_id) < int(target.entity_id))):
			nearest = distance
			target = candidate
	var commands: Array[Dictionary] = []
	if target.is_empty():
		return {"commands": commands, "next_sequence": next_sequence}
	var tick := int(player.sim_tick)
	var toward: Vector2 = target.position - position
	var distance := toward.length()
	var direction: Vector2 = toward.normalized() if distance > 0.001 else player.player_facing
	var vertical := Vector2.DOWN if position.y < target.position.y else Vector2.UP
	var dodge_required := requires_dodge(observation)
	var range_limit := float(observation.targeting_distance)
	if dodge_required:
		commands.append(Protocol.move(tick, "ranger", next_sequence, roundi(vertical.x * 1000.0), roundi(vertical.y * 1000.0), 1000))
		next_sequence += 1
	elif distance > range_limit * 0.82:
		commands.append(Protocol.move(tick, "ranger", next_sequence, roundi(direction.x * 1000.0), roundi(direction.y * 1000.0), 720))
		next_sequence += 1
	var skills: Array = player.equipped_skills
	if int(player.hunter_mark_cooldown_ticks) == 0 and skills.size() > 1 and skills[1] == "hunter_mark":
		commands.append(Protocol.cast(tick, "ranger", next_sequence, "hunter_mark", int(target.entity_id)))
		next_sequence += 1
	if int(player.dodge_cooldown_ticks) == 0 and dodge_required:
		commands.append(Protocol.dodge(tick, "ranger", next_sequence, roundi(vertical.x * 1000.0), roundi(vertical.y * 1000.0)))
		next_sequence += 1
	if distance <= range_limit and int(player.attack_cooldown_ticks) <= Timeline.INPUT_BUFFER_TICKS:
		commands.append(Protocol.cast(tick, "ranger", next_sequence, "piercing_arrow", int(target.entity_id), roundi(direction.x * 1000.0), roundi(direction.y * 1000.0)))
		next_sequence += 1
	return {"commands": commands, "next_sequence": next_sequence}


func requires_dodge(observation: Dictionary) -> bool:
	var player: Dictionary = observation.player
	if int(player.dodge_cooldown_ticks) > 0:
		return false
	var position: Vector2 = player.player_position
	for hazard: Dictionary in observation.hazards:
		if String(hazard.id) != "moving_fireline" or String(hazard.phase) != "active":
			continue
		var line_x := float((hazard.origin as Vector2).x)
		var dodge_step := Skill.DODGE_SPEED / float(Skill.TICKS_PER_SECOND)
		if absf(position.x - line_x) <= float(hazard.width) * 0.5 + dodge_step:
			return true
	var boss: Dictionary = observation.boss
	return not boss.is_empty() and int(boss.impact_tick) == int(player.sim_tick) + 1 and Query.shape_contains(boss.target_shape, position)
