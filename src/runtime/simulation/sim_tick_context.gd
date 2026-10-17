class_name SimTickContext
extends RefCounted

## The complete typed state handed to every phase and port.
##
## A context exists for exactly one tick. Ports read the view and buffers and
## write only into the buffers they own per the phase contract; stores are
## exposed for movement commits and damage application inside their phases.

var tick: int = 0
var room_instance_id: String = ""
var world_revision: int = -1
var view: SimReadView = null
var stores: Array[SimEntityStore] = []
var intents: SimIntentBuffer = null
var hits: SimHitBuffer = null
var statuses: SimStatusBuffer = null
var structural: SimStructuralChangeBuffer = null
var phase_trace: Array[StringName] = []


func store_by_id(id: StringName) -> SimEntityStore:
	for store in stores:
		if store.store_id == id:
			return store
	return null
