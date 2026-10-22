class_name DestinyForge
extends RefCounted

## Pure data model for the three deterministic Destiny Forge tracks.

const TRACK_ADD := "add"
const TRACK_REWRITE := "rewrite"
const TRACK_REFINE := "refine"
const MAX_TIER := 4

var item_seed: int
var slot_count: int
var affixes: Array[Dictionary] = []
var legal_families: Array[Dictionary] = []
var dice := {
	TRACK_ADD: 0,
	TRACK_REWRITE: 0,
	TRACK_REFINE: 0,
}
var _add_cursor := 0
var _rewrite_cursor := 0
var _refine_cursors: Array[int] = []


func _init(seed_value: int = 0, families: Array = [], numeric_slots: int = 4) -> void:
	item_seed = seed_value
	slot_count = maxi(1, numeric_slots)
	for _index in slot_count:
		affixes.append({})
		_refine_cursors.append(0)
	set_legal_families(families)


func set_legal_families(families: Array) -> void:
	legal_families.clear()
	for raw_family in families:
		var family := _normalize_family(raw_family)
		if not family.is_empty() and not _has_family(legal_families, family.name):
			legal_families.append(family)
	legal_families.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.name < b.name)


func set_affix(slot: int, family: String, tier: int = 1) -> bool:
	if not _valid_slot(slot) or family.is_empty() or tier < 1 or tier > MAX_TIER:
		return false
	if _family_equipped_elsewhere(family, slot):
		return false
	affixes[slot] = {"family": family, "tier": tier}
	return true


func clear_affix(slot: int) -> bool:
	if not _valid_slot(slot):
		return false
	affixes[slot] = {}
	return true


func set_dice(track: String, amount: int) -> bool:
	var normalized := _normalize_track(track)
	if normalized.is_empty() or amount < 0:
		return false
	dice[normalized] = amount
	return true


func grant_dice(track: String, amount: int) -> bool:
	var normalized := _normalize_track(track)
	if normalized.is_empty() or amount < 0:
		return false
	dice[normalized] = int(dice[normalized]) + amount
	return true


func get_dice(track: String) -> int:
	var normalized := _normalize_track(track)
	return int(dice.get(normalized, 0))


func preview(track: String, slot: int, count: int = -1) -> Array[Dictionary]:
	var normalized := _normalize_track(track)
	if normalized.is_empty() or not _valid_slot(slot):
		return []
	var affordable := get_dice(normalized)
	var preview_count := affordable if count < 0 else mini(affordable, maxi(0, count))
	if normalized == TRACK_ADD and not affixes[slot].is_empty():
		return []
	if normalized in [TRACK_REWRITE, TRACK_REFINE] and affixes[slot].is_empty():
		return []
	if normalized == TRACK_REFINE:
		return _preview_refine(slot, preview_count)
	return _preview_family_track(normalized, slot, preview_count)


func choose(track: String, slot: int, choice_number: int) -> Dictionary:
	var normalized := _normalize_track(track)
	if normalized.is_empty():
		return _error("unknown_track")
	if choice_number < 1:
		return _error("choice_must_be_positive")
	if get_dice(normalized) < choice_number:
		return _error("insufficient_dice")
	var candidates := preview(normalized, slot, choice_number)
	if candidates.size() < choice_number:
		return _error("no_legal_candidate")
	var selected: Dictionary = candidates[choice_number - 1].duplicate(true)
	dice[normalized] = get_dice(normalized) - choice_number
	if normalized == TRACK_ADD:
		_add_cursor += choice_number
	elif normalized == TRACK_REWRITE:
		_rewrite_cursor += choice_number
	else:
		_refine_cursors[slot] += choice_number
	affixes[slot] = {
		"family": selected.family,
		"tier": selected.tier,
	}
	return {
		"ok": true,
		"track": normalized,
		"slot": slot,
		"cost": choice_number,
		"remaining_dice": get_dice(normalized),
		"result": affixes[slot].duplicate(true),
	}


func commit(track: String, slot: int, choice_number: int) -> Dictionary:
	return choose(track, slot, choice_number)


func state() -> Dictionary:
	return {
		"item_seed": item_seed,
		"slot_count": slot_count,
		"affixes": affixes.duplicate(true),
		"legal_families": legal_families.duplicate(true),
		"dice": dice.duplicate(true),
		"cursors": {
			TRACK_ADD: _add_cursor,
			TRACK_REWRITE: _rewrite_cursor,
			TRACK_REFINE: _refine_cursors.duplicate(),
		},
	}


func restore_state(saved: Dictionary) -> bool:
	var saved_affixes: Array = saved.get("affixes", [])
	var saved_cursors: Dictionary = saved.get("cursors", {})
	var saved_refine: Array = saved_cursors.get(TRACK_REFINE, [])
	var saved_slots := int(saved.get("slot_count", saved_affixes.size()))
	if saved_slots < 1 or saved_affixes.size() != saved_slots or saved_refine.size() != saved_slots:
		return false
	item_seed = int(saved.get("item_seed", item_seed))
	slot_count = saved_slots
	affixes.assign(saved_affixes.duplicate(true))
	_refine_cursors.assign(saved_refine.duplicate())
	_add_cursor = maxi(0, int(saved_cursors.get(TRACK_ADD, 0)))
	_rewrite_cursor = maxi(0, int(saved_cursors.get(TRACK_REWRITE, 0)))
	set_legal_families(saved.get("legal_families", legal_families))
	var saved_dice: Dictionary = saved.get("dice", {})
	for track in [TRACK_ADD, TRACK_REWRITE, TRACK_REFINE]:
		dice[track] = maxi(0, int(saved_dice.get(track, 0)))
	return true


func _preview_family_track(track: String, slot: int, count: int) -> Array[Dictionary]:
	var allowed := _allowed_families(slot)
	if allowed.is_empty():
		return []
	var cursor: int = _add_cursor if track == TRACK_ADD else _rewrite_cursor
	var weighted_entries: Array[Dictionary] = []
	for family in allowed:
		for _copy in maxi(1, int(family.weight)):
			weighted_entries.append(family)
	var result: Array[Dictionary] = []
	var cached_cycle := -1
	var bag: Array[Dictionary] = []
	for offset in count:
		var absolute_index := cursor + offset
		var cycle := absolute_index / weighted_entries.size()
		if cycle != cached_cycle:
			# Add/rewrite are item-wide streams; the target slot only filters legality.
			bag = _shuffle_bag(weighted_entries, track, -1, cycle)
			cached_cycle = cycle
		var family: Dictionary = bag[absolute_index % bag.size()]
		var tier := 1 + (_random_at(_salt(track, -1, absolute_index, 71)) % MAX_TIER)
		result.append({
			"index": offset + 1,
			"cost": offset + 1,
			"family": family.name,
			"tier": tier,
		})
	return result


func _preview_refine(slot: int, count: int) -> Array[Dictionary]:
	var current: Dictionary = affixes[slot]
	var current_tier := int(current.tier)
	if current_tier >= MAX_TIER:
		return []
	var result: Array[Dictionary] = []
	var cursor: int = _refine_cursors[slot]
	for offset in count:
		var improvement_range := MAX_TIER - current_tier
		var tier := current_tier + 1 + (_random_at(_salt(TRACK_REFINE, slot, cursor + offset, 97)) % improvement_range)
		result.append({
			"index": offset + 1,
			"cost": offset + 1,
			"family": current.family,
			"tier": tier,
		})
	return result


func _shuffle_bag(entries: Array[Dictionary], track: String, slot: int, cycle: int) -> Array[Dictionary]:
	var bag: Array[Dictionary] = entries.duplicate()
	for index in range(bag.size() - 1, 0, -1):
		var swap_index := _random_at(_salt(track, slot, cycle, index + 211)) % (index + 1)
		var temporary := bag[index]
		bag[index] = bag[swap_index]
		bag[swap_index] = temporary
	return bag


func _allowed_families(target_slot: int) -> Array[Dictionary]:
	var allowed: Array[Dictionary] = []
	for family in legal_families:
		if not _family_equipped_elsewhere(String(family.name), target_slot) and not _family_is_current(family.name, target_slot):
			allowed.append(family)
	return allowed


func _family_is_current(family: String, slot: int) -> bool:
	return not affixes[slot].is_empty() and String(affixes[slot].family) == family


func _family_equipped_elsewhere(family: String, ignored_slot: int) -> bool:
	for slot in affixes.size():
		if slot != ignored_slot and not affixes[slot].is_empty() and String(affixes[slot].family) == family:
			return true
	return false


func _normalize_family(raw_family: Variant) -> Dictionary:
	if raw_family is String:
		return {"name": raw_family, "weight": 1}
	if raw_family is Dictionary:
		var name := String(raw_family.get("name", raw_family.get("family", "")))
		if name.is_empty():
			return {}
		return {"name": name, "weight": maxi(1, int(raw_family.get("weight", 1)))}
	return {}


func _normalize_track(track: String) -> String:
	match track.to_lower():
		# Legacy operation inputs remain accepted; these are not display labels.
		"add", "augment", "\u6dfb\u94f8":
			return TRACK_ADD
		"rewrite", "reforge", "\u6539\u5199":
			return TRACK_REWRITE
		"refine", "upgrade", "\u7cbe\u70bc":
			return TRACK_REFINE
	return ""


func _salt(track: String, slot: int, position: int, extra: int) -> int:
	var value := _stable_text_hash(track)
	value = (value * 1103515245 + slot * 1009 + position * 9176 + extra) & 0x7fffffff
	return value


func _random_at(salt: int) -> int:
	var value := (item_seed & 0x7fffffff) ^ salt
	value = (value * 1103515245 + 12345) & 0x7fffffff
	value = (value * 1103515245 + 12345) & 0x7fffffff
	return value


func _stable_text_hash(value: String) -> int:
	var result := 2166136261
	for byte in value.to_utf8_buffer():
		result = ((result ^ int(byte)) * 16777619) & 0x7fffffff
	return result


func _valid_slot(slot: int) -> bool:
	return slot >= 0 and slot < slot_count


func _has_family(families: Array[Dictionary], name: String) -> bool:
	for family in families:
		if String(family.name) == name:
			return true
	return false


func _error(code: String) -> Dictionary:
	return {"ok": false, "error": code}
