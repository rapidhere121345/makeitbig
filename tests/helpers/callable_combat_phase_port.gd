extends "res://src/runtime/combat/combat_phase_port.gd"

## Test-only composition adapter. Production uses MainArena.RoomPhaseDomain;
## tests can replace individual phase owners without weakening the typed
## CombatSimulation boundary.

const REQUIRED: Array[String] = [
	"read_only_targets", "set_elapsed", "consume_player_events",
	"update_room_rules", "refresh_hazard_states", "collect_commands", "route_commands",
	"update_enemies", "advance_projectiles", "resolve_hazard_hits", "check_battle_end", "check_timeout",
]

var _callbacks: Dictionary = {}

func bind(callbacks: Dictionary) -> Dictionary:
	for name: String in REQUIRED:
		var callback: Variant = callbacks.get(name, Callable())
		if not callback is Callable or not (callback as Callable).is_valid():
			return {"ok": false, "error": "missing_callback:%s" % name}
	_callbacks = callbacks.duplicate()
	return {"ok": true, "error": ""}

func is_ready() -> bool:
	for name: String in REQUIRED:
		var callback: Variant = _callbacks.get(name, Callable())
		if not callback is Callable or not (callback as Callable).is_valid():
			return false
	return true

func read_only_targets() -> Array[Dictionary]:
	return _array_of_dicts(_call("read_only_targets"))

func set_elapsed(value: float) -> void:
	_call("set_elapsed", [value])

func consume_player_events(result: Dictionary) -> void:
	_call("consume_player_events", [result])

func update_room_rules() -> void:
	_call("update_room_rules")

func refresh_hazard_states() -> void:
	_call("refresh_hazard_states")

func collect_commands() -> Array[Dictionary]:
	return _array_of_dicts(_call("collect_commands"))

func route_commands(commands: Array[Dictionary]) -> Dictionary:
	var value: Variant = _call("route_commands", [commands])
	return value if value is Dictionary else {}

func update_enemies() -> void:
	_call("update_enemies")

func advance_projectiles() -> void:
	_call("advance_projectiles")

func resolve_hazard_hits() -> void:
	_call("resolve_hazard_hits")

func check_battle_end() -> void:
	_call("check_battle_end")

func check_timeout() -> void:
	_call("check_timeout")

func _call(name: String, arguments: Array = []) -> Variant:
	return (_callbacks[name] as Callable).callv(arguments)

func _array_of_dicts(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if value is Array:
		for entry: Variant in value:
			if entry is Dictionary:
				result.append(entry)
	return result
