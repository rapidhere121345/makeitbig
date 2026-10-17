class_name SimStructuralChange
extends RefCounted

## One deferred structural change committed at tick end.
##
## Death settlement and action-commit enqueue changes here; nothing mutates the
## entity stores mid-tick except through tombstoning, which keeps dead entities
## addressable-but-inert until this buffer commits.

enum Kind {
	SPAWN = 1,
	RETIRE = 2,
}

var kind: int = 0
var spawn_record: Variant = null
var retired_handle: SimEntityHandle = null
var target_store_id: StringName = &""
var origin: StringName = &""


static func spawn_entity(record: Variant, target_store: StringName, change_origin: StringName) -> SimStructuralChange:
	var change := SimStructuralChange.new()
	change.kind = Kind.SPAWN
	change.spawn_record = record
	change.target_store_id = target_store
	change.origin = change_origin
	return change


static func retire(entity: SimEntityHandle, change_origin: StringName) -> SimStructuralChange:
	var change := SimStructuralChange.new()
	change.kind = Kind.RETIRE
	change.retired_handle = entity
	change.origin = change_origin
	return change
