class_name CombatRoomLoot
extends RefCounted

## Room-owned loot lifecycle. Main supplies room identity and observations;
## this facade owns slot validation, pickup queueing and the one-shot ledger.

const LedgerScript := preload("res://src/game/combat_loot_ledger.gd")
const GeneratorScript := preload("res://src/systems/equipment_drop_generator.gd")

var _ledger
var _slots: Array[Dictionary] = []
var _settlement: Dictionary = {}
var _pickup_requests: Array[Dictionary] = []
var _pickup_receipts: Array[Dictionary] = []
var _request_sequence := 0
var _drop_index := 0


func reset() -> void:
	_ledger = null
	_slots.clear()
	_settlement.clear()
	_pickup_requests.clear()
	_pickup_receipts.clear()
	_request_sequence = 0
	_drop_index = 0


func configure(room: Dictionary, room_id: String, root_seed: int, item_registry) -> Dictionary:
	reset()
	if not room.has("loot_slots"):
		return {"ok": true, "error": "", "enabled": false}
	var slots_value: Variant = room.get("loot_slots")
	if not slots_value is Array:
		return _failure("invalid_loot_slots")
	var seen: Dictionary = {}
	var normalized: Array[Dictionary] = []
	for raw_value: Variant in (slots_value as Array):
		if not raw_value is Dictionary:
			return _failure("invalid_loot_slot")
		var raw: Dictionary = raw_value
		var slot_id := String(raw.get("slot_id", "")).strip_edges()
		var source := String(raw.get("source", "")).strip_edges()
		if slot_id.is_empty() or seen.has(slot_id) or source not in ["enemy_death", "wave_clear"]:
			return _failure("invalid_loot_slot_identity")
		var tags: Array[String] = []
		if raw.has("tags"):
			if not raw.tags is Array:
				return _failure("invalid_loot_slot_tags:%s" % slot_id)
			for tag_value: Variant in raw.tags:
				if not tag_value is String or String(tag_value).strip_edges().is_empty():
					return _failure("invalid_loot_slot_tags:%s" % slot_id)
				tags.append(String(tag_value).strip_edges())
		elif raw.get("tag", null) is String and not String(raw.tag).strip_edges().is_empty():
			tags.append(String(raw.tag).strip_edges())
		else:
			return _failure("missing_loot_slot_tag:%s" % slot_id)
		var pickup_radius_value: Variant = raw.get("pickup_radius", 18.0)
		if (typeof(pickup_radius_value) not in [TYPE_INT, TYPE_FLOAT]
				or not is_finite(float(pickup_radius_value)) or float(pickup_radius_value) <= 0.0):
			return _failure("invalid_loot_pickup_radius:%s" % slot_id)
		if raw.has("guaranteed") and not raw.guaranteed is bool:
			return _failure("invalid_loot_guaranteed:%s" % slot_id)
		var guarantee := String(raw.get("guarantee_family", "")).strip_edges()
		normalized.append({
			"slot_id": slot_id, "source": source, "tags": tags,
			"pickup_radius": float(pickup_radius_value), "guaranteed": bool(raw.get("guaranteed", false)),
			"guarantee_family": guarantee,
		})
		seen[slot_id] = true
	if normalized.is_empty():
		return {"ok": true, "error": "", "enabled": false}
	if item_registry == null:
		return _failure("loot_item_registry_unavailable")
	var generator := GeneratorScript.new(item_registry)
	var ledger := LedgerScript.new()
	var configured: Dictionary = ledger.configure(room_id, root_seed, generator)
	if not bool(configured.get("ok", false)):
		return configured
	_slots = normalized
	_ledger = ledger
	return {"ok": true, "error": "", "enabled": true}


func enabled() -> bool:
	return _ledger != null


func spawn_for_source(tick: int, source: String, source_entity_id: int, position: Vector2) -> Dictionary:
	if _ledger == null or not position.is_finite():
		return _failure("room_loot_disabled")
	var resolved_source_entity_id := source_entity_id
	if resolved_source_entity_id <= 0:
		resolved_source_entity_id = 1000000000 + _drop_index
	var spawned_slots: Dictionary = _ledger.snapshot().get("spawned_slots", {})
	for slot: Dictionary in _slots:
		if String(slot.source) != source or spawned_slots.has(String(slot.slot_id)):
			continue
		var result: Dictionary = _ledger.spawn(
			tick, String(slot.slot_id), resolved_source_entity_id, position,
			_drop_index, slot.tags, String(slot.guarantee_family), float(slot.pickup_radius)
		)
		if bool(result.get("ok", false)):
			_drop_index += 1
		return result
	return _failure("no_matching_loot_slot")


func request_pickup(tick: int, active: bool, battle_over: bool, loot_entity_id: String) -> Dictionary:
	if _ledger == null:
		return _failure("room_loot_disabled")
	if not active or battle_over:
		return _failure("loot_pickup_room_inactive")
	var normalized_id := loot_entity_id.strip_edges()
	if normalized_id.is_empty():
		return _failure("invalid_loot_entity_id")
	var found := false
	for entity: Dictionary in snapshot().get("entities", []):
		if String(entity.get("loot_entity_id", "")) == normalized_id and String(entity.get("state", "")) == LedgerScript.ACTIVE_STATE:
			found = true
			break
	if not found:
		return _failure("loot_not_available")
	for pending: Dictionary in _pickup_requests:
		if String(pending.get("loot_entity_id", "")) == normalized_id:
			return _failure("loot_pickup_already_queued")
	_request_sequence += 1
	var request := {
		"request_id": _request_sequence, "loot_entity_id": normalized_id,
		"requested_tick": tick, "execute_tick": tick + 1,
	}
	_pickup_requests.append(request)
	return {"ok": true, "error": "", "accepted": true, "queued": true, "request": request.duplicate(true)}


func process_pickups(tick: int, player_health: float, player_position: Vector2, battle_over: bool) -> void:
	if _ledger == null or _pickup_requests.is_empty():
		return
	var remaining: Array[Dictionary] = []
	for request: Dictionary in _pickup_requests:
		if int(request.execute_tick) > tick:
			remaining.append(request)
			continue
		var result: Dictionary
		if player_health <= 0.0 or battle_over:
			result = _failure("loot_pickup_player_inactive")
		else:
			result = _ledger.pickup(tick, 1, String(request.loot_entity_id), player_position)
		result["request_id"] = int(request.request_id)
		_pickup_receipts.append(result.duplicate(true))
	_pickup_requests = remaining


func settle(outcome: String) -> Dictionary:
	if _ledger == null:
		return {"ok": true, "error": "", "enabled": false, "settlement": {}}
	if not _settlement.is_empty():
		return {"ok": true, "error": "", "enabled": true, "settlement": _settlement.duplicate(true)}
	var settled: Dictionary = _ledger.settle(outcome)
	if not bool(settled.get("ok", false)):
		return _failure("loot_settlement_failed:%s" % String(settled.get("error", "invalid_receipt")))
	_settlement = settled.duplicate(true)
	return {"ok": true, "error": "", "enabled": true, "settlement": _settlement.duplicate(true)}


func settlement_snapshot() -> Dictionary:
	return _settlement.duplicate(true)


func snapshot() -> Dictionary:
	if _ledger == null:
		return {"enabled": false, "entities": [], "events": [], "settlement": {}}
	var result: Dictionary = _ledger.snapshot()
	result["enabled"] = true
	result["pending_pickup_requests"] = _pickup_requests.duplicate(true)
	result["pickup_receipts"] = _pickup_receipts.duplicate(true)
	return result


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}
