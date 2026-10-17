class_name SimEntityView
extends RefCounted

## Detached read-only entity view.
##
## Views are value copies built at tick start; consumers can never mutate live
## records through them. The kernel-defined fields cover identity and
## lifecycle; records extend the view by overriding build_entity_view() with a
## subclass carrying typed domain fields.

var handle: SimEntityHandle = null
var stable_key: int = 0
var alive: bool = false
var room_instance_id: String = ""
var world_revision: int = -1


func fill_identity(assigned_handle: SimEntityHandle, key: int, instance_id: String, revision: int) -> void:
	handle = assigned_handle
	stable_key = key
	room_instance_id = instance_id
	world_revision = revision
