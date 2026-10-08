class_name CombatCommandProtocol
extends RefCounted

const PROTOCOL_VERSION := 2

const STATUS_ACCEPTED := "accepted"
const STATUS_REJECTED := "rejected"

const KIND_MOVE := "move"
const KIND_STOP_MOVE := "stop_move"
const KIND_CAST := "cast"
const KIND_DODGE := "dodge"

const ABILITY_PIERCING_ARROW := "piercing_arrow"
const ABILITY_HUNTER_MARK := "hunter_mark"
const ABILITY_DASH := "dash"

const _BASE_FIELDS := ["protocol_version", "tick", "actor_id", "sequence", "kind"]
const _KNOWN_ABILITIES := [ABILITY_PIERCING_ARROW, ABILITY_HUNTER_MARK, ABILITY_DASH]


static func move(tick: int, actor_id: String, sequence: int, direction_x_milli: int, direction_y_milli: int, speed_milli: int) -> Dictionary:
	return {
		"protocol_version": PROTOCOL_VERSION,
		"tick": tick,
		"actor_id": actor_id,
		"sequence": sequence,
		"kind": KIND_MOVE,
		"direction_x_milli": direction_x_milli,
		"direction_y_milli": direction_y_milli,
		"speed_milli": speed_milli,
	}


static func stop_move(tick: int, actor_id: String, sequence: int) -> Dictionary:
	return {
		"protocol_version": PROTOCOL_VERSION,
		"tick": tick,
		"actor_id": actor_id,
		"sequence": sequence,
		"kind": KIND_STOP_MOVE,
	}


static func cast(tick: int, actor_id: String, sequence: int, ability_id: String, target_entity_id: int, direction_x_milli = null, direction_y_milli = null) -> Dictionary:
	var command := {
		"protocol_version": PROTOCOL_VERSION,
		"tick": tick,
		"actor_id": actor_id,
		"sequence": sequence,
		"kind": KIND_CAST,
		"ability_id": ability_id,
		"target_entity_id": target_entity_id,
	}
	if direction_x_milli != null or direction_y_milli != null:
		command["direction_x_milli"] = direction_x_milli
		command["direction_y_milli"] = direction_y_milli
	return command


static func dodge(tick: int, actor_id: String, sequence: int, direction_x_milli: int, direction_y_milli: int) -> Dictionary:
	return {
		"protocol_version": PROTOCOL_VERSION,
		"tick": tick,
		"actor_id": actor_id,
		"sequence": sequence,
		"kind": KIND_DODGE,
		"direction_x_milli": direction_x_milli,
		"direction_y_milli": direction_y_milli,
	}


static func validate(command, current_tick: int, equipped_abilities, allow_dodge: bool = true) -> Dictionary:
	if not command is Dictionary:
		return _receipt(STATUS_REJECTED, "invalid_command", {})
	var candidate: Dictionary = command
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
	if not candidate.kind is String or String(candidate.kind) not in [KIND_MOVE, KIND_STOP_MOVE, KIND_CAST, KIND_DODGE]:
		return _receipt(STATUS_REJECTED, "invalid_kind", candidate.duplicate(true))

	var kind := String(candidate.kind)
	var allowed_fields: Array = _BASE_FIELDS.duplicate()
	match kind:
		KIND_MOVE:
			allowed_fields.append_array(["direction_x_milli", "direction_y_milli", "speed_milli"])
		KIND_CAST:
			allowed_fields.append_array(["ability_id", "target_entity_id"])
			if candidate.get("ability_id") in [ABILITY_DASH, ABILITY_PIERCING_ARROW]:
				var has_x := candidate.has("direction_x_milli")
				var has_y := candidate.has("direction_y_milli")
				if not has_x or not has_y:
					return _receipt(STATUS_REJECTED, "missing_field", candidate.duplicate(true))
				allowed_fields.append_array(["direction_x_milli", "direction_y_milli"])
		KIND_DODGE:
			allowed_fields.append_array(["direction_x_milli", "direction_y_milli"])

	for key in candidate.keys():
		if key not in allowed_fields:
			return _receipt(STATUS_REJECTED, "extra_field", candidate.duplicate(true))
	for field in allowed_fields:
		if not candidate.has(field):
			return _receipt(STATUS_REJECTED, "missing_field", candidate.duplicate(true))

	if kind == KIND_MOVE or kind == KIND_DODGE or (kind == KIND_CAST and candidate.has("direction_x_milli")):
		if not _valid_direction(candidate):
			return _receipt(STATUS_REJECTED, "invalid_direction", candidate.duplicate(true))
	if kind == KIND_MOVE:
		if not candidate.speed_milli is int or int(candidate.speed_milli) < 0 or int(candidate.speed_milli) > 1000:
			return _receipt(STATUS_REJECTED, "invalid_speed", candidate.duplicate(true))
	if kind == KIND_DODGE and not allow_dodge:
		return _receipt(STATUS_REJECTED, "dodge_not_allowed", candidate.duplicate(true))
	if kind == KIND_CAST:
		if not candidate.ability_id is String or String(candidate.ability_id).is_empty():
			return _receipt(STATUS_REJECTED, "invalid_ability", candidate.duplicate(true))
		var ability_id := String(candidate.ability_id)
		if ability_id not in _KNOWN_ABILITIES:
			return _receipt(STATUS_REJECTED, "unknown_ability", candidate.duplicate(true))
		if not _is_equipped(ability_id, equipped_abilities):
			return _receipt(STATUS_REJECTED, "ability_not_equipped", candidate.duplicate(true))
		if not candidate.target_entity_id is int or (ability_id != ABILITY_DASH and int(candidate.target_entity_id) <= 0) or (ability_id == ABILITY_DASH and int(candidate.target_entity_id) < 0):
			return _receipt(STATUS_REJECTED, "invalid_target", candidate.duplicate(true))

	return _receipt(STATUS_ACCEPTED, "ok", _normalize(candidate, allowed_fields))


static func arbitrate(commands: Array, current_tick: int, equipped_abilities, allow_dodge: bool = true) -> Dictionary:
	var entries: Array[Dictionary] = []
	for command in commands:
		var receipt := validate(command, current_tick, equipped_abilities, allow_dodge)
		entries.append({"receipt": receipt, "priority": _sort_priority(receipt.command)})
	entries.sort_custom(_entry_before)

	var kept_by_actor: Dictionary = {}
	for entry in entries:
		var receipt: Dictionary = entry.receipt
		if receipt.status != STATUS_ACCEPTED:
			continue
		var command: Dictionary = receipt.command
		var actor_id := String(command.actor_id)
		if not kept_by_actor.has(actor_id):
			kept_by_actor[actor_id] = {"mobility": false, "offensive": false, "mark": false, "move": false}
		var kept: Dictionary = kept_by_actor[actor_id]
		var category := _category(command)
		match category:
			"mobility":
				if kept.mobility or kept.offensive:
					_reject_receipt(receipt, "action_conflict")
				else:
					kept.mobility = true
			"offensive":
				if kept.mobility or kept.offensive:
					_reject_receipt(receipt, "action_conflict")
				else:
					kept.offensive = true
			"utility":
				if kept.mark:
					_reject_receipt(receipt, "action_conflict")
				else:
					kept.mark = true
			"move":
				if kept.move:
					_reject_receipt(receipt, "duplicate_move")
				else:
					kept.move = true
		kept_by_actor[actor_id] = kept

	var accepted: Array[Dictionary] = []
	entries.sort_custom(_receipt_entry_before)
	var receipts: Array[Dictionary] = []
	for entry in entries:
		var receipt: Dictionary = entry.receipt
		receipts.append(receipt)
		if receipt.status == STATUS_ACCEPTED:
			accepted.append(receipt.command)
	accepted.sort_custom(_accepted_before)
	return {"commands": accepted, "receipts": receipts}


static func _valid_direction(command: Dictionary) -> bool:
	if not command.direction_x_milli is int or not command.direction_y_milli is int:
		return false
	var x := int(command.direction_x_milli)
	var y := int(command.direction_y_milli)
	return x >= -1000 and x <= 1000 and y >= -1000 and y <= 1000


static func _is_equipped(ability_id: String, equipped_abilities) -> bool:
	if not equipped_abilities is Array:
		return false
	for equipped in equipped_abilities:
		if equipped is String and String(equipped) == ability_id:
			return true
	return false


static func _normalize(command: Dictionary, fields: Array) -> Dictionary:
	var normalized := {}
	for field in fields:
		normalized[field] = command[field]
	return normalized


static func _receipt(status: String, reason: String, command: Dictionary) -> Dictionary:
	return {"status": status, "reason": reason, "command": command}


static func _reject_receipt(receipt: Dictionary, reason: String) -> void:
	receipt.status = STATUS_REJECTED
	receipt.reason = reason


static func _category(command: Dictionary) -> String:
	if command.kind == KIND_DODGE or (command.kind == KIND_CAST and command.ability_id == ABILITY_DASH):
		return "mobility"
	if command.kind == KIND_CAST and command.ability_id == ABILITY_PIERCING_ARROW:
		return "offensive"
	if command.kind == KIND_CAST and command.ability_id == ABILITY_HUNTER_MARK:
		return "utility"
	return "move"


static func _sort_priority(command: Dictionary) -> int:
	if command.is_empty():
		return 99
	if command.get("kind") == KIND_DODGE:
		return 0
	if command.get("kind") == KIND_CAST and command.get("ability_id") == ABILITY_DASH:
		return 1
	if command.get("kind") == KIND_CAST and command.get("ability_id") == ABILITY_HUNTER_MARK:
		return 2
	if command.get("kind") == KIND_CAST and command.get("ability_id") == ABILITY_PIERCING_ARROW:
		return 3
	if command.get("kind") == KIND_STOP_MOVE or command.get("kind") == KIND_MOVE:
		return 4
	return 98


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
	if int(left.priority) != int(right.priority):
		return int(left.priority) < int(right.priority)
	var sequence_a := int(a.get("sequence", -1)) if a.get("sequence") is int else -1
	var sequence_b := int(b.get("sequence", -1)) if b.get("sequence") is int else -1
	if sequence_a != sequence_b:
		return sequence_a < sequence_b
	return JSON.stringify(a, "", true) < JSON.stringify(b, "", true)


static func _accepted_before(a: Dictionary, b: Dictionary) -> bool:
	var actor_compare := String(a.actor_id).naturalnocasecmp_to(String(b.actor_id))
	if actor_compare != 0:
		return actor_compare < 0
	if int(a.tick) != int(b.tick):
		return int(a.tick) < int(b.tick)
	var priority_a := _sort_priority(a)
	var priority_b := _sort_priority(b)
	if priority_a != priority_b:
		return priority_a < priority_b
	return int(a.sequence) < int(b.sequence)


static func _receipt_entry_before(left: Dictionary, right: Dictionary) -> bool:
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
	if int(left.priority) != int(right.priority):
		return int(left.priority) < int(right.priority)
	return JSON.stringify(a, "", true) < JSON.stringify(b, "", true)
