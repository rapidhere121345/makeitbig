class_name MainCommandIntake
extends RoomCommandIntake

## View-side command intake for MainArena: reads the arena's gameplay snapshot
## and hands it to the input adapter at the moment the authority asks, so the
## timing matches the former direct calls from the collect phase.

var _arena: MainArena


func _init(arena: MainArena) -> void:
	_arena = arena


func collect_commands() -> Array[Dictionary]:
	return _arena.input_adapter.collect_commands(_arena.gameplay_snapshot())


func collect_loot_pickup_command() -> Dictionary:
	return _arena.input_adapter.collect_loot_pickup_command(_arena.gameplay_snapshot())
