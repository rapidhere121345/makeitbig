class_name CombatSimulation
extends RefCounted

## Fixed-tick room orchestration. Player phases run in PlayerCombatRules;
## callbacks carry only room/input/target/projectile/enemy boundaries.
const Rules := preload("res://src/systems/player_combat_rules.gd")
const REQUIRED_CALLBACKS: Array[String] = [
	"read_only_targets", "set_elapsed", "consume_player_events",
	"update_room_rules", "refresh_hazard_states", "collect_commands", "route_commands",
	"update_enemies", "advance_projectiles", "resolve_hazard_hits", "check_battle_end", "check_timeout",
]

var _world
var _rules: Rules
var _callbacks: Dictionary = {}


func configure(world, player_rules: Rules, callbacks: Dictionary) -> Dictionary:
	if world == null or player_rules == null or int(world.tick_rate) != 30:
		return {"ok": false, "error": "simulation_dependencies_unavailable"}
	for name: String in REQUIRED_CALLBACKS:
		var callback: Variant = callbacks.get(name, Callable())
		if not callback is Callable or not (callback as Callable).is_valid():
			return {"ok": false, "error": "missing_callback:%s" % name}
	_world = world
	_rules = player_rules
	_callbacks = callbacks.duplicate()
	return {"ok": true, "error": ""}


func step() -> Dictionary:
	if _world == null or _callbacks.is_empty():
		return {"ok": false, "error": "simulation_not_configured"}
	var world_step: Dictionary = _world.step()
	var tick := int(world_step.tick)
	_invoke("set_elapsed", [float(tick) / float(_world.tick_rate)])
	var targets: Array[Dictionary] = _targets()
	var prepared := _rules.begin_tick(tick, targets)
	if not bool(prepared.get("ok", false)):
		return prepared
	_invoke("consume_player_events", [prepared])
	_invoke("update_room_rules")
	_invoke("refresh_hazard_states")
	var commands_value: Variant = _invoke("collect_commands")
	var commands: Array = commands_value if commands_value is Array else []
	var routed_value: Variant = _invoke("route_commands", [commands])
	if not routed_value is Dictionary:
		return {"ok": false, "error": "command_route_invalid", "tick": tick}
	var advanced := _rules.advance_tick(tick, routed_value, _targets())
	if not bool(advanced.get("ok", false)):
		return advanced
	_invoke("consume_player_events", [advanced])
	_invoke("update_enemies")
	_invoke("advance_projectiles")
	_invoke("resolve_hazard_hits")
	_invoke("check_battle_end")
	_invoke("check_timeout")
	return {"ok": true, "error": "", "tick": tick, "world_step": world_step.duplicate(true), "player_step": advanced}


func _targets() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var value: Variant = _invoke("read_only_targets")
	if value is Array:
		for target: Dictionary in value:
			result.append(target.duplicate(true))
	return result


func _invoke(name: String, arguments: Array = []) -> Variant:
	return (_callbacks[name] as Callable).callv(arguments)
