class_name CombatLootLedger
extends RefCounted

## Room-local loot authority. The generator remains a pure materializer; this
## ledger owns spawn identity, pickup state, and one-shot settlement.

const ACTIVE_STATE := "available"
const PICKED_STATE := "picked"
const LEFT_STATE := "left_in_room"
const FORFEITED_STATE := "forfeited_by_defeat"

var _room_id := ""
var _root_seed := 0
var _generator: Object
var _configured := false
var _entities: Dictionary = {}
var _spawned_slots: Dictionary = {}
var _events: Array[Dictionary] = []
var _settlement: Dictionary = {}


func configure(room_id: String, root_seed: int, generator: Object) -> Dictionary:
	if room_id.strip_edges().is_empty() or generator == null or not generator.has_method("generate_drop"):
		return _failure("loot_dependencies_unavailable")
	_room_id = room_id.strip_edges()
	_root_seed = root_seed
	_generator = generator
	_configured = true
	_entities.clear()
	_spawned_slots.clear()
	_events.clear()
	_settlement.clear()
	return {"ok": true, "error": ""}


func spawn(
	tick: int,
	slot_id: String,
	source_entity_id: int,
	position: Vector2,
	drop_index: int,
	drop_tags: Array,
	guarantee_family: String = "",
	pickup_radius: float = 18.0
) -> Dictionary:
	if not _configured:
		return _failure("loot_not_configured")
	if not _settlement.is_empty():
		return _failure("loot_already_settled")
	if tick < 0 or source_entity_id <= 0 or drop_index < 0 or slot_id.strip_edges().is_empty():
		return _failure("invalid_loot_spawn")
	if not position.is_finite() or not is_finite(pickup_radius) or pickup_radius <= 0.0:
		return _failure("invalid_loot_geometry")
	var normalized_slot := slot_id.strip_edges()
	if _spawned_slots.has(normalized_slot):
		return _failure("loot_slot_already_spawned")
	var item: Variant = _generator.call("generate_drop", _root_seed, "%s/%s" % [_room_id, normalized_slot], drop_index, drop_tags, guarantee_family)
	if not item is Dictionary or (item as Dictionary).is_empty():
		return _failure("loot_generation_failed")
	var entity_id := "loot/%s/%s" % [_room_id, normalized_slot]
	if _entities.has(entity_id):
		return _failure("loot_entity_id_collision")
	var entity := {
		"loot_entity_id": entity_id,
		"slot_id": normalized_slot,
		"source_entity_id": source_entity_id,
		"spawned_tick": tick,
		"position": position,
		"pickup_radius": pickup_radius,
		"state": ACTIVE_STATE,
		"item": (item as Dictionary).duplicate(true),
		"picked_tick": -1,
		"picked_by": 0,
	}
	_entities[entity_id] = entity
	_spawned_slots[normalized_slot] = entity_id
	_events.append({"tick": tick, "type": "loot_spawned", "loot_entity_id": entity_id, "source_entity_id": source_entity_id})
	return {"ok": true, "error": "", "entity": _entity_snapshot(entity)}


func pickup(tick: int, player_entity_id: int, loot_entity_id: String, player_position: Vector2) -> Dictionary:
	if not _configured:
		return _failure("loot_not_configured")
	if not _settlement.is_empty():
		return _failure("loot_already_settled")
	if tick < 0 or player_entity_id <= 0 or not player_position.is_finite():
		return _failure("invalid_pickup")
	if not _entities.has(loot_entity_id):
		return _failure("unknown_loot_entity")
	var entity: Dictionary = _entities[loot_entity_id]
	if String(entity.state) != ACTIVE_STATE:
		return _failure("loot_not_available")
	var distance_squared: float = player_position.distance_squared_to(entity.position)
	var radius: float = float(entity.pickup_radius)
	if distance_squared > radius * radius + 0.000001:
		return _failure("loot_out_of_range")
	entity.state = PICKED_STATE
	entity.picked_tick = tick
	entity.picked_by = player_entity_id
	_entities[loot_entity_id] = entity
	_events.append({"tick": tick, "type": "loot_picked", "loot_entity_id": loot_entity_id, "player_entity_id": player_entity_id})
	return {"ok": true, "error": "", "entity": _entity_snapshot(entity), "item": (entity.item as Dictionary).duplicate(true)}


func settle(outcome: String) -> Dictionary:
	if not _configured:
		return _failure("loot_not_configured")
	if not _settlement.is_empty():
		return _settlement.duplicate(true)
	if outcome not in ["victory", "defeat", "abandoned"]:
		return _failure("invalid_loot_outcome")
	var ordered_ids: Array[String] = []
	for entity_id: Variant in _entities.keys():
		ordered_ids.append(String(entity_id))
	ordered_ids.sort()
	var items: Array[Dictionary] = []
	for entity_id: String in ordered_ids:
		var entity: Dictionary = _entities[entity_id]
		if outcome == "victory":
			if String(entity.state) == ACTIVE_STATE:
				entity.state = LEFT_STATE
			elif String(entity.state) == PICKED_STATE:
				items.append((entity.item as Dictionary).duplicate(true))
		else:
			if String(entity.state) in [ACTIVE_STATE, PICKED_STATE]:
				entity.state = FORFEITED_STATE
		_entities[entity_id] = entity
	_settlement = {
		"ok": true,
		"error": "",
		"outcome": outcome,
		"items": items,
		"entities": snapshot().entities,
		"event_count": _events.size(),
	}
	return _settlement.duplicate(true)


func snapshot() -> Dictionary:
	var ordered_ids: Array[String] = []
	for entity_id: Variant in _entities.keys():
		ordered_ids.append(String(entity_id))
	ordered_ids.sort()
	var entities: Array[Dictionary] = []
	for entity_id: String in ordered_ids:
		entities.append(_entity_snapshot(_entities[entity_id]))
	return {
		"room_id": _room_id,
		"root_seed": _root_seed,
		"entities": entities,
		"spawned_slots": _spawned_slots.duplicate(true),
		"events": _events.duplicate(true),
		"settlement": _settlement.duplicate(true),
	}


func _entity_snapshot(entity: Dictionary) -> Dictionary:
	var result := entity.duplicate(true)
	result["position"] = entity.position
	return result


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}
