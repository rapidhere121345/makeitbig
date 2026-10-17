class_name SimIntent
extends RefCounted

## Typed per-tick desire for one entity.
##
## Intents are the single hand-off shape between intent producers (encounter
## port, control commands) and the movement/action phases. Producers only ever
## express direction and a primary action; they never call movement themselves.

var entity: SimEntityHandle = null
var move_direction: Vector2 = Vector2.ZERO
var primary_action: bool = false
var source: StringName = &""


static func make(target: SimEntityHandle, direction: Vector2, press_action: bool, intent_source: StringName) -> SimIntent:
	var intent := SimIntent.new()
	intent.entity = target
	intent.move_direction = direction
	intent.primary_action = press_action
	intent.source = intent_source
	return intent
