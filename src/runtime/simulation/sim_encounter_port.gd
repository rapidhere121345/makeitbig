class_name SimEncounterPort
extends RefCounted

## Narrow integration port for encounter direction and death reaction.

const DeathSettlementNotificationScript := preload("res://src/runtime/combat/death_settlement_notification.gd")


## INTENT phase: append SimIntent entries for AI-driven entities in stable-key
## order. Producers never mutate records directly.
func produce_intents(_ctx: SimTickContext) -> void:
	pass


## DEATH_SETTLEMENT phase: notified for each entity that tombstoned this tick,
## in stable-key order. Spawn/despawn reactions must go through the structural
## buffer so changes stay deferred to tick end.
func on_death(_entity_view: SimEntityView, _ctx: SimTickContext) -> void:
	pass


## Receives the detached encounter notification emitted by DeathSettlement.
## Ports that do not use the explicit settlement path keep the entity-view
## on_death hook above as their default.
func on_death_settlement(_notification: Variant, _ctx: SimTickContext) -> void:
	pass
