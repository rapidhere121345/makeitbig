extends SceneTree

const RegistryScript = preload("res://src/content/early_item_registry.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var registry = RegistryScript.new()
	var load_errors: Array[String] = registry.load_all()
	_expect(load_errors.is_empty(), "registry load failed: %s" % str(load_errors), failures)
	_test_content_census(registry, failures)
	_test_item_instance_contract(registry, failures)
	_test_illegal_content(registry, failures)
	_test_stable_loadouts_and_atomic_load(registry, failures)
	_finish(failures)


func _test_content_census(registry, failures: Array[String]) -> void:
	_expect(registry.equipment_slots == RegistryScript.EQUIPMENT_SLOTS, "formal 12-slot schema changed", failures)
	_expect(registry.equipment_slots.size() == 12, "formal schema must reserve 12 slots", failures)
	_expect(registry.prototype_open_slots == ["main_hand", "off_hand", "gloves", "ring_1"], "prototype open slots changed", failures)
	_expect(registry.base_items.size() == 8, "prototype must contain exactly 8 base items", failures)
	_expect(registry.affix_families.size() == 8, "prototype must contain exactly 8 T1 affix families", failures)
	_expect(registry.runes.size() == 3 and registry.runes.has("breeding_split"), "three ranger runes including breeding_split are required", failures)
	_expect(registry.laws.size() == 1 and registry.laws.has("pack_hunt_mark"), "pack_hunt_mark must be the sole early law", failures)
	_expect(registry.item_instances.size() == 18, "fixed start, calibration builds, and two campaign rewards must contain eighteen stable ItemInstances", failures)
	var rune_reward: Dictionary = registry.item_instances.get("reward_mainline_03_breeding_split_gloves", {})
	var law_reward: Dictionary = registry.item_instances.get("reward_mainline_05_pack_hunt_mark_ring", {})
	_expect(String(rune_reward.get("base_item_id", "")) == "turnfeather_gloves"
		and String(rune_reward.get("slot", "")) == "gloves"
		and String(rune_reward.get("rune_id", "")) == "breeding_split"
		and rune_reward.get("source", {}) == {"type": "campaign_first_reward", "id": "mainline_03_first_elite"},
		"mainline 03 stable semantic reward ItemInstance is wrong", failures)
	_expect(String(law_reward.get("base_item_id", "")) == "hawk_eye_ring"
		and String(law_reward.get("slot", "")) == "ring_1"
		and String(law_reward.get("law_id", "")) == "pack_hunt_mark"
		and law_reward.get("source", {}) == {"type": "campaign_first_reward", "id": "mainline_05_growth_gate"},
		"mainline 05 stable semantic reward ItemInstance is wrong", failures)
	_expect(registry.fixed_starting_loadout_id == "fixed_start", "fixed starting loadout reference changed", failures)
	_expect(registry.calibration_fixture_ids == ["calibration_convergent", "calibration_critical", "calibration_exponential"], "calibration fixture references changed", failures)
	var calibration_instance_ids: Dictionary = {}
	var shared_base: Dictionary = (registry.build_fixtures[registry.fixed_starting_loadout_id] as Dictionary).base_parameters
	for fixture_id in registry.calibration_fixture_ids:
		var fixture: Dictionary = registry.build_fixtures[fixture_id]
		_expect(fixture.base_parameters == shared_base, "%s must share the fixed start's complete character base" % fixture_id, failures)
		for slot in registry.prototype_open_slots:
			var instance_id := String(fixture.equipment[slot])
			_expect(not calibration_instance_ids.has(instance_id), "%s must own a distinct calibration ItemInstance" % fixture_id, failures)
			calibration_instance_ids[instance_id] = true
	_expect(calibration_instance_ids.size() == 12, "three calibration fixtures must use twelve distinct equipment instances", failures)
	var per_slot := {}
	for base_id in registry.base_items:
		var slot := String(registry.base_items[base_id].slot)
		per_slot[slot] = int(per_slot.get(slot, 0)) + 1
	for slot in registry.prototype_open_slots:
		_expect(int(per_slot.get(slot, 0)) == 2, "slot %s must have two base items" % slot, failures)
	var parameters := {}
	for family_id in registry.affix_families:
		var family: Dictionary = registry.affix_families[family_id]
		parameters[String(family.parameter)] = true
		_expect((family.tiers as Array).size() == 4, "affix %s must define I-IV tiers" % family_id, failures)
	_expect(parameters.keys().size() == 8, "each early affix family must change a distinct real parameter", failures)


func _test_item_instance_contract(registry, failures: Array[String]) -> void:
	var item := _item("starter-main", "ashwood_longbow", "main_hand", [
		{"family_id": "piercing_continuation", "tier": 1},
	], "breeding_split", "pack_hunt_mark")
	_expect(registry.validate_item_instance(item).is_empty(), "valid ItemInstance was rejected", failures)

	var unknown_base: Dictionary = item.duplicate(true)
	unknown_base.base_item_id = "missing_base"
	_expect(_contains(registry.validate_item_instance(unknown_base), "unknown base_item_id"), "unknown base reference must be explicit", failures)
	var closed_slot: Dictionary = item.duplicate(true)
	closed_slot.slot = "head"
	_expect(_contains(registry.validate_item_instance(closed_slot), "not prototype-open"), "closed prototype slot must be rejected", failures)
	var bad_tier: Dictionary = item.duplicate(true)
	bad_tier.affixes[0].tier = 5
	_expect(_contains(registry.validate_item_instance(bad_tier), "unsupported tier 5"), "unsupported affix tier must be rejected", failures)
	var duplicate_affix: Dictionary = item.duplicate(true)
	duplicate_affix.affixes.append({"family_id": "piercing_continuation", "tier": 2})
	_expect(_contains(registry.validate_item_instance(duplicate_affix), "duplicate affix family"), "same-family affixes on one item must be rejected", failures)
	var unknown_rune: Dictionary = item.duplicate(true)
	unknown_rune.rune_id = "scripted_rune"
	_expect(_contains(registry.validate_item_instance(unknown_rune), "unknown rune id"), "unknown semantic reference must be rejected", failures)
	var malformed: Dictionary = item.duplicate(true)
	malformed["callback"] = "do_bad_thing"
	_expect(_contains(registry.validate_item_instance(malformed), "unknown field 'callback'"), "ItemInstance fields must remain stable", failures)


func _test_illegal_content(registry, failures: Array[String]) -> void:
	var file := FileAccess.open("res://content/early_items.json", FileAccess.READ)
	var content: Dictionary = JSON.parse_string(file.get_as_text())
	var scripted: Dictionary = content.duplicate(true)
	scripted.base_items[0]["script"] = "res://evil.gd"
	_expect(_contains(registry.validate_content(scripted), "executable field 'script'"), "content data must not hide scripts", failures)
	var duplicate: Dictionary = content.duplicate(true)
	duplicate.runes[0].id = duplicate.base_items[0].id
	_expect(_contains(registry.validate_content(duplicate), "duplicate id"), "IDs must be globally unique", failures)
	var bad_open_slots: Dictionary = content.duplicate(true)
	bad_open_slots.prototype_open_slots.append("head")
	_expect(_contains(registry.validate_content(bad_open_slots), "prototype_open_slots must"), "open-slot contract must be exact", failures)
	var bad_type: Dictionary = content.duplicate(true)
	bad_type.affix_families[0].tiers[0].value = "0.06"
	_expect(_contains(registry.validate_content(bad_type), "positive finite number"), "numeric content must reject strings", failures)
	var dangling: Dictionary = content.duplicate(true)
	dangling.build_fixtures[0].equipment.main_hand = "missing_instance"
	_expect(_contains(registry.validate_content(dangling), "unknown item instance"), "fixture item references must be strict", failures)
	var partial_fixture: Dictionary = content.duplicate(true)
	partial_fixture.build_fixtures[0].equipment.erase("ring_1")
	_expect(_contains(registry.validate_content(partial_fixture), "missing field 'ring_1'"), "fixture equipment must atomically cover all four open slots", failures)


func _test_stable_loadouts_and_atomic_load(registry, failures: Array[String]) -> void:
	var first: Dictionary = registry.equipment_for_fixture(registry.fixed_starting_loadout_id)
	var second: Dictionary = registry.equipment_for_fixture(registry.fixed_starting_loadout_id)
	_expect(first.size() == 4 and first == second, "fixed start must materialize deterministically", failures)
	for slot in RegistryScript.PROTOTYPE_OPEN_SLOTS:
		_expect(String(first[slot].instance_id) == "fixed_start_%s" % slot, "slot %s lost its stable instance id" % slot, failures)
	first.main_hand.instance_id = "mutated_copy"
	_expect(String(registry.equipment_for_fixture("fixed_start").main_hand.instance_id) == "fixed_start_main_hand", "materialized equipment must not mutate registry truth", failures)
	var before_ids: Array = registry.base_items.keys()
	before_ids.sort()
	var load_errors: Array[String] = registry.load_all("res://content/does_not_exist.json")
	var after_ids: Array = registry.base_items.keys()
	after_ids.sort()
	_expect(not load_errors.is_empty() and before_ids == after_ids, "failed reload must preserve the previously valid registry atomically", failures)


func _item(instance_id: String, base_id: String, slot: String, affixes: Array, rune_id: String = "", law_id: String = "") -> Dictionary:
	return {
		"instance_id": instance_id,
		"base_item_id": base_id,
		"slot": slot,
		"affixes": affixes,
		"rune_id": rune_id,
		"law_id": law_id,
		"source": {"type": "fixed_start", "id": "tutorial"},
		"law_seed": 1001,
	}


func _contains(errors: Array[String], needle: String) -> bool:
	for error in errors:
		if error.contains(needle):
			return true
	return false


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("PASS  test_early_items.gd")
		quit(0)
		return
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)
