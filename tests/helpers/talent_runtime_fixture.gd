extends RefCounted

const EarlyItemRegistryScript := preload("res://src/content/early_item_registry.gd")
const BuildResolverScript := preload("res://src/systems/build_resolver.gd")
const Protocol := preload("res://src/systems/combat_command_protocol.gd")
const PhasePort := preload("res://tests/helpers/callable_combat_phase_port.gd")

const CombatRoomRuntimeScript := preload("res://src/game/combat_room_runtime.gd")

const LAYER_ONE := [
	"ranger_steady_string",
	"ranger_long_breath",
	"ranger_keen_eye",
	"ranger_light_step",
	"ranger_recovery_pose",
]
const LAYER_TWO := [
	"ranger_close_turn",
	"ranger_continuation_calibration",
	"ranger_defocused_tracking",
]
const LOWER_EIGHT := LAYER_ONE + LAYER_TWO

var registry
var resolver
var _command_batches: Dictionary = {}


func _init() -> void:
	registry = EarlyItemRegistryScript.new()
	var errors: Array = registry.load_all()
	assert(errors.is_empty(), "talent fixture registry failed: %s" % str(errors))
	resolver = BuildResolverScript.new(registry)


func resolved_build(layer_three: Array = []) -> Dictionary:
	assert(layer_three.size() <= 2, "this regression explicitly allows at most two layer-3 nodes")
	return resolver.resolve(
		{
			"p": 0.50,
			"T": 2.0,
			"v": 200.0,
			"d": 320.0,
			"turn": 0.10,
			"damage": 100.0,
			"critical_chance": 0.0,
			"max_health": 1000.0,
		},
		{
			"gloves": _item("talent-critical-gloves", "turnfeather_gloves", "gloves", [], "breeding_split"),
			"ring_1": _item("talent-critical-ring", "hawk_eye_ring", "ring_1", [], "", "pack_hunt_mark"),
		},
		"piercing_arrow",
		{
			"talents": {"allocated_ids": LOWER_EIGHT + layer_three, "stance": "mid"},
			"talent_points": 30,
			"unlocked_classes": ["ranger"],
		}
	)


func _item(instance_id: String, base_id: String, slot: String, affixes: Array, rune_id: String = "", law_id: String = "") -> Dictionary:
	return {
		"instance_id": instance_id,
		"base_item_id": base_id,
		"slot": slot,
		"affixes": affixes,
		"rune_id": rune_id,
		"law_id": law_id,
		"source": {"type": "test_fixture", "id": "talent-runtime"},
		"law_seed": 52969,
	}


func start_session(layer_three: Array = [], presentation_enabled: bool = false):
	var build := resolved_build(layer_three)
	assert(bool(build.get("ok", false)), "BuildResolver rejected talent fixture: %s" % str(build.get("errors", [])))
	var runtime = CombatRoomRuntimeScript.new()
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(runtime)
	var started: Dictionary = runtime.start_session({
		"contract_id": "test.talent-runtime",
		"mode": "Manual",
		"preset_id": String(build.growth_classification),
		"seed": 52969,
		"presentation_enabled": presentation_enabled,
		"room": {
			"room_id": "room.talent-runtime",
			"layout_id": "rectangle_arena",
			"objective_id": "clear",
			"hazard_ids": [],
			"enemy_ids": ["melee_pursuer", "fan_ranged"],
			"elite_rule_ids": [],
			"boss_id": "",
			"drop_tags": [],
		},
		"framework_context": {
			"active_build": {"skills": ["piercing_arrow", "hunter_mark", "dash"]},
			"resolved_build": build,
		},
	})
	assert(bool(started.get("ok", false)), "runtime failed: %s" % str(started))
	return {"runtime": runtime, "arena": runtime.get("room_instance"), "build": build}


func free_session(session: Dictionary) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if session.has("runtime") and is_instance_valid(session.runtime):
		tree.root.remove_child(session.runtime)
		_command_batches.erase(session.arena.get_instance_id())
		session.runtime.free()


func player(arena) -> Dictionary:
	return arena.player_combat_state.snapshot(arena.sim_tick)


func configure_target(arena, offset: Vector2 = Vector2(120.0, 0.0)):
	# Only the actors are positioned by this fixture. The room already reset
	# State/Rules; no player counters, timeline ids or world ticks are rewritten.
	assert(bool(arena.teleport_actor("ranger", arena._arena_rect().get_center() + Vector2(0, -36)).get("ok", false)))
	var target = arena.enemies[0]
	assert(bool(arena.teleport_actor("enemy/%d" % target.entity_id, arena.player_position + offset).get("ok", false)))
	target.health = 1000000000.0
	target.maximum_health = target.health
	for other in arena.enemies.slice(1):
		assert(bool(arena.teleport_actor("enemy/%d" % other.entity_id, arena.player_position + Vector2(-180.0, -120.0)).get("ok", false)))
	var arena_id: int = arena.get_instance_id()
	_command_batches[arena_id] = []
	var callbacks := {
		"read_only_targets": Callable(arena, "_read_only_targets"),
		"set_elapsed": Callable(arena, "_simulation_set_elapsed"),
		"consume_player_events": Callable(arena, "_consume_player_events"),
		"update_room_rules": Callable(arena, "_update_room_rules_tick"),
		"refresh_hazard_states": Callable(arena, "_refresh_hazard_states_tick"),
		"collect_commands": func() -> Array[Dictionary]: return _collect(arena_id),
		"route_commands": Callable(arena, "_route_commands"),
		# Talent payload assertions use stationary targets, as the original
		# fixture did. Player rules, motor, projectiles and contacts all run.
		"update_enemies": func() -> void: pass,
		"advance_projectiles": Callable(arena, "_advance_piercing_projectiles_tick"),
		"resolve_hazard_hits": Callable(arena, "_resolve_hazard_hits_tick"),
		"check_battle_end": Callable(arena, "_check_battle_end"),
		"check_timeout": Callable(arena, "_simulation_check_timeout"),
	}
	var phase_port = PhasePort.new()
	var port_result: Dictionary = phase_port.bind(callbacks)
	assert(bool(port_result.get("ok", false)), "talent phase port bind failed: %s" % str(port_result))
	var configured: Dictionary = arena.combat_simulation.configure(arena.simulation_world, arena.player_combat_rules, phase_port)
	assert(bool(configured.get("ok", false)), "talent tick driver failed: %s" % str(configured))
	return target


func _collect(arena_id: int) -> Array[Dictionary]:
	var commands: Array[Dictionary] = []
	commands.assign(_command_batches.get(arena_id, []))
	_command_batches[arena_id] = []
	return commands


func step(arena, commands: Array[Dictionary] = []) -> Dictionary:
	_command_batches[arena.get_instance_id()] = commands.duplicate(true)
	var result: Dictionary = arena.combat_simulation.step()
	assert(bool(result.get("ok", false)), "talent simulation failed: %s" % str(result))
	return result


func advance_to(arena, tick: int) -> void:
	assert(tick >= int(arena.sim_tick), "talent fixture cannot rewind the world")
	while int(arena.sim_tick) < tick:
		step(arena)


func cast(arena, ability: String, target_id: int = 0, aim: Vector2 = Vector2.RIGHT) -> Dictionary:
	var tick := int(arena.sim_tick) + 1
	var sequence := int(arena.command_sequence)
	arena.command_sequence += 1
	var direction := aim.normalized()
	var command: Dictionary
	if ability == "dodge":
		command = Protocol.dodge(tick, "ranger", sequence, roundi(direction.x * 1000.0), roundi(direction.y * 1000.0))
	else:
		command = Protocol.cast(tick, "ranger", sequence, ability, target_id, roundi(direction.x * 1000.0), roundi(direction.y * 1000.0)) if ability in ["dash", "piercing_arrow"] else Protocol.cast(tick, "ranger", sequence, ability, target_id)
	var result := step(arena, [command])
	for receipt: Dictionary in result.player_step.receipts:
		if int((receipt.get("command", {}) as Dictionary).get("sequence", -1)) == sequence:
			return receipt
	return {"accepted": false, "reason": "receipt_missing"}


func wait_for_cast_ready(arena) -> void:
	var guard := 0
	while guard < 240:
		var slice := player(arena)
		if int(slice.attack_cooldown_ticks) == 0 and int(slice.dodge_remaining_ticks) == 0 and int(slice.dash_remaining_ticks) == 0 and slice.timeline.active.is_empty() and slice.timeline.buffered.is_empty():
			return
		step(arena)
		guard += 1
	assert(false, "talent fixture waited too long for the real action window")


func release_arrow(arena, target, aim: Vector2 = Vector2.ZERO) -> bool:
	wait_for_cast_ready(arena)
	var direction: Vector2 = aim if aim != Vector2.ZERO else arena.player_position.direction_to(target.position)
	var receipt := cast(arena, "piercing_arrow", target.entity_id, direction)
	if not bool(receipt.get("accepted", false)):
		return false
	var active: Dictionary = player(arena).timeline.active
	if active.is_empty():
		return false
	advance_to(arena, int(active.start_tick) + int(active.windup_ticks))
	return not arena.projectiles.is_empty()


func advance_projectiles(arena, maximum_ticks: int = 160) -> void:
	var advanced := 0
	while not arena.projectiles.is_empty() and advanced < maximum_ticks:
		step(arena)
		advanced += 1
	assert(arena.projectiles.is_empty(), "talent fixture projectile did not resolve")
