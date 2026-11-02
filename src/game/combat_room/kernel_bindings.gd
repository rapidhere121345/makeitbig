class_name KernelBindings
extends RefCounted

## State of the room's kernel bindings: the Ranger and Boss arrow flight
## drivers, the Boss combat domain with its detached target views, the stable
## key to enemy entity id map and the death settlement cursors. MainArena owns
## the instance; KernelReconciler, RoomActorSetup and PiercingArrows share it
## through MainArena.kernel_bindings.

const RangerArrowFlightScript := preload("res://src/runtime/combat/ranger_arrow_flight.gd")
const BossArrowFlightScript := preload("res://src/runtime/combat/boss_arrow_flight.gd")

var arrow_flight := RangerArrowFlightScript.new()
var boss_flight := BossArrowFlightScript.new()
var boss_domain: BossCombatDomain = null
var boss_domain_targets: Dictionary = {}
var boss_settlement_cursor := 0
## Stable entity key ("actor/<key>") to legacy enemy entity id, rebuilt at
## every room registration boundary for death settlement reconciliation.
var enemy_stable_keys: Dictionary = {}
var settlement_cursor := 0


## Clears the per-room identity and cursor state; the flight drivers and the
## Boss domain are rebound separately by KernelReconciler.
func reset_room_state() -> void:
	enemy_stable_keys.clear()
	settlement_cursor = 0
	boss_domain_targets.clear()
	boss_settlement_cursor = 0
