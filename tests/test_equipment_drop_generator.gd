extends SceneTree

const BuildResolverScript = preload("res://src/systems/build_resolver.gd")
const EarlyItemRegistryScript = preload("res://src/content/early_item_registry.gd")
const GeneratorScript = preload("res://src/systems/equipment_drop_generator.gd")

var registry: RefCounted
var generator: RefCounted


func _initialize() -> void:
	var failures: Array[String] = []
	registry = EarlyItemRegistryScript.new()
	var load_failures: Array[String] = registry.load_all()
	if not load_failures.is_empty():
		failures.append("fixture registry failed to load: %s" % "; ".join(load_failures))
		_finish(failures)
		return
	generator = GeneratorScript.new(registry)

	_test_determinism_and_stable_diversion(failures)
	_test_registry_and_resolver_legality(failures)
	_test_guaranteed_family(failures)
	_test_unknown_and_empty_inputs(failures)
	_test_instance_id_uniqueness(failures)
	_finish(failures)


func _test_determinism_and_stable_diversion(failures: Array[String]) -> void:
	var tags := ["equipment_general", "projectile_speed", "damage"]
	var first: Dictionary = generator.generate_drop(77123, "growth_check", 4, tags)
	var repeated: Dictionary = generator.generate_drop(77123, "growth_check", 4, tags)
	var reordered: Dictionary = generator.generate_drop(77123, "growth_check", 4, ["damage", "equipment_general", "projectile_speed"])
	var diverted: Dictionary = generator.generate_drop(77123, "growth_check", 5, tags)
	_expect(not first.is_empty() and first == repeated, "same deterministic input must reproduce every ItemInstance field", failures)
	_expect(first == reordered, "drop tag order must not perturb the deterministic stream", failures)
	_expect(not diverted.is_empty() and diverted != first and diverted.instance_id != first.instance_id, "different drop indexes must stably split the stream", failures)


func _test_registry_and_resolver_legality(failures: Array[String]) -> void:
	var cases := [
		["main_hand"], ["off_hand"], ["gloves"], ["ring"],
		["piercing_probability"], ["shared_lifetime"], ["projectile_speed"],
		["targeting_distance"], ["turn_time"], ["damage"], ["critical"], ["survival"],
	]
	var resolver: RefCounted = BuildResolverScript.new(registry)
	for index in range(cases.size()):
		var item: Dictionary = generator.generate_drop(9001, "legality_room", index, cases[index])
		_expect(not item.is_empty(), "recognized equipment tags must materialize an item: %s" % str(cases[index]), failures)
		if item.is_empty():
			continue
		var validation: Array[String] = registry.validate_item_instance(item)
		_expect(validation.is_empty(), "generated ItemInstance must pass EarlyItemRegistry: %s" % "; ".join(validation), failures)
		var resolved: Dictionary = resolver.resolve(_base_parameters(), {String(item.slot): item}, "piercing_arrow")
		_expect(bool(resolved.get("ok", false)), "generated ItemInstance must be accepted by BuildResolver: %s" % str(resolved.get("errors", [])), failures)


func _test_guaranteed_family(failures: Array[String]) -> void:
	var drops: Array[Dictionary] = generator.generate_drops(551, "elite_reward", 0, 5, ["main_hand"], "maximum_health")
	_expect(drops.size() == 5, "a valid guarantee must preserve the requested drop count", failures)
	var found := false
	for item in drops:
		for affix in (item.affixes as Array):
			if String((affix as Dictionary).family_id) == "maximum_health":
				found = true
				_expect(String(item.slot) in ["gloves", "ring_1"], "guarantee fallback must still choose a compatible slot", failures)
	_expect(found, "at least one generated item must contain guarantee_family", failures)


func _test_unknown_and_empty_inputs(failures: Array[String]) -> void:
	_expect(generator.generate_drop(1, "room", 0, []).is_empty(), "empty drop tags must fail closed", failures)
	_expect(generator.generate_drop(1, "room", 0, ["unknown_tag"]).is_empty(), "all-unknown drop tags must fail closed", failures)
	_expect(generator.generate_drop(1, "tutorial", 0, ["starter_fixed"]).is_empty(), "starter_fixed must remain an authored loadout tag, not generate random equipment", failures)
	_expect(generator.generate_drop(1, "room", 0, ["add_dice", "proxy_core_fixed"]).is_empty(), "non-equipment campaign tags must not become equipment", failures)
	_expect(generator.generate_drop(1, "room", 0, ["equipment_general"], "missing_family").is_empty(), "unknown guarantee_family must fail closed", failures)
	_expect(generator.generate_drop(1, "", 0, ["equipment_general"]).is_empty(), "empty source id must fail closed", failures)
	_expect(generator.generate_drop(1, "room", -1, ["equipment_general"]).is_empty(), "negative drop index must fail closed", failures)
	var mixed: Dictionary = generator.generate_drop(1, "room", 0, ["unknown_tag", "equipment_general"])
	_expect(not mixed.is_empty(), "unknown tags must be ignored when a recognized equipment tag remains", failures)


func _test_instance_id_uniqueness(failures: Array[String]) -> void:
	var ids := {}
	for seed in range(8):
		var drops: Array[Dictionary] = generator.generate_drops(seed, "repeatable_side_room", 0, 32, ["equipment_general"])
		_expect(drops.size() == 32, "batch generation must return every requested drop", failures)
		for item in drops:
			var instance_id := String(item.instance_id)
			_expect(instance_id.begins_with("drop_") and instance_id.length() == 69, "instance_id must use the stable SHA-256 identity format", failures)
			_expect(not ids.has(instance_id), "instance_id collision: %s" % instance_id, failures)
			ids[instance_id] = true
	_expect(ids.size() == 256, "seed/index matrix must produce 256 unique instance_ids", failures)


func _base_parameters() -> Dictionary:
	return {
		"p": 0.25,
		"T": 2.0,
		"v": 200.0,
		"d": 100.0,
		"turn": 0.1,
		"damage": 100.0,
		"critical_chance": 0.05,
		"max_health": 100.0,
	}


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("PASS  test_equipment_drop_generator.gd")
		quit(0)
		return
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)
