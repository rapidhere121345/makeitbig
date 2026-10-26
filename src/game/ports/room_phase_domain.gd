extends "res://src/runtime/combat/combat_phase_port.gd"

## Typed production phase domain for the fixed combat tick.
##
## This is the room-domain side of the CombatSimulation authority seam. It is
## a CombatPhasePort subclass declared by the room owner itself, and every
## phase dispatches through a typed owner reference. There is deliberately no
## has_method protocol, no string .call() indirection and no separate adapter
## script. When the remaining Main-owned phases migrate into the runtime room
## domain, this class shrinks with them.

var _owner: MainArena = null


func bind(owner: MainArena) -> Dictionary:
	if owner == null or not is_instance_valid(owner):
		return {"ok": false, "error": "combat_phase_room_unavailable"}
	_owner = owner
	return {"ok": true, "error": ""}


func is_ready() -> bool:
	return _owner != null and is_instance_valid(_owner)


func read_only_targets() -> Array[Dictionary]:
	return _owner._read_only_targets()


func set_elapsed(value: float) -> void:
	_owner._simulation_set_elapsed(value)


func consume_player_events(result: Dictionary) -> void:
	_owner._consume_player_events(result)


func update_room_rules() -> void:
	_owner._update_room_rules_tick()


func refresh_hazard_states() -> void:
	_owner._refresh_hazard_states_tick()


func collect_commands() -> Array[Dictionary]:
	return _owner._simulation_collect_commands()


func route_commands(commands: Array[Dictionary]) -> Dictionary:
	return _owner._route_commands(commands)


func update_enemies() -> void:
	_owner._update_enemies_tick()


func advance_projectiles() -> void:
	_owner._advance_piercing_projectiles_tick()


func resolve_hazard_hits() -> void:
	_owner._resolve_hazard_hits_tick()


func check_battle_end() -> void:
	_owner._check_battle_end()


func room_terminal_locked() -> bool:
	return _owner != null and is_instance_valid(_owner) and bool(_owner.battle_over)


func check_timeout() -> void:
	_owner._simulation_check_timeout()
