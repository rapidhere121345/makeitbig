extends SceneTree

const RegistryScript = preload("res://src/content/early_item_registry.gd")
const ResolverScript = preload("res://src/systems/build_resolver.gd")
const Assert := preload("res://tests/helpers/assert.gd")

var registry
var resolver


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	registry = RegistryScript.new()
	var registry_errors: Array[String] = registry.load_all()
	_expect(registry_errors.is_empty(), "registry fixture failed: %s" % str(registry_errors), failures)
	resolver = ResolverScript.new(registry)
	var resolve_argument_count := -1
	for method_value in resolver.get_method_list():
		if String((method_value as Dictionary).get("name", "")) == "resolve":
			resolve_argument_count = ((method_value as Dictionary).get("args", []) as Array).size()
			break
	_expect(resolve_argument_count == 4,
		"BuildResolver.resolve must expose base parameters, equipment, skill, and talent context", failures)
	_test_fixed_start(failures)
	_test_growth_boundaries(failures)
	_test_real_equipment_parameters(failures)
	_test_missing_interfaces(failures)
	_test_deterministic_unordered_input(failures)
	_test_invalid_input_and_p_cap(failures)
	_finish(failures)


func _test_fixed_start(failures: Array[String]) -> void:
	var result: Dictionary = resolver.resolve_fixture(registry.fixed_starting_loadout_id)
	_expect(bool(result.ok), "fixed starting loadout must resolve: %s" % str(result.errors), failures)
	_expect(_near(result.final_parameters.p, 0.31), "fixed start must apply the Piercer Gloves +6-point base modifier", failures)
	_expect(_near(result.final_parameters.damage, 160.0), "fixed start must apply Ashwood Longbow damage", failures)
	_expect(_near(result.final_parameters.max_health, 112.0), "fixed start must use the deterministic vitality ring", failures)
	_expect(_near(result.final_parameters.critical_chance, 0.0), "undefined critical behavior must not leak into the fixed start", failures)
	_expect(result.growth_classification == "convergent", "fixed start without semantic pieces must converge", failures)
	_expect(int(result.generation_count) == 80, "fixed start must share the arena's g=80 character baseline", failures)
	_expect(String(result.build_fingerprint).length() == 64, "fixed start must expose a SHA-256 build fingerprint", failures)
	_expect((result.equipped_instance_ids as Dictionary).size() == 12, "resolved builds must expose the formal 12-slot equipment map", failures)


func _test_growth_boundaries(failures: Array[String]) -> void:
	for fixture in [
		{"id": "calibration_convergent", "p": 0.49, "expected": "convergent", "R": 0.98},
		{"id": "calibration_critical", "p": 0.50, "expected": "critical", "R": 1.0},
		{"id": "calibration_exponential", "p": 0.61, "expected": "exponential", "R": 1.22},
	]:
		var result: Dictionary = resolver.resolve_fixture(fixture.id)
		_expect(bool(result.ok), "growth fixture failed at p=%s" % fixture.p, failures)
		_expect(_near(result.final_parameters.p, fixture.p), "%s did not reach its calibrated p through equipment" % fixture.id, failures)
		_expect(result.growth_classification == fixture.expected, "p=%s classification changed" % fixture.p, failures)
		_expect(_near(result.R, fixture.R), "p=%s must produce R=2p" % fixture.p, failures)
		_expect(int(result.generation_count) == 80, "stable T/(d/v+turn) boundary changed", failures)
		_expect(_near(result.final_parameters.T, 34.0) and _near(result.final_parameters.damage, 160.0), "%s must preserve the migrated arena lifetime and damage" % fixture.id, failures)
		_expect(result.rune_ids == ["breeding_split"] and result.law_ids == ["pack_hunt_mark"], "%s must obtain semantic interfaces from equipped items" % fixture.id, failures)


func _test_real_equipment_parameters(failures: Array[String]) -> void:
	var naked: Dictionary = resolver.resolve(_base(0.25), {}, "piercing_arrow")
	var equipped: Dictionary = resolver.resolve(_base(0.25), _parameter_loadout(), "piercing_arrow")
	_expect(bool(equipped.ok), "parameter loadout failed: %s" % str(equipped.errors), failures)
	for parameter in ["p", "T", "v", "d", "turn", "damage"]:
		_expect(not _near(equipped.final_parameters[parameter], naked.final_parameters[parameter]), "equipment must really change %s" % parameter, failures)
		_expect((equipped.parameter_sources[parameter] as Array).size() > 1, "%s needs per-source explanation" % parameter, failures)
	_expect(equipped.final_parameters.critical_chance > naked.final_parameters.critical_chance, "critical affix must affect final parameters", failures)
	_expect(equipped.final_parameters.max_health > naked.final_parameters.max_health, "survival base must affect final parameters", failures)


func _test_missing_interfaces(failures: Array[String]) -> void:
	var none: Dictionary = resolver.resolve(_base(0.61), {}, "piercing_arrow")
	_expect(bool(none.ok), "missing semantic interfaces must remain a valid evaluable build", failures)
	_expect("breedable_event" in none.missing_interfaces and "branch_target_history" in none.missing_interfaces, "missing rune and law interfaces must be exposed", failures)
	_expect(_near(none.R, 0.61) and none.growth_classification == "convergent", "without split the chain ratio must remain p", failures)
	var split_item := _item("semantic-gloves", "turnfeather_gloves", "gloves", [], "breeding_split")
	var split_only: Dictionary = resolver.resolve(_base(0.61), {"gloves": split_item}, "piercing_arrow")
	_expect("breedable_event" in split_only.connected_interfaces, "breeding_split must connect breedable_event", failures)
	_expect("branch_target_history" in split_only.missing_interfaces, "missing pack law must remain visible", failures)
	_expect(_near(split_only.R, 0.61), "split without target-history law must not claim R=2p", failures)
	var law_item := _item("semantic-ring", "hawk_eye_ring", "ring_1", [], "", "pack_hunt_mark")
	var complete: Dictionary = resolver.resolve(_base(0.61), {"gloves": split_item, "ring_1": law_item}, "piercing_arrow")
	_expect(complete.missing_interfaces.is_empty(), "complete route must have no missing interfaces", failures)
	_expect("branch_target_history" in complete.connected_interfaces and _near(complete.R, 1.22), "complete route must connect R=2p", failures)


func _test_deterministic_unordered_input(failures: Array[String]) -> void:
	var ordered := _parameter_loadout()
	var reversed := {}
	var keys: Array = ordered.keys()
	keys.reverse()
	for key in keys:
		var item: Dictionary = ordered[key].duplicate(true)
		item.affixes.reverse()
		reversed[key] = item
	var first: Dictionary = resolver.resolve(_base(0.25), ordered, {"id": "piercing_arrow"})
	var second: Dictionary = resolver.resolve(_base(0.25), reversed, "piercing_arrow")
	_expect(first == second, "unordered dictionary/affix input must produce an identical result", failures)
	_expect(String(first.build_fingerprint).length() == 64, "valid builds must expose a stable SHA-256 fingerprint", failures)
	_expect(first.equipped_instance_ids.main_hand == "params-main" and first.equipped_instance_ids.head == "", "fingerprint metadata must include occupied and closed formal slots", failures)
	var changed := ordered.duplicate(true)
	changed.main_hand.affixes[0].tier = 2
	var changed_result: Dictionary = resolver.resolve(_base(0.25), changed, "piercing_arrow")
	_expect(bool(changed_result.ok) and changed_result.build_fingerprint != first.build_fingerprint, "changing an affix tier must change the build fingerprint", failures)
	var reseeded := ordered.duplicate(true)
	reseeded.main_hand.law_seed = int(reseeded.main_hand.law_seed) + 1
	var reseeded_result: Dictionary = resolver.resolve(_base(0.25), reseeded, "piercing_arrow")
	_expect(bool(reseeded_result.ok) and reseeded_result.final_parameters == first.final_parameters and reseeded_result.build_fingerprint != first.build_fingerprint, "fingerprint must include the full ItemInstance snapshot, not only final parameters", failures)


func _test_invalid_input_and_p_cap(failures: Array[String]) -> void:
	var invalid_item := _item("broken", "missing_base", "main_hand", [])
	var invalid: Dictionary = resolver.resolve(_base(0.25), {"main_hand": invalid_item}, "piercing_arrow")
	_expect(not bool(invalid.ok) and _contains(invalid.errors, "unknown base_item_id 'missing_base'"), "invalid item must return a clear error", failures)
	var over_item := _item("over-p", "piercer_gloves", "gloves", [
		{"family_id": "piercing_continuation", "tier": 4},
	])
	over_item.rune_id = "breeding_split"
	over_item.law_id = "pack_hunt_mark"
	var capped: Dictionary = resolver.resolve(_base(0.95), {"gloves": over_item}, "piercing_arrow")
	_expect(bool(capped.ok) and _near(capped.final_parameters.p, 1.0), "p must cap at 1.0", failures)
	_expect(capped.final_parameters.damage > 100.0, "p overflow must become ordinary continuation-hit damage", failures)
	_expect(_near(capped.R, 2.0) and capped.growth_classification == "exponential", "capped p must keep a stable R=2 upper boundary", failures)
	var malformed: Dictionary = resolver.resolve({"p": "0.25"}, [], "piercing_arrow")
	_expect(not bool(malformed.ok) and not malformed.errors.is_empty(), "malformed resolver input must fail without crashing", failures)
	_expect(malformed.final_parameters.is_empty() and malformed.parameter_sources.is_empty() and malformed.connected_interfaces.is_empty(), "failed resolution must not leak a partial Build", failures)
	_expect(malformed.build_fingerprint == "" and malformed.equipped_instance_ids.is_empty(), "failed resolution must not leak fingerprint metadata", failures)
	var missing_fixture: Dictionary = resolver.resolve_fixture("missing_fixture")
	_expect(not bool(missing_fixture.ok) and missing_fixture.final_parameters.is_empty(), "unknown fixtures must fail atomically", failures)


func _base(p: float) -> Dictionary:
	return {
		"p": p,
		"T": 2.0,
		"v": 200.0,
		"d": 100.0,
		"turn": 0.1,
		"damage": 100.0,
		"critical_chance": 0.05,
		"max_health": 100.0,
	}


func _fixed_starting_items() -> Dictionary:
	return {
		"main_hand": _item("start-main", "ashwood_longbow", "main_hand", []),
		"off_hand": _item("start-off", "lineage_quiver", "off_hand", []),
		"gloves": _item("start-gloves", "piercer_gloves", "gloves", []),
		"ring_1": _item("start-ring", "vitality_ring", "ring_1", []),
	}


func _parameter_loadout() -> Dictionary:
	return {
		"main_hand": _item("params-main", "swift_recurve_bow", "main_hand", [
			{"family_id": "carrier_power", "tier": 1},
			{"family_id": "seeking_distance", "tier": 1},
		]),
		"off_hand": _item("params-off", "lineage_quiver", "off_hand", [
			{"family_id": "projectile_lifetime", "tier": 1},
			{"family_id": "projectile_speed", "tier": 1},
		]),
		"gloves": _item("params-gloves", "piercer_gloves", "gloves", [
			{"family_id": "piercing_continuation", "tier": 1},
			{"family_id": "turn_response", "tier": 1},
		]),
		"ring_1": _item("params-ring", "vitality_ring", "ring_1", [
			{"family_id": "critical_chance", "tier": 1},
		]),
	}


func _item(instance_id: String, base_id: String, slot: String, affixes: Array, rune_id: String = "", law_id: String = "") -> Dictionary:
	return {
		"instance_id": instance_id,
		"base_item_id": base_id,
		"slot": slot,
		"affixes": affixes,
		"rune_id": rune_id,
		"law_id": law_id,
		"source": {"type": "test_fixture", "id": "resolver"},
		"law_seed": 424242,
	}


func _contains(errors: Array, needle: String) -> bool:
	for error in errors:
		if String(error).contains(needle):
			return true
	return false


func _near(left: Variant, right: Variant, epsilon: float = 0.000001) -> bool:
	return absf(float(left) - float(right)) <= epsilon


func _expect(condition: bool, message: String, failures: Array[String]) -> void: Assert.expect(condition, message, failures)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("PASS  test_build_resolver.gd")
		quit(0)
		return
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)
