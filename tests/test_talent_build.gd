extends SceneTree

const RegistryScript := preload("res://src/content/talent_registry.gd")
const BuildScript := preload("res://src/systems/talent_build.gd")
const ResolverScript := preload("res://src/systems/build_resolver.gd")
const ItemRegistryScript := preload("res://src/content/early_item_registry.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var registry := RegistryScript.new()
	if not registry.load_errors.is_empty():
		failures.append("catalog load: %s" % str(registry.load_errors))
	var build := BuildScript.new(registry)
	_test_catalog_contract(registry, failures)
	_test_validation_rules(build, failures)
	_test_compilation(build, failures)
	_test_resolver_integration(failures)
	_test_registry_failure_is_closed(failures)
	_test_three_skill_sequence(failures)
	if failures.is_empty():
		print("PASS  test_talent_build.gd")
		quit(0)
		return
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _test_catalog_contract(registry: RegistryScript, failures: Array[String]) -> void:
	var catalog := registry.catalog()
	_expect(bool(catalog.ok), "catalog: healthy registry must return ok", failures)
	var trees: Array = catalog.trees
	_expect(trees.size() == 3, "catalog: expected three trees", failures)
	var ranger: Dictionary = trees[0]
	_expect(String(ranger.class_id) == "ranger" and bool(ranger.implemented), "catalog: ranger tree must be implemented", failures)
	_expect((ranger.nodes as Array).size() == 15, "catalog: ranger tree must expose 15 nodes", failures)
	var implemented_count := 0
	for node_value in ranger.nodes:
		var node: Dictionary = node_value
		_expect(not String(node.description).strip_edges().is_empty(), "catalog: %s has no player description" % node.id, failures)
		if bool(node.implemented):
			implemented_count += 1
	_expect(implemented_count == 14, "catalog: ranger currently expects 14 implemented nodes", failures)


func _test_validation_rules(build: BuildScript, failures: Array[String]) -> void:
	var layer1 := ["ranger_steady_string", "ranger_long_breath", "ranger_keen_eye"]
	_expect(bool(build.validate({"allocated_ids": [], "stance": "mid"}, 10, ["ranger"]).ok), "validate: empty build must be valid", failures)
	_expect(not bool(build.validate({"allocated_ids": [layer1[0], layer1[1], "ranger_close_turn"], "stance": "mid"}, 10, ["ranger"]).ok), "validate: layer 2 must need three layer-1 points", failures)
	var layer2 := ["ranger_close_turn", "ranger_continuation_calibration", "ranger_defocused_tracking", "ranger_lineage_sense"]
	_expect(bool(build.validate({"allocated_ids": layer1 + layer2, "stance": "mid"}, 10, ["ranger"]).ok), "validate: valid 7-point topology was rejected", failures)
	var direct_layer3 := layer1 + layer2 + ["ranger_last_generation_loading", "ranger_three_skill_rhythm"]
	_expect(not bool(build.validate({"allocated_ids": direct_layer3, "stance": "mid"}, 10, ["ranger"]).ok), "validate: layer 3 must need eight lower-layer points", failures)
	var lower8 := layer1 + layer2 + ["ranger_recovery_pose"]
	_expect(bool(build.validate({"allocated_ids": lower8 + ["ranger_near_far_hunting"], "stance": "far"}, 10, ["ranger"]).ok), "validate: valid 9-point topology was rejected", failures)
	var refunded := lower8.duplicate()
	refunded.remove_at(0)
	_expect(not bool(build.validate({"allocated_ids": refunded + ["ranger_near_far_hunting"], "stance": "far"}, 10, ["ranger"]).ok), "validate: refunding support points must invalidate layer 3", failures)
	_expect(not bool(build.validate({"allocated_ids": ["ranger_steady_string"], "stance": "mid"}, 0, ["ranger"]).ok), "validate: points must not be overspent", failures)
	_expect(not bool(build.validate({"allocated_ids": ["ranger_steady_string"], "stance": "mid"}, 1, []).ok), "validate: locked class must be rejected", failures)
	_expect(not bool(build.validate({"allocated_ids": ["ranger_wind_slice_stance"], "stance": "mid"}, 10, ["ranger"]).ok), "validate: unimplemented node must be rejected", failures)
	_expect(not bool(build.validate({"allocated_ids": ["ranger_steady_string", "ranger_steady_string"], "stance": "mid"}, 10, ["ranger"]).ok), "validate: duplicate node must be rejected", failures)


func _test_compilation(build: BuildScript, failures: Array[String]) -> void:
	var ids := ["ranger_steady_string", "ranger_long_breath", "ranger_keen_eye", "ranger_light_step", "ranger_recovery_pose", "ranger_close_turn", "ranger_continuation_calibration", "ranger_defocused_tracking", "ranger_lineage_sense", "ranger_near_far_hunting"]
	var compiled := build.compile({"allocated_ids": ids, "stance": "near"}, 10, ["ranger"])
	_expect(bool(compiled.ok), "compile: valid 10-point build failed: %s" % str(compiled.errors), failures)
	_expect((compiled.talent_parameter_sources as Array).any(func(source): return String(source.talent_id) == "ranger_near_far_hunting" and String(source.parameter) == "turn"), "compile: near stance did not produce turn modifier", failures)
	var far := build.compile({"allocated_ids": ids, "stance": "far"}, 10, ["ranger"])
	_expect((far.talent_parameter_sources as Array).any(func(source): return String(source.talent_id) == "ranger_near_far_hunting" and String(source.parameter) == "T"), "compile: far stance did not produce lifetime modifier", failures)


func _test_resolver_integration(failures: Array[String]) -> void:
	var items := ItemRegistryScript.new()
	_expect(items.load_all().is_empty(), "resolver: item fixture failed", failures)
	var resolver := ResolverScript.new(items)
	var context := {
		"talents": {"allocated_ids": ["ranger_steady_string"], "stance": "mid"},
		"talent_points": 10,
		"unlocked_classes": ["ranger"],
	}
	var empty := resolver.resolve(_base(), {}, "piercing_arrow")
	var talented := resolver.resolve(_base(), {}, "piercing_arrow", context)
	_expect(bool(empty.ok) and bool(talented.ok), "resolver: builds failed: %s / %s" % [str(empty.errors), str(talented.errors)], failures)
	if bool(empty.ok) and bool(talented.ok):
		_expect(float(talented.final_parameters.v) > float(empty.final_parameters.v), "resolver: steady string did not affect speed", failures)
		_expect(String(empty.build_fingerprint) != String(talented.build_fingerprint), "resolver: talents must change fingerprint", failures)


func _test_registry_failure_is_closed(failures: Array[String]) -> void:
	var broken := RegistryScript.new("res://content/early_items.json")
	var build := BuildScript.new(broken)
	_expect(not bool(build.compile({"allocated_ids": [], "stance": "mid"}, 30, ["ranger"]).ok), "fail-closed: empty compile hid a broken registry", failures)
	_expect(not bool(build.compile({"allocated_ids": ["ranger_steady_string"], "stance": "mid"}, 30, ["ranger"]).ok), "fail-closed: broken registry accepted a node", failures)
	_expect(not bool(broken.catalog().ok), "fail-closed: broken catalog claimed ok", failures)


func _test_three_skill_sequence(failures: Array[String]) -> void:
	var sequence := preload("res://src/game/main.gd").new()
	var sequence_valid := sequence != null
	if sequence_valid:
		sequence.talent_capabilities = {"three_skill_rhythm_windup_ticks": 4}
		sequence._advance_three_skill_sequence("hunter_mark")
		sequence._advance_three_skill_sequence("piercing_arrow")
		_expect(sequence.three_skill_sequence_stage == 1 and not sequence.three_skill_bonus_ready, "sequence: wrong-order prefix did not restart on arrow", failures)
		sequence._advance_three_skill_sequence("hunter_mark")
		sequence._advance_three_skill_sequence("dash")
		_expect(sequence.three_skill_bonus_ready, "sequence: completed sequence did not arm the bonus", failures)
		sequence.free()


func _base() -> Dictionary:
	return {"p": 0.25, "T": 2.0, "v": 200.0, "d": 100.0, "turn": 0.1, "damage": 100.0, "max_health": 100.0}


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
