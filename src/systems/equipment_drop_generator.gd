class_name EquipmentDropGenerator
extends RefCounted

## Pure deterministic materializer for early-campaign equipment drops.
## Invalid/non-equipment inputs fail closed with an empty result.

const DeterministicRngScript = preload("res://src/core/deterministic_rng.gd")
const EarlyItemRegistryScript = preload("res://src/content/early_item_registry.gd")

const SOURCE_TYPE := "campaign_drop"
# starter_fixed identifies the authored tutorial loadout. It is deliberately not
# a random equipment pool tag; real drops only begin once comparison is unlocked.
const GENERAL_TAGS: Array[String] = ["equipment_general"]
const SLOT_TAGS := {
	"main_hand": "main_hand",
	"off_hand": "off_hand",
	"gloves": "gloves",
	"ring": "ring_1",
}
const FAMILY_TAGS := {
	"piercing_probability": "piercing_continuation",
	"shared_lifetime": "projectile_lifetime",
	"projectile_speed": "projectile_speed",
	"targeting_distance": "seeking_distance",
	"turn_time": "turn_response",
	"damage": "carrier_power",
	"critical": "critical_chance",
	"survival": "maximum_health",
}

var _registry: Variant


func _init(registry: Variant = null) -> void:
	_registry = registry
	if _registry == null:
		_registry = EarlyItemRegistryScript.new()
		if not _registry.load_all().is_empty():
			_registry = null


func generate_drop(root_seed: int, source_id: String, drop_index: int, drop_tags: Array, guarantee_family: String = "") -> Dictionary:
	var drops := generate_drops(root_seed, source_id, drop_index, 1, drop_tags, guarantee_family)
	return (drops[0] as Dictionary).duplicate(true) if not drops.is_empty() else {}


func generate_drops(root_seed: int, source_id: String, first_drop_index: int, drop_count: int, drop_tags: Array, guarantee_family: String = "") -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var normalized_source := source_id.strip_edges()
	var normalized_tags := _recognized_tags(drop_tags)
	var normalized_guarantee := guarantee_family.strip_edges()
	if not _registry_is_ready() or normalized_source.is_empty() or first_drop_index < 0 or drop_count <= 0:
		return results
	if normalized_tags.is_empty():
		return results
	if not normalized_guarantee.is_empty() and not _registry.affix_families.has(normalized_guarantee):
		return results

	for offset in range(drop_count):
		var guaranteed_family := normalized_guarantee if offset == 0 else ""
		var item := _materialize(root_seed, normalized_source, first_drop_index + offset, normalized_tags, guaranteed_family)
		if item.is_empty():
			return []
		results.append(item)
	return results


func _materialize(root_seed: int, source_id: String, drop_index: int, tags: Array[String], guarantee_family: String) -> Dictionary:
	var stream_key := _stream_key(source_id, drop_index, tags, guarantee_family)
	var rng: RefCounted = DeterministicRngScript.new(root_seed, stream_key)
	var explicit_slots := _slots_from_tags(tags)
	var requested_families := _families_from_tags(tags)
	if not guarantee_family.is_empty():
		requested_families = [guarantee_family]

	var pairs := _compatible_pairs(explicit_slots, requested_families)
	# A guarantee is stronger than a conflicting slot tag. Fall back to any slot
	# that can legally carry the promised family.
	if pairs.is_empty() and not requested_families.is_empty():
		pairs = _compatible_pairs([], requested_families)
	if pairs.is_empty():
		return {}

	var pair: Dictionary = pairs[rng.next_int(pairs.size())]
	var slot := String(pair.slot)
	var family_id := String(pair.family_id)
	var base_ids := _base_ids_for_slot(slot)
	if base_ids.is_empty():
		return {}
	var base_item_id := String(base_ids[rng.next_int(base_ids.size())])
	var tiers: Array = (_registry.affix_families[family_id] as Dictionary).get("tiers", [])
	if tiers.is_empty():
		return {}
	var tier_entry: Dictionary = tiers[rng.next_int(tiers.size())]
	var law_seed: int = rng.next_u32()
	var identity := "%d\u001f%s" % [root_seed, stream_key]

	return {
		"instance_id": "drop_%s" % identity.sha256_text(),
		"base_item_id": base_item_id,
		"slot": slot,
		"affixes": [{"family_id": family_id, "tier": int(tier_entry.tier)}],
		"rune_id": "",
		"law_id": "",
		"source": {"type": SOURCE_TYPE, "id": source_id},
		"law_seed": law_seed,
	}


func _recognized_tags(drop_tags: Array) -> Array[String]:
	var seen := {}
	for value in drop_tags:
		if not value is String:
			continue
		var tag := String(value).strip_edges()
		if tag in GENERAL_TAGS or SLOT_TAGS.has(tag) or FAMILY_TAGS.has(tag):
			seen[tag] = true
	var result: Array[String] = []
	for tag in seen.keys():
		result.append(String(tag))
	result.sort()
	return result


func _slots_from_tags(tags: Array[String]) -> Array[String]:
	var slots: Array[String] = []
	for tag in tags:
		if SLOT_TAGS.has(tag):
			var slot := String(SLOT_TAGS[tag])
			if slot not in slots:
				slots.append(slot)
	if slots.is_empty():
		slots = EarlyItemRegistryScript.PROTOTYPE_OPEN_SLOTS.duplicate()
	slots.sort()
	return slots


func _families_from_tags(tags: Array[String]) -> Array[String]:
	var families: Array[String] = []
	for tag in tags:
		if FAMILY_TAGS.has(tag):
			var family_id := String(FAMILY_TAGS[tag])
			if family_id not in families:
				families.append(family_id)
	if families.is_empty():
		for family_id in _registry.affix_families.keys():
			families.append(String(family_id))
	families.sort()
	return families


func _compatible_pairs(slots: Array[String], families: Array[String]) -> Array[Dictionary]:
	var allowed_slots := slots
	if allowed_slots.is_empty():
		allowed_slots = EarlyItemRegistryScript.PROTOTYPE_OPEN_SLOTS.duplicate()
	var pairs: Array[Dictionary] = []
	for slot in allowed_slots:
		for family_id in families:
			if not _registry.affix_families.has(family_id):
				continue
			var compatible: Array = (_registry.affix_families[family_id] as Dictionary).get("compatible_slots", [])
			if slot in compatible:
				pairs.append({"slot": slot, "family_id": family_id})
	return pairs


func _base_ids_for_slot(slot: String) -> Array[String]:
	var ids: Array[String] = []
	for base_id in _registry.base_items.keys():
		if String((_registry.base_items[base_id] as Dictionary).get("slot", "")) == slot:
			ids.append(String(base_id))
	ids.sort()
	return ids


func _stream_key(source_id: String, drop_index: int, tags: Array[String], guarantee_family: String) -> String:
	return "equipment-drop-v1\u001f%s\u001f%d\u001f%s\u001f%s" % [
		source_id,
		drop_index,
		",".join(tags),
		guarantee_family,
	]


func _registry_is_ready() -> bool:
	return _registry != null \
		and _registry.base_items is Dictionary and not _registry.base_items.is_empty() \
		and _registry.affix_families is Dictionary and not _registry.affix_families.is_empty()
