class_name SimCommand
extends RefCounted

## Typed external command.
##
## Commands are the only sanctioned outside-in mutation requests. They carry a
## kind discriminator plus only the fields that kind reads; no gameplay data
## travels in untyped dictionaries. The kernel stamps room identity and world
## revision on queue and rejects stale stamps fail-closed.

enum Kind {
	SPAWN = 1,
	DESPAWN = 2,
	CONTROL = 3,
}

var kind: int = 0
var submit_sequence: int = 0
var room_instance_id: String = ""
var world_revision: int = -1
var store_id: StringName = &""

# SPAWN: a fully constructed record instance deferred into the store.
var spawn_record: Variant = null

# DESPAWN: which live entity to retire.
var target: SimEntityHandle = null

# CONTROL: movement direction plus a primary action press for this tick.
var move_direction: Vector2 = Vector2.ZERO
var primary_action: bool = false


static func spawn_entity(record: Variant, target_store: StringName = &"") -> SimCommand:
	var command := SimCommand.new()
	command.kind = Kind.SPAWN
	command.spawn_record = record
	command.store_id = target_store
	return command


static func despawn_entity(entity: SimEntityHandle, target_store: StringName = &"") -> SimCommand:
	var command := SimCommand.new()
	command.kind = Kind.DESPAWN
	command.target = entity
	command.store_id = target_store
	return command


static func control(entity: SimEntityHandle, direction: Vector2, press_action: bool, target_store: StringName = &"") -> SimCommand:
	var command := SimCommand.new()
	command.kind = Kind.CONTROL
	command.target = entity
	command.move_direction = direction
	command.primary_action = press_action
	command.store_id = target_store
	return command


func kind_name() -> StringName:
	match kind:
		Kind.SPAWN: return &"spawn"
		Kind.DESPAWN: return &"despawn"
		Kind.CONTROL: return &"control"
	return &"unknown"
