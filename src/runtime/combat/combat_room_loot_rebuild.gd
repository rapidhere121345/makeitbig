class_name TargetCombatRoomLoot
extends RefCounted

const LOOT_SOURCES := ["enemy_death", "wave_clear"]
const ACTIVE_STATE := "available"
const PICKED_STATE := "picked"
const LEFT_STATE := "left_in_room"
const FORFEITED_STATE := "forfeited_by_defeat"

var room_id := ""
var root_seed := 0
var _materializer: Object
var _placement_validator := Callable()
var _slots: Array[Dictionary] = []
var _entities: Dictionary = {}
var _spawned_slots: Dictionary = {}
var _events: Array[Dictionary] = []
var _pending_pickups: Array[Dictionary] = []
var _pickup_receipts: Array[Dictionary] = []
var _settlement: Dictionary = {}
var _drop_index := 0
var _request_sequence := 0


func configure(identifier: String, seed: int, slot_definitions: Array, materializer: Object, placement_validator: Callable) -> Dictionary:
	reset()
	if not _valid_id(identifier) or materializer == null or not materializer.has_method("generate_drop"):
		return _failure("invalid_loot_dependencies")
	if not placement_validator.is_valid():
		return _failure("loot_placement_validator_required")
	var normalized: Array[Dictionary] = []
	var seen: Dictionary = {}
	for raw_value: Variant in slot_definitions:
		if not raw_value is Dictionary:
			return _failure("invalid_loot_slot")
		var raw: Dictionary = raw_value
		var slot_id := String(raw.get("slot_id", ""))
		var source := String(raw.get("source", ""))
		if not _valid_id(slot_id) or seen.has(slot_id) or source not in LOOT_SOURCES:
			return _failure("invalid_loot_slot_identity")
		var raw_tags: Variant = raw.get("tags", [])
		if not raw_tags is Array:
			return _failure("invalid_loot_slot_tags")
		var tags: Array[String] = []
		for raw_tag: Variant in raw_tags as Array:
			if not raw_tag is String or not _valid_id(String(raw_tag)):
				return _failure("invalid_loot_slot_tag")
			tags.append(String(raw_tag))
		tags.sort()
		if tags.is_empty():
			return _failure("missing_loot_slot_tags")
		var pickup_radius: Variant = raw.get("pickup_radius", 18.0)
		if (typeof(pickup_radius) not in [TYPE_INT, TYPE_FLOAT]
				or not is_finite(float(pickup_radius)) or float(pickup_radius) <= 0.0):
			return _failure("invalid_loot_pickup_radius")
		if raw.has("guaranteed") and not raw["guaranteed"] is bool:
			return _failure("invalid_loot_guaranteed")
		var guarantee_family := String(raw.get("guarantee_family", ""))
		if not guarantee_family.is_empty() and not _valid_id(guarantee_family):
			return _failure("invalid_loot_guarantee_family")
		normalized.append({
			"slot_id": slot_id,
			"source": source,
			"tags": tags,
			"pickup_radius": float(pickup_radius),
			"guaranteed": bool(raw.get("guaranteed", false)),
			"guarantee_family": guarantee_family,
		})
		seen[slot_id] = true
	normalized.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.get("slot_id", "")) < String(right.get("slot_id", ""))
	)
	if normalized.is_empty():
		return _failure("missing_loot_slots")
	room_id = identifier
	root_seed = seed
	_materializer = materializer
	_placement_validator = placement_validator
	_slots = normalized
	return {"ok": true, "error": "", "snapshot": snapshot()}


func reset() -> void:
	room_id = ""
	root_seed = 0
	_materializer = null
	_placement_validator = Callable()
	_slots.clear()
	_entities.clear()
	_spawned_slots.clear()
	_events.clear()
	_pending_pickups.clear()
	_pickup_receipts.clear()
	_settlement.clear()
	_drop_index = 0
	_request_sequence = 0


func spawn(tick: int, raw_request: Variant) -> Dictionary:
	if _materializer == null:
		return _failure("loot_not_configured")
	if not _settlement.is_empty():
		return _failure("loot_already_settled")
	var raw: Variant = raw_request.snapshot() if raw_request is Object and raw_request.has_method("snapshot") else raw_request
	if not raw is Dictionary:
		return _failure("loot_spawn_request_not_dictionary")
	var request: Dictionary = raw
	var request_tick := int(request.get("tick", tick))
	if request_tick != tick or tick < 0:
		return _failure("invalid_loot_spawn_tick")
	if String(request.get("room_id", room_id)) != room_id:
		return _failure("loot_spawn_room_mismatch")
	var source := String(request.get("source", ""))
	var source_entity_key := String(request.get("source_entity_key", ""))
	if source not in LOOT_SOURCES or not _valid_id(source_entity_key):
		return _failure("invalid_loot_spawn_identity")
	var position: Variant = request.get("position", Vector2.INF)
	if not position is Vector2 or not (position as Vector2).is_finite():
		return _failure("invalid_loot_spawn_position")
	var tags: Array = request.get("tags", []) if request.get("tags", []) is Array else []
	var requested_slot := String(request.get("slot_id", ""))
	var slot: Dictionary = _select_slot(source, requested_slot)
	if slot.is_empty():
		return _failure("no_matching_loot_slot")
	var slot_id := String(slot["slot_id"])
	if not bool(_placement_validator.call(position, float(slot["pickup_radius"]))):
		return _failure("loot_spawn_position_blocked")
	var item: Variant = _materializer.call("generate_drop", root_seed, "%s/%s" % [room_id, slot_id], _drop_index, tags if not tags.is_empty() else slot["tags"], String(slot["guarantee_family"]))
	if not item is Dictionary or (item as Dictionary).is_empty():
		return _failure("loot_generation_failed")
	var entity_id := "loot/%s/%s" % [room_id, slot_id]
	if _entities.has(entity_id):
		return _failure("loot_entity_id_collision")
	var entity := {
		"loot_entity_id": entity_id,
		"slot_id": slot_id,
		"source": source,
		"source_entity_key": source_entity_key,
		"spawned_tick": tick,
		"position": position,
		"pickup_radius": float(slot["pickup_radius"]),
		"state": ACTIVE_STATE,
		"item": (item as Dictionary).duplicate(true),
		"picked_tick": -1,
		"picked_by": "",
	}
	_entities[entity_id] = entity
	_spawned_slots[slot_id] = entity_id
	_drop_index += 1
	_events.append({"tick": tick, "type": "loot_spawned", "loot_entity_id": entity_id, "source_entity_key": source_entity_key})
	return {"ok": true, "error": "", "entity": _entity_snapshot(entity)}


func request_pickup(tick: int, player_entity_key: String, loot_entity_id: String) -> Dictionary:
	if _materializer == null:
		return _failure("loot_not_configured")
	if not _settlement.is_empty():
		return _failure("loot_already_settled")
	if not _valid_id(player_entity_key) or not _valid_id(loot_entity_id) or tick < 0:
		return _failure("invalid_loot_pickup_request")
	if not _entities.has(loot_entity_id) or String(_entities[loot_entity_id].get("state", "")) != ACTIVE_STATE:
		return _failure("loot_not_available")
	for pending: Dictionary in _pending_pickups:
		if String(pending.get("loot_entity_id", "")) == loot_entity_id:
			return _failure("loot_pickup_already_queued")
	_request_sequence += 1
	var request := {
		"request_id": _request_sequence,
		"requested_tick": tick,
		"execute_tick": tick + 1,
		"player_entity_key": player_entity_key,
		"loot_entity_id": loot_entity_id,
	}
	_pending_pickups.append(request)
	return {"ok": true, "error": "", "request": request.duplicate(true)}


func commit_pickups(tick: int, player_health: float, player_position: Vector2, battle_over: bool, battle_victory: bool) -> Array[Dictionary]:
	var receipts: Array[Dictionary] = []
	if not _settlement.is_empty():
		return receipts
	var remaining: Array[Dictionary] = []
	for request: Dictionary in _pending_pickups:
		if int(request.get("execute_tick", -1)) > tick:
			remaining.append(request)
			continue
		var receipt: Dictionary = _commit_pickup(tick, request, player_health, player_position, battle_over, battle_victory)
		receipt["request_id"] = request.get("request_id", -1)
		receipts.append(receipt.duplicate(true))
		_pickup_receipts.append(receipt.duplicate(true))
	_pending_pickups = remaining
	return receipts


func settle(outcome: String) -> Dictionary:
	if _materializer == null:
		return _failure("loot_not_configured")
	if not _settlement.is_empty():
		return _settlement.duplicate(true)
	if outcome not in ["victory", "defeat", "abandoned"]:
		return _failure("invalid_loot_outcome")
	var ordered_ids: Array[String] = _sorted_entity_ids()
	var items: Array[Dictionary] = []
	for entity_id: String in ordered_ids:
		var entity: Dictionary = _entities[entity_id]
		if outcome == "victory":
			if String(entity.get("state", "")) == ACTIVE_STATE:
				entity["state"] = LEFT_STATE
			elif String(entity.get("state", "")) == PICKED_STATE:
				items.append((entity.get("item", {}) as Dictionary).duplicate(true))
		else:
			if String(entity.get("state", "")) in [ACTIVE_STATE, PICKED_STATE]:
				entity["state"] = FORFEITED_STATE
		_entities[entity_id] = entity
	_settlement = {
		"ok": true,
		"error": "",
		"outcome": outcome,
		"items": items,
		"entities": _entity_snapshots(),
		"event_count": _events.size(),
	}
	return _settlement.duplicate(true)


func snapshot() -> Dictionary:
	return {
		"room_id": room_id,
		"root_seed": root_seed,
		"slots": _slots.duplicate(true),
		"entities": _entity_snapshots(),
		"spawned_slots": _spawned_slots.duplicate(true),
		"events": _events.duplicate(true),
		"pending_pickups": _pending_pickups.duplicate(true),
		"pickup_receipts": _pickup_receipts.duplicate(true),
		"settlement": _settlement.duplicate(true),
	}


func settlement_snapshot() -> Dictionary:
	return _settlement.duplicate(true)


func _select_slot(source: String, requested_slot: String) -> Dictionary:
	for slot: Dictionary in _slots:
		if String(slot.get("source", "")) != source:
			continue
		if not requested_slot.is_empty() and String(slot.get("slot_id", "")) != requested_slot:
			continue
		if _spawned_slots.has(String(slot.get("slot_id", ""))):
			continue
		return slot
	return {}


func _commit_pickup(tick: int, request: Dictionary, player_health: float, player_position: Vector2, battle_over: bool, battle_victory: bool) -> Dictionary:
	var loot_entity_id := String(request.get("loot_entity_id", ""))
	if player_health <= 0.0 or (battle_over and not battle_victory):
		return _failure("loot_pickup_player_inactive")
	if not player_position.is_finite() or not _entities.has(loot_entity_id):
		return _failure("invalid_loot_pickup_commit")
	var entity: Dictionary = _entities[loot_entity_id]
	if String(entity.get("state", "")) != ACTIVE_STATE:
		return _failure("loot_not_available")
	var radius: float = float(entity.get("pickup_radius", 0.0))
	if player_position.distance_squared_to(entity.get("position", Vector2.INF)) > radius * radius + 0.000001:
		return _failure("loot_out_of_range")
	entity["state"] = PICKED_STATE
	entity["picked_tick"] = tick
	entity["picked_by"] = String(request.get("player_entity_key", ""))
	_entities[loot_entity_id] = entity
	_events.append({"tick": tick, "type": "loot_picked", "loot_entity_id": loot_entity_id, "player_entity_key": entity["picked_by"]})
	return {"ok": true, "error": "", "entity": _entity_snapshot(entity), "item": (entity.get("item", {}) as Dictionary).duplicate(true)}


func _entity_snapshots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entity_id: String in _sorted_entity_ids():
		result.append(_entity_snapshot(_entities[entity_id]))
	return result


func _sorted_entity_ids() -> Array[String]:
	var result: Array[String] = []
	for entity_id: Variant in _entities.keys():
		result.append(String(entity_id))
	result.sort()
	return result


func _entity_snapshot(entity: Dictionary) -> Dictionary:
	return entity.duplicate(true)


func _valid_id(value: String) -> bool:
	return not value.is_empty() and value == value.strip_edges() and not value.contains(" ")


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}
