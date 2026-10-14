class_name CombatRoomResult
extends RefCounted

## Pure room-result projection.
##
## CombatRoomRuntime owns lifecycle and signal delivery. This object owns the
## boundary between a room's authoritative snapshot and the contract result
## protocol, so scene nodes never become the result schema.

static func build(current_config: Dictionary, room_snapshot: Dictionary, outcome: String) -> Dictionary:
	if outcome == "defeat":
		for field: String in ["last_damage_source_id", "last_damage_tick"]:
			if not room_snapshot.has(field):
				return {"ok": false, "error": "missing_room_snapshot_field:%s" % field}
		if not room_snapshot.last_damage_source_id is String:
			return {"ok": false, "error": "invalid_room_snapshot_field:last_damage_source_id"}
		if not room_snapshot.last_damage_tick is int:
			return {"ok": false, "error": "invalid_room_snapshot_field:last_damage_tick"}
	var room_value: Variant = current_config.get("room", {})
	var room: Dictionary = room_value as Dictionary if room_value is Dictionary else {}
	var reward_value: Variant = room_snapshot.get("room_reward_snapshot", {})
	var room_rewards: Dictionary = reward_value.duplicate(true) if reward_value is Dictionary else {}
	var drop_tags_value: Variant = room.get("drop_tags", [])
	var drop_tags: Array = drop_tags_value.duplicate(true) if drop_tags_value is Array else []
	var rewards: Dictionary = room_rewards.duplicate(true)
	for obsolete_key in ["fate_dice", "fate_dice_delta", "add_dice_delta", "rewrite_dice_delta", "refine_dice_delta", "reroll_dice_delta", "drop_id", "drop_label"]:
		rewards.erase(obsolete_key)
	rewards["law_tallies_delta"] = {
		"inscribe": int(room_rewards.get("add_dice_delta", 0)) + (1 if "inscribe_tally" in drop_tags else 0),
		"rewrite": int(room_rewards.get("rewrite_dice_delta", 0)) + (1 if "rewrite_tally" in drop_tags else 0),
		"refine": int(room_rewards.get("refine_dice_delta", 0)) + (1 if "refine_tally" in drop_tags else 0),
	}
	var resolved_build_value: Variant = current_config.get("resolved_build", {})
	var resolved_build: Dictionary = resolved_build_value as Dictionary if resolved_build_value is Dictionary else {}
	var result := {
		"outcome": outcome,
		"contract_id": _copy_value(current_config.get("contract_id")),
		"mode": String(current_config.get("mode", "")),
		"preset_id": String(current_config.get("preset_id", "convergent")),
		"build_fingerprint": String(resolved_build.get("build_fingerprint", "")),
		"seed": _copy_value(current_config.get("seed")),
		"room_id": _copy_room_value(room, "room_id"),
		"objective": _copy_room_value(room, "objective_id", "objective"),
		"layout": _copy_room_value(room, "layout_id", "layout"),
		"drop_tags": drop_tags.duplicate(true),
		"ticks": int(room_snapshot.get("sim_tick", 0)),
		"elapsed_seconds": float(room_snapshot.get("elapsed", 0.0)),
		"casts": int(room_snapshot.get("shots", 0)),
		"arrow_hits": int(room_snapshot.get("arrow_hits", 0)),
		"defeated": int(room_snapshot.get("defeated", 0)),
		"report": String(room_snapshot.get("battle_report", "")),
		"rewards": rewards,
	}
	if outcome == "defeat":
		result["failure_reason"] = room_snapshot.last_damage_source_id
		result["death_tick"] = room_snapshot.last_damage_tick
	var automation_failure := String(room_snapshot.get("automation_smoke_failure", ""))
	if not automation_failure.is_empty():
		result["error"] = automation_failure
	return result


static func _copy_room_value(room: Dictionary, key: String, fallback_key: String = "") -> Variant:
	var value: Variant = room.get(key, room.get(fallback_key) if not fallback_key.is_empty() else null)
	return _copy_value(value)


static func _copy_value(value: Variant) -> Variant:
	return {"value": value}.duplicate(true)["value"]
