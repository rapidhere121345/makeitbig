class_name SimReadView
extends RefCounted

## Detached world read view for one tick.
##
## Built once per tick in the begin-tick phase from live entities sorted by
## stable key. Ports and queries read this view; nothing inside the tick may
## treat it as writable state.

var tick: int = 0
var room_instance_id: String = ""
var world_revision: int = -1
var entities: Array[SimEntityView] = []


static func build(current_tick: int, instance_id: String, revision: int, stores: Array[SimEntityStore]) -> SimReadView:
	var view := SimReadView.new()
	view.tick = current_tick
	view.room_instance_id = instance_id
	view.world_revision = revision
	var merged: Array[SimEntityView] = []
	for store in stores:
		merged.append_array(store.build_views_sorted_by_key())
	merged.sort_custom(func(left: SimEntityView, right: SimEntityView) -> bool:
		return left.stable_key < right.stable_key)
	view.entities = merged
	return view


func entity_count() -> int:
	return entities.size()
