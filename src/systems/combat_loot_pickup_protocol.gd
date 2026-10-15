class_name CombatLootPickupProtocol
extends RefCounted

## Standalone command protocol for post-battle loot pickup requests.
## Distance, room-active state, combat outcome, and ledger ownership are
## judged by the room authority; this layer only arbitrates well-formed,
## current-tick requests for a single actor.

const PROTOCOL_VERSION := 1

const STATUS_ACCEPTED := "accepted"
const STATUS_REJECTED := "rejected"

const KIND_LOOT_PICKUP := "loot_pickup"

const _BASE_FIELDS := ["protocol_version", "tick", "actor_id", "sequence", "kind", "loot_entity_id"]


static func make_request(tick: int, actor_id: String, sequence: int, loot_entity_id: String) -> Dictionary:
	return {
		"protocol_version": PROTOCOL_VERSION,
		"tick": tick,
		"actor_id": actor_id,
		"sequence": sequence,
		"kind": KIND_LOOT_PICKUP,
		"loot_entity_id": loot_entity_id,
	}


static func validate(request, current_tick: int) -> Dictionary:
	if not request is Dictionary:
		return _receipt(STATUS_REJECTED, "invalid_request", {})
	var candidate: Dictionary = request
	for field in _BASE_FIELDS:
		if not candidate.has(field):
			return _receipt(STATUS_REJECTED, "missing_field", candidate.duplicate(true))

	if not candidate.protocol_version is int or int(candidate.protocol_version) != PROTOCOL_VERSION:
		return _receipt(STATUS_REJECTED, "wrong_protocol", candidate.duplicate(true))
	if not candidate.tick is int:
		return _receipt(STATUS_REJECTED, "invalid_tick", candidate.duplicate(true))
	if int(candidate.tick) < current_tick:
		return _receipt(STATUS_REJECTED, "stale_tick", candidate.duplicate(true))
	if int(candidate.tick) > current_tick:
		return _receipt(STATUS_REJECTED, "future_tick", candidate.duplicate(true))
	if not candidate.actor_id is String or String(candidate.actor_id).strip_edges().is_empty():
		return _receipt(STATUS_REJECTED, "invalid_actor", candidate.duplicate(true))
	if not candidate.sequence is int or int(candidate.sequence) < 0:
		return _receipt(STATUS_REJECTED, "invalid_sequence", candidate.duplicate(true))
	if not candidate.kind is String or String(candidate.kind) != KIND_LOOT_PICKUP:
		return _receipt(STATUS_REJECTED, "invalid_kind", candidate.duplicate(true))
	if not candidate.loot_entity_id is String or String(candidate.loot_entity_id).strip_edges().is_empty():
		return _receipt(STATUS_REJECTED, "invalid_loot_entity", candidate.duplicate(true))

	for key in candidate.keys():
		if key not in _BASE_FIELDS:
			return _receipt(STATUS_REJECTED, "extra_field", candidate.duplicate(true))

	return _receipt(STATUS_ACCEPTED, "ok", _normalize(candidate))


static func arbitrate(requests: Array, current_tick: int, actor_id: String = "ranger") -> Dictionary:
	var entries: Array[Dictionary] = []
	for request in requests:
		var receipt := validate(request, current_tick)
		entries.append({"receipt": receipt})
	entries.sort_custom(_entry_before)

	var has_accepted := false
	for entry in entries:
		var receipt: Dictionary = entry.receipt
		if receipt.status != STATUS_ACCEPTED:
			continue
		var command: Dictionary = receipt.command
		if String(command.actor_id) != String(actor_id):
			_reject_receipt(receipt, "actor_mismatch")
			continue
		if has_accepted:
			_reject_receipt(receipt, "duplicate_pickup_request")
			continue
		has_accepted = true

	var commands: Array[Dictionary] = []
	var receipts: Array[Dictionary] = []
	for entry in entries:
		var receipt: Dictionary = entry.receipt
		receipts.append(receipt)
		if receipt.status == STATUS_ACCEPTED:
			commands.append(receipt.command.duplicate(true))
	return {"commands": commands, "receipts": receipts}


static func _normalize(candidate: Dictionary) -> Dictionary:
	var normalized := {}
	for field in _BASE_FIELDS:
		normalized[field] = candidate[field]
	return normalized


static func _receipt(status: String, reason: String, command: Dictionary) -> Dictionary:
	return {"status": status, "reason": reason, "command": command}


static func _reject_receipt(receipt: Dictionary, reason: String) -> void:
	receipt.status = STATUS_REJECTED
	receipt.reason = reason


static func _entry_before(left: Dictionary, right: Dictionary) -> bool:
	var a: Dictionary = left.receipt.command
	var b: Dictionary = right.receipt.command
	var actor_compare := String(a.get("actor_id", "")).naturalnocasecmp_to(String(b.get("actor_id", "")))
	if actor_compare != 0:
		return actor_compare < 0
	var tick_a := int(a.get("tick", -1)) if a.get("tick") is int else -1
	var tick_b := int(b.get("tick", -1)) if b.get("tick") is int else -1
	if tick_a != tick_b:
		return tick_a < tick_b
	var sequence_a := int(a.get("sequence", -1)) if a.get("sequence") is int else -1
	var sequence_b := int(b.get("sequence", -1)) if b.get("sequence") is int else -1
	if sequence_a != sequence_b:
		return sequence_a < sequence_b
	return JSON.stringify(a, "", true) < JSON.stringify(b, "", true)
