extends SceneTree

const ContentRegistry := preload("res://src/content/content_registry.gd")
const ProxyBuild := preload("res://src/systems/proxy_build.gd")
const WHITE := ["near_enemy_horizon", "direct_gait", "single_key_execution", "short_trace_memory"]


func _initialize() -> void:
	var failures: Array[String] = []
	var registry = ContentRegistry.new()
	var load_errors: Array[String] = registry.load_all()
	_expect(load_errors.is_empty(), "catalog failed to load: %s" % str(load_errors), failures)
	if load_errors.is_empty():
		_test_supported_combinations(registry.cores, failures)
		_test_order_invariance(registry.cores, failures)
		_test_settings(registry.cores, failures)
		_test_fail_closed(registry.cores, failures)
		_test_alias_isolation(registry.cores, failures)
		_test_deterministic_bytes(registry.cores, failures)
		_test_resolved_validation_and_fingerprint(registry.cores, failures)
	if failures.is_empty():
		print("PASS  test_proxy_build.gd")
		quit(0)
		return
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _test_supported_combinations(catalog: Dictionary, failures: Array[String]) -> void:
	var builds := [
		WHITE,
		["marking_prism", "direct_gait", "single_key_execution", "short_trace_memory"],
		["near_enemy_horizon", "distance_keeping_gait", "single_key_execution", "short_trace_memory"],
		["marking_prism", "distance_keeping_gait", "single_key_execution", "short_trace_memory"],
	]
	for index in range(builds.size()):
		var result := ProxyBuild.compile({"cores": builds[index]}, catalog)
		_expect(result.ok, "supported build %d failed: %s" % [index, result.get("error", "")], failures)
		if not result.ok:
			continue
		var resolved: Dictionary = result.value
		_expect(resolved.schema_version == ProxyBuild.RESOLVED_SCHEMA_VERSION,
			"supported build %d has wrong schema version" % index, failures)
		_expect(_slots(resolved.cores) == ProxyBuild.SLOT_ORDER,
			"supported build %d was not emitted in fixed slot order" % index, failures)
		_expect(not JSON.stringify(resolved).contains("近敌视界") and not JSON.stringify(resolved).contains("protocol") and not JSON.stringify(resolved).contains("name"),
			"supported build %d leaked presentation fields" % index, failures)
		_expect(resolved.command_contract == ["move", "piercing_arrow", "stop_move"],
			"supported build %d has the wrong command contract" % index, failures)
		_expect(_core(resolved, "execution").capabilities.skill_count == 1
			and _core(resolved, "memory").capabilities.rotation_steps == 1,
			"supported build %d lost typed runtime capabilities" % index, failures)
		var expected_state := ["last_committed_action", "movement_band", "next_perception_tick", "target_entity_id"]
		if index in [1, 3]:
			expected_state = ["candidate_entity_ids", "last_committed_action", "movement_band", "next_perception_tick", "target_entity_id"]
		_expect(resolved.state_contract == expected_state, "supported build %d has the wrong state contract" % index, failures)
		_expect(String(resolved.semantic_fingerprint).length() == 64,
			"supported build %d has no SHA-256 semantic fingerprint" % index, failures)
		_expect(resolved.is_read_only() and resolved.cores.is_read_only() and resolved.cores[0].is_read_only(),
			"supported build %d is not deeply read-only" % index, failures)
	var marking := ProxyBuild.compile({"cores": builds[1]}, catalog)
	if marking.ok:
		var text := JSON.stringify(marking.value.observation_contract)
		_expect(text.contains("enemy.basic") and text.contains("enemy.public_classification_tags"),
			"marking prism lost its allowed observation channels", failures)
		for forbidden in ["status", "hazard", "telegraph"]:
			_expect(not text.contains(forbidden), "marking prism exposed forbidden %s data" % forbidden, failures)


func _test_order_invariance(catalog: Dictionary, failures: Array[String]) -> void:
	var canonical := ProxyBuild.compile({"cores": WHITE}, catalog)
	var permuted := ProxyBuild.compile({"cores": [WHITE[3], WHITE[1], WHITE[0], WHITE[2]]}, catalog)
	_expect(canonical.ok and permuted.ok and JSON.stringify(canonical.value) == JSON.stringify(permuted.value),
		"array permutation changed resolved bytes", failures)


func _test_settings(catalog: Dictionary, failures: Array[String]) -> void:
	var distance_build := ["near_enemy_horizon", "distance_keeping_gait", "single_key_execution", "short_trace_memory"]
	var defaults := ProxyBuild.compile({"cores": distance_build}, catalog)
	_expect(defaults.ok and _core(defaults.value, "movement").settings == {"distance_band": "mid"},
		"missing settings did not use distance-keeping defaults", failures)
	var far := ProxyBuild.compile({"cores": distance_build, "settings": {"distance_keeping_gait": {"distance_band": "far"}}}, catalog)
	_expect(far.ok and _core(far.value, "movement").settings == {"distance_band": "far"},
		"valid distance-keeping settings did not compile", failures)
	for bad_settings in [
		{"distance_keeping_gait": {"distance_band": "meters"}},
		{"distance_keeping_gait": {"distance_band": "near", "meters": 12}},
		{"distance_keeping_gait": {}},
		{"distance_keeping_gait": "near"},
	]:
		var bad := ProxyBuild.compile({"cores": distance_build, "settings": bad_settings}, catalog)
		_expect(not bad.ok and bad.error == "invalid_settings:distance_keeping_gait",
			"illegal distance-keeping settings were accepted: %s" % str(bad_settings), failures)
	var wrong_owner := ProxyBuild.compile({"cores": WHITE, "settings": {"distance_keeping_gait": {"distance_band": "near"}}}, catalog)
	_expect(not wrong_owner.ok and wrong_owner.error == "settings_for_unselected_core:distance_keeping_gait",
		"settings for an unequipped core were accepted", failures)
	var non_configurable := ProxyBuild.compile({"cores": WHITE, "settings": {"direct_gait": {}}}, catalog)
	_expect(not non_configurable.ok and non_configurable.error == "unexpected_settings:direct_gait",
		"settings on a non-configurable core were accepted", failures)


func _test_fail_closed(catalog: Dictionary, failures: Array[String]) -> void:
	var unsupported_count := 0
	for core_id in catalog:
		var core: Dictionary = catalog[core_id]
		if String(core.behavior_id) in ProxyBuild.SUPPORTED_BEHAVIORS:
			continue
		unsupported_count += 1
		var ids: Array = WHITE.duplicate()
		ids[ProxyBuild.SLOT_ORDER.find(String(core.slot))] = String(core_id)
		var unsupported := ProxyBuild.compile({"cores": ids}, catalog)
		_expect(not unsupported.ok and unsupported.error == "unsupported_behavior:%s" % core.behavior_id,
			"unimplemented behavior %s did not fail closed" % core.behavior_id, failures)
	_expect(unsupported_count == 10, "unsupported behavior census must remain exactly 10", failures)
	var duplicate := ProxyBuild.compile({"cores": ["near_enemy_horizon", "near_enemy_horizon", "single_key_execution", "short_trace_memory"]}, catalog)
	_expect(not duplicate.ok and duplicate.error == "duplicate_core_id:near_enemy_horizon",
		"duplicate core id was accepted", failures)
	var duplicate_slot := ProxyBuild.compile({"cores": ["near_enemy_horizon", "marking_prism", "single_key_execution", "short_trace_memory"]}, catalog)
	_expect(not duplicate_slot.ok and duplicate_slot.error == "duplicate_slot:perception",
		"duplicate slot was accepted", failures)
	var missing := ProxyBuild.compile({"cores": ["near_enemy_horizon", "direct_gait", "single_key_execution"]}, catalog)
	_expect(not missing.ok and missing.error == "invalid_core_count", "missing slot was accepted", failures)
	var unknown := ProxyBuild.compile({"cores": ["near_enemy_horizon", "direct_gait", "single_key_execution", "future_memory"]}, catalog)
	_expect(not unknown.ok and unknown.error == "unknown_core:future_memory", "unknown core was accepted", failures)
	var extra_field := ProxyBuild.compile({"cores": WHITE, "attachments": []}, catalog)
	_expect(not extra_field.ok and extra_field.error == "invalid_raw_build", "unknown raw-build field was accepted", failures)
	var bad_catalog := catalog.duplicate(true)
	bad_catalog.near_enemy_horizon["future"] = true
	var catalog_failure := ProxyBuild.compile({"cores": WHITE}, bad_catalog)
	_expect(not catalog_failure.ok and catalog_failure.error == "invalid_core_catalog:near_enemy_horizon",
		"unknown catalog core field was accepted", failures)


func _test_alias_isolation(catalog: Dictionary, failures: Array[String]) -> void:
	var raw := {"cores": WHITE.duplicate()}
	var mutable_catalog := catalog.duplicate(true)
	var result := ProxyBuild.compile(raw, mutable_catalog)
	_expect(result.ok, "alias-isolation fixture did not compile", failures)
	if not result.ok:
		return
	var before := JSON.stringify(result.value)
	raw.cores[0] = "state_parser"
	mutable_catalog.near_enemy_horizon.capabilities.target_count = 999
	_expect(JSON.stringify(result.value) == before, "input or catalog mutation polluted resolved output", failures)
	var editable_copy: Dictionary = result.value.duplicate(true)
	editable_copy.cores[0].capabilities.target_count = 999
	_expect(JSON.stringify(result.value) == before, "duplicate mutation polluted resolved output", failures)
	var second := ProxyBuild.compile({"cores": WHITE}, catalog)
	_expect(second.ok and not is_same(second.value.cores[0], result.value.cores[0]),
		"separate compile calls share nested output aliases", failures)


func _test_deterministic_bytes(catalog: Dictionary, failures: Array[String]) -> void:
	var reordered_catalog := {}
	var ids: Array = catalog.keys()
	ids.reverse()
	for id in ids:
		var core: Dictionary = catalog[id].duplicate(true)
		core.capabilities = _reordered_dictionary(core.capabilities)
		core.observation_channels.reverse()
		core.state_fields.reverse()
		core.command_kinds.reverse()
		reordered_catalog[id] = core
	var first := ProxyBuild.compile({"cores": WHITE}, catalog)
	var second := ProxyBuild.compile({"cores": [WHITE[2], WHITE[0], WHITE[3], WHITE[1]], "settings": {}}, reordered_catalog)
	_expect(first.ok and second.ok and JSON.stringify(first.value) == JSON.stringify(second.value),
		"same semantics did not produce byte-stable JSON", failures)


func _test_resolved_validation_and_fingerprint(catalog: Dictionary, failures: Array[String]) -> void:
	var white := ProxyBuild.compile({"cores": WHITE}, catalog)
	var marking := ProxyBuild.compile({"cores": ["marking_prism", "direct_gait", "single_key_execution", "short_trace_memory"]}, catalog)
	var distance_near := ProxyBuild.compile({"cores": ["near_enemy_horizon", "distance_keeping_gait", "single_key_execution", "short_trace_memory"], "settings": {"distance_keeping_gait": {"distance_band": "near"}}}, catalog)
	var distance_far := ProxyBuild.compile({"cores": ["near_enemy_horizon", "distance_keeping_gait", "single_key_execution", "short_trace_memory"], "settings": {"distance_keeping_gait": {"distance_band": "far"}}}, catalog)
	_expect(white.ok and marking.ok and distance_near.ok and distance_far.ok, "fingerprint fixtures did not compile", failures)
	if not (white.ok and marking.ok and distance_near.ok and distance_far.ok):
		return
	_expect(white.value.semantic_fingerprint != marking.value.semantic_fingerprint, "behavior change did not change fingerprint", failures)
	_expect(distance_near.value.semantic_fingerprint != distance_far.value.semantic_fingerprint, "effective setting change did not change fingerprint", failures)
	var changed_catalog := catalog.duplicate(true)
	changed_catalog.direct_gait.capabilities.approach_enter_targeting_distance_milli = 830
	var changed_core := ProxyBuild.compile({"cores": WHITE}, changed_catalog)
	_expect(changed_core.ok and changed_core.value.semantic_fingerprint != white.value.semantic_fingerprint, "effective core capability change did not change fingerprint", failures)
	var normalized := ProxyBuild.normalize_resolved(white.value)
	_expect(normalized.ok and JSON.stringify(normalized.value) == JSON.stringify(white.value), "valid resolved build did not normalize byte-identically", failures)
	_expect(normalized.value.is_read_only() and normalized.value.cores[0].capabilities.is_read_only(), "normalized resolved build was not deeply frozen", failures)
	var forged: Dictionary = white.value.duplicate(true)
	forged.cores[1].capabilities.approach_enter_targeting_distance_milli = 900
	var rejected := ProxyBuild.normalize_resolved(forged)
	_expect(not rejected.ok and rejected.error == "semantic_fingerprint_mismatch", "stale fingerprint was accepted", failures)
	var extra: Dictionary = white.value.duplicate(true)
	extra["future"] = true
	_expect(not ProxyBuild.normalize_resolved(extra).ok, "extra resolved field was accepted", failures)
	var reordered: Dictionary = white.value.duplicate(true)
	reordered.observation_contract.reverse()
	reordered.cores[0].observation_channels.reverse()
	var reordered_result := ProxyBuild.normalize_resolved(reordered)
	_expect(reordered_result.ok and JSON.stringify(reordered_result.value) == JSON.stringify(white.value), "order-synonymous resolved input was not canonicalized stably", failures)


func _slots(cores: Array) -> Array[String]:
	var result: Array[String] = []
	for core in cores:
		result.append(String(core.slot))
	return result


func _core(resolved: Dictionary, slot: String) -> Dictionary:
	for core_value in resolved.cores:
		if String(core_value.slot) == slot:
			return core_value
	return {}


func _reordered_dictionary(source: Dictionary) -> Dictionary:
	var result := {}
	var keys: Array = source.keys()
	keys.reverse()
	for key in keys:
		result[key] = source[key]
	return result


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
