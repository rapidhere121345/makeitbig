extends "res://src/runtime/simulation/sim_encounter_port.gd"

## Fake encounter integration: emits configured move intents in stable-key
## order and records death notifications.

var move_directions: Dictionary = {}  # stable_key -> Vector2 (lookup only)

var intent_log: Array = []  # [tick, stable_key] in append order
var deaths: Array[int] = []


func produce_intents(ctx: SimTickContext) -> void:
	for entity_view in ctx.view.entities:
		if move_directions.has(entity_view.stable_key):
			ctx.intents.append(SimIntent.make(
				entity_view.handle,
				move_directions[entity_view.stable_key],
				false,
				&"fake_encounter"
			))
			intent_log.append([ctx.tick, entity_view.stable_key])


func on_death(entity_view: SimEntityView, _ctx: SimTickContext) -> void:
	deaths.append(entity_view.stable_key)
