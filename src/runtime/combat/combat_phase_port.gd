class_name CombatPhasePort
extends RefCounted

## Typed room boundary for the fixed combat phases.
##
## CombatSimulation owns phase order and the player domain. The mounted room
## owns this port for room observations, encounter/hazard work, projectile
## advancement and terminal projection. Production supplies a typed domain
## object that overrides every phase method (the room owner declares its
## domain inline); production must not route this boundary through string-call
## adapters or Callable bags. Test doubles may compose phases from tests/.

func read_only_targets() -> Array[Dictionary]:
	return []

func set_elapsed(_value: float) -> void:
	pass

func consume_player_events(_result: Dictionary) -> void:
	pass

func update_room_rules() -> void:
	pass

func refresh_hazard_states() -> void:
	pass

func collect_commands() -> Array[Dictionary]:
	return []

func route_commands(_commands: Array[Dictionary]) -> Dictionary:
	return {}

func update_enemies() -> void:
	pass

func advance_projectiles() -> void:
	pass

func resolve_hazard_hits() -> void:
	pass

func check_battle_end() -> void:
	pass


## True once the room reached a terminal decision: the loot window may keep
## the simulation stepping, but enemy planning must stop so survivors of a
## victorious hunt cannot keep attacking a ranger whose combat actions are
## locked. Base fails open (not terminal) for isolated domain fixtures.
func room_terminal_locked() -> bool:
	return false

func check_timeout() -> void:
	pass

func is_ready() -> bool:
	return true
