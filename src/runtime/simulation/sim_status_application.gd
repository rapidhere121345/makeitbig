class_name SimStatusApplication
extends RefCounted

## Typed status-effect request.
##
## Carries a status identifier plus duration and magnitude. The kernel only
## moves these between phases; interpretation belongs to the combat port and
## the record's own status state.

var source: SimEntityHandle = null
var target: SimEntityHandle = null
var status_id: StringName = &""
var duration_ticks: int = 0
var magnitude: int = 0


static func make(from_entity: SimEntityHandle, to_entity: SimEntityHandle, id: StringName, duration: int, power: int) -> SimStatusApplication:
	var application := SimStatusApplication.new()
	application.source = from_entity
	application.target = to_entity
	application.status_id = id
	application.duration_ticks = duration
	application.magnitude = power
	return application
