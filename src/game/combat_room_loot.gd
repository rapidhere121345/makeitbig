class_name CombatRoomLoot
extends RefCounted

## Composition adapter for the single room-loot authority.
##
## Main owns the room lifecycle and input boundary, while
## TargetCombatRoomLoot owns every loot entity, pickup request, deterministic
## materialization and settlement transition.  This adapter preserves the
## room-facing protocol used by the game shell without keeping a second ledger.

const AuthorityScript := preload("res://src/runtime/combat/combat_room_loot_rebuild.gd")
const GeneratorScript := preload("res://src/systems/equipment_drop_generator.gd")
const PlacementPortScript := preload("res://src/runtime/world/room_loot_placement_port.gd")

var _authority: TargetCombatRoomLoot = null


func reset() -> void:
	_authority = null


func configure(
	room: Dictionary,
	room_id: String,
	root_seed: int,
	item_registry,
	placement_port: Variant
) -> Dictionary:
	reset()
	if not room.has("loot_slots"):
		return {"ok": true, "error": "", "enabled": false}
	var slots_value: Variant = room.get("loot_slots")
	if not slots_value is Array:
		return _failure("invalid_loot_slots")
	if (slots_value as Array).is_empty():
		return {"ok": true, "error": "", "enabled": false}
	if item_registry == null:
		return _failure("loot_item_registry_unavailable")
	if not placement_port is PlacementPortScript:
		return _failure("loot_placement_port_required")
	var generator := GeneratorScript.new(item_registry)
	var authority := AuthorityScript.new()
	var configured: Dictionary = authority.configure(room_id, root_seed, slots_value, generator, placement_port)
	if not bool(configured.get("ok", false)):
		return configured
	_authority = authority
	return {"ok": true, "error": "", "enabled": true}


func enabled() -> bool:
	return _authority != null


func has_unsettled_entities() -> bool:
	if _authority == null:
		return false
	var settlement: Dictionary = _authority.settlement_snapshot()
	if not settlement.is_empty():
		return false
	return not (_authority.snapshot().get("entities", []) as Array).is_empty()


func spawn_for_source(tick: int, source: String, source_entity_id: int, position: Vector2) -> Dictionary:
	if _authority == null or not position.is_finite():
		return _failure("room_loot_disabled")
	if source not in ["enemy_death", "wave_clear"]:
		return _failure("invalid_loot_source")
	var source_key := "wave_clear" if source_entity_id <= 0 else "enemy/%d" % source_entity_id
	var result: Dictionary = _authority.spawn(tick, {
		"tick": tick,
		"room_id": _authority.room_id,
		"source": source,
		"source_entity_key": source_key,
		"position": position,
	})
	return result


func request_pickup(tick: int, active: bool, battle_over: bool, battle_victory: bool, loot_entity_id: String) -> Dictionary:
	if _authority == null:
		return _failure("room_loot_disabled")
	# A victory ends combat but leaves the room open for an explicit loot window.
	# Defeat closes the room immediately and never permits a queued pickup.
	if not active or (battle_over and not battle_victory):
		return _failure("loot_pickup_room_inactive")
	var result: Dictionary = _authority.request_pickup(tick, "ranger", loot_entity_id.strip_edges())
	if bool(result.get("ok", false)):
		result["accepted"] = true
		result["queued"] = true
	else:
		result["accepted"] = false
	return result


func process_pickups(tick: int, player_health: float, player_position: Vector2, battle_over: bool, battle_victory: bool) -> void:
	if _authority == null:
		return
	_authority.commit_pickups(tick, player_health, player_position, battle_over, battle_victory)


func settle(outcome: String) -> Dictionary:
	if _authority == null:
		return {"ok": true, "error": "", "enabled": false, "settlement": {}}
	var settled: Dictionary = _authority.settle(outcome)
	if not bool(settled.get("ok", false)):
		return _failure("loot_settlement_failed:%s" % String(settled.get("error", "invalid_receipt")))
	return {"ok": true, "error": "", "enabled": true, "settlement": settled.duplicate(true)}


func settlement_snapshot() -> Dictionary:
	if _authority == null:
		return {}
	return _authority.settlement_snapshot()


func snapshot() -> Dictionary:
	if _authority == null:
		return {"enabled": false, "entities": [], "events": [], "settlement": {}}
	var result: Dictionary = _authority.snapshot()
	result["enabled"] = true
	return result


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}
