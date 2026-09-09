extends RefCounted

const ContentRegistry = preload("res://src/content/content_registry.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_real_files_load_and_validate(failures)
	_test_expected_census(failures)
	_test_sample_ids_and_names(failures)
	_test_ranger_presets(failures)
	_test_attachment_preset_rules(failures)
	_test_validation_rejects_bad_data(failures)
	return failures


func _test_real_files_load_and_validate(failures: Array[String]) -> void:
	var registry = ContentRegistry.new()
	var errors: Array[String] = registry.load_all()
	_expect(errors.is_empty(), "content: shipped JSON must load cleanly, got %s" % str(errors), failures)
	var second_errors: Array[String] = registry.load_all()
	_expect(second_errors.is_empty() and registry.preset_order.size() == 3,
		"content: reload must be idempotent", failures)


func _test_expected_census(failures: Array[String]) -> void:
	var registry = ContentRegistry.new()
	registry.load_all()
	_expect(registry.cores.size() == 16, "content: expected 16 cores", failures)
	_expect(registry.attachments.size() == 10, "content: expected 10 attachments", failures)
	_expect(registry.firmwares.size() == 16, "content: expected 16 firmwares", failures)
	var per_slot := {}
	for id in registry.cores:
		var core: Dictionary = registry.cores[id]
		var slot := String(core["slot"])
		per_slot[slot] = int(per_slot.get(slot, 0)) + 1
		_expect(int(core["numeric_slots"]) == 3, "core %s: numeric_slots must be 3" % id, failures)
	for slot in ContentRegistry.CORE_SLOTS:
		_expect(int(per_slot.get(slot, 0)) == 4, "content: slot %s must hold 4 cores" % slot, failures)
	var per_category := {}
	for id in registry.attachments:
		var attachment: Dictionary = registry.attachments[id]
		var category := String(attachment["category"])
		per_category[category] = int(per_category.get(category, 0)) + 1
		_expect(int(attachment["numeric_slots"]) == 3, "attachment %s: numeric_slots must be 3" % id, failures)
	for category in ContentRegistry.ATTACHMENT_CATEGORIES:
		_expect(int(per_category.get(category, 0)) == 2,
			"content: category %s must hold 2 attachments" % category, failures)
	var compatible_counts := {}
	for id in registry.firmwares:
		var firmware: Dictionary = registry.firmwares[id]
		var compatible := String(firmware["compatible_slot"])
		compatible_counts[compatible] = int(compatible_counts.get(compatible, 0)) + 1
		_expect(String(firmware["semantics"]) != "", "firmware %s: semantics required" % id, failures)
	_expect(int(compatible_counts.get("perception", 0)) == 3, "firmware: 3 for perception", failures)
	_expect(int(compatible_counts.get("movement", 0)) == 3, "firmware: 3 for movement", failures)
	_expect(int(compatible_counts.get("execution", 0)) == 4, "firmware: 4 for execution", failures)
	_expect(int(compatible_counts.get("memory", 0)) == 3, "firmware: 3 for memory", failures)
	_expect(int(compatible_counts.get("attachment", 0)) == 3, "firmware: 3 for attachment", failures)


func _test_sample_ids_and_names(failures: Array[String]) -> void:
	var registry = ContentRegistry.new()
	registry.load_all()
	var expected_names := {
		"near_enemy_horizon": "近敌视界",
		"lineage_cache": "谱系缓存",
		"wish_picker": "愿望拾取器",
		"cycle_resetter": "循环复位器",
		"marker_priority": "标记者优先",
		"consecutive_contract": "连续契约",
	}
	for id in expected_names:
		var table: Dictionary = registry.cores if registry.cores.has(id) else (
			registry.attachments if registry.attachments.has(id) else registry.firmwares
		)
		_expect(table.has(id), "content: missing id %s" % id, failures)
		if table.has(id):
			_expect(String(table[id]["name"]) == String(expected_names[id]),
				"content: %s must be named %s" % [id, expected_names[id]], failures)


func _test_ranger_presets(failures: Array[String]) -> void:
	var registry = ContentRegistry.new()
	registry.load_all()
	var shared: Dictionary = registry.preset_shared_parameters
	_expect(_near(shared.get("shared_lifetime"), 16.0), "presets: shared lifetime must be 16", failures)
	_expect(_near(shared.get("distance"), 180.0), "presets: distance must be 180", failures)
	_expect(_near(shared.get("speed"), 600.0), "presets: speed must be 600", failures)
	_expect(_near(shared.get("minimum_turn_time"), 0.12), "presets: turn time must be 0.12", failures)
	var equipped: Dictionary = registry.preset_equipped_parameters
	_expect(_near(equipped.get("shared_lifetime"), 34.0), "presets: equipped lifetime must be 34", failures)
	_expect(_near(equipped.get("distance"), 150.0), "presets: equipped distance must be 150", failures)
	_expect(_near(equipped.get("speed"), 620.0), "presets: equipped speed must be 620", failures)
	_expect(_near(equipped.get("minimum_turn_time"), 0.18), "presets: equipped turn time must be 0.18", failures)
	_expect(registry.presets.size() == 3, "presets: exactly 3 diagnostic presets", failures)
	_expect(registry.preset_order == ["convergent", "critical", "exponential"],
		"presets: JSON order must drive the base-screen order", failures)
	var expected_p := {"convergent": 0.49, "critical": 0.50, "exponential": 0.61}
	for id in expected_p:
		_expect(registry.presets.has(id), "presets: missing preset %s" % id, failures)
		if registry.presets.has(id):
			_expect(_near(registry.presets[id].get("p"), float(expected_p[id])),
				"presets: %s must use p=%s" % [id, expected_p[id]], failures)


func _test_attachment_preset_rules(failures: Array[String]) -> void:
	var registry = ContentRegistry.new()
	registry.load_all()
	var good: Array[String] = registry.validate_attachment_preset(["wish_picker", "fork_compass", "evasion_safeguard"])
	_expect(good.is_empty(), "attachment preset: distinct categories must pass, got %s" % str(good), failures)
	var same_category: Array[String] = registry.validate_attachment_preset(
		["wish_picker", "destiny_sieve", "evasion_safeguard"])
	_expect(not same_category.is_empty(), "attachment preset: repeated category must fail", failures)
	var duplicated: Array[String] = registry.validate_attachment_preset(
		["wish_picker", "wish_picker", "evasion_safeguard"])
	_expect(not duplicated.is_empty(), "attachment preset: duplicate attachment must fail", failures)
	var unknown: Array[String] = registry.validate_attachment_preset(["wish_picker", "fork_compass", "not_real"])
	_expect(not unknown.is_empty(), "attachment preset: unknown id must fail", failures)
	var wrong_size: Array[String] = registry.validate_attachment_preset(["wish_picker", "fork_compass"])
	_expect(not wrong_size.is_empty(), "attachment preset: size != 3 must fail", failures)


func _test_validation_rejects_bad_data(failures: Array[String]) -> void:
	var registry = ContentRegistry.new()
	var dup := {
		"schema_version": 1,
		"cores": [
			{"id": "x", "name": "甲", "slot": "perception", "protocol": "p", "numeric_slots": 3},
			{"id": "x", "name": "乙", "slot": "perception", "protocol": "p", "numeric_slots": 3},
		],
		"attachments": [],
		"firmwares": [],
	}
	var dup_errors: Array[String] = registry.validate_proxy_components(dup)
	_expect(_has_substring(dup_errors, "duplicate id"), "validator: duplicate ids must be rejected", failures)
	_expect(_has_substring(dup_errors, "core slot perception has 2 entries"),
		"validator: wrong core count per slot must be rejected", failures)
	_expect(_has_substring(dup_errors, "firmwares"), "validator: firmware count must be checked", failures)
	var bad_slots := {
		"schema_version": 1,
		"cores": [{"id": "y", "name": "甲", "slot": "vibes", "protocol": "p", "numeric_slots": 2}],
		"attachments": [{"id": "a", "name": "附件", "category": "tactics", "protocol": "p", "numeric_slots": 3}],
		"firmwares": [],
	}
	var slot_errors: Array[String] = registry.validate_proxy_components(bad_slots)
	_expect(_has_substring(slot_errors, "unknown slot"), "validator: unknown core slot must be rejected", failures)
	_expect(_has_substring(slot_errors, "numeric_slots must be 3"),
		"validator: numeric_slots != 3 must be rejected", failures)
	_expect(_has_substring(slot_errors, "category tactics has 1 entries"),
		"validator: wrong attachment category count must be rejected", failures)
	var bad_protocols := {
		"schema_version": 1,
		"cores": [{"id": "no_core_protocol", "name": "核心", "slot": "perception", "numeric_slots": 3}],
		"attachments": [{"id": "blank_attachment_protocol", "name": "附件", "category": "tactics", "protocol": "  ", "numeric_slots": 3}],
		"firmwares": [],
	}
	var protocol_errors: Array[String] = registry.validate_proxy_components(bad_protocols)
	_expect(_has_substring(protocol_errors, "core no_core_protocol: missing protocol"),
		"validator: core protocol must be non-empty", failures)
	_expect(_has_substring(protocol_errors, "attachment blank_attachment_protocol: missing protocol"),
		"validator: attachment protocol must be non-empty", failures)
	var wrong_firmware_distribution := {
		"schema_version": 1,
		"cores": [],
		"attachments": [],
		"firmwares": [],
	}
	for index in range(16):
		wrong_firmware_distribution["firmwares"].append({
			"id": "firmware_%d" % index,
			"name": "固件%d" % index,
			"compatible_slot": "execution",
			"semantics": "有效语义",
		})
	var firmware_errors: Array[String] = registry.validate_proxy_components(wrong_firmware_distribution)
	_expect(_has_substring(firmware_errors, "firmware slot execution has 16 entries, expected 4"),
		"validator: firmware distribution must be exact even when total count is 16", failures)
	wrong_firmware_distribution["firmwares"][0]["semantics"] = ""
	firmware_errors = registry.validate_proxy_components(wrong_firmware_distribution)
	_expect(_has_substring(firmware_errors, "firmware firmware_0: missing semantics"),
		"validator: firmware semantics must remain required", failures)
	var bad_presets := {
		"schema_version": 2,
		"shared_parameters": {"shared_lifetime": 16.0, "distance": 180.0, "speed": 600.0, "minimum_turn_time": 0.12},
		"presets": [
			{"id": "over", "name": "越界", "p": 1.5},
			{"id": "zero", "name": "零", "p": 0.0},
			{"id": "over", "name": "重复", "p": 0.5},
			{"id": "text", "name": "文字", "p": "0.5"},
		],
	}
	var preset_errors: Array[String] = registry.validate_ranger_presets(bad_presets)
	_expect(_has_substring(preset_errors, "schema_version must be 1"),
		"validator: ranger preset schema version must be 1", failures)
	_expect(_has_substring(preset_errors, "out of range"), "validator: p>1 must be rejected", failures)
	_expect(_has_substring(preset_errors, "out of range"), "validator: p<=0 must be rejected", failures)
	_expect(_has_substring(preset_errors, "duplicate preset id"), "validator: duplicate preset id must be rejected", failures)
	_expect(_has_substring(preset_errors, "p must be a number"), "validator: non-numeric p must be rejected", failures)
	var bad_proxy_schema := {"schema_version": 2, "cores": [], "attachments": [], "firmwares": []}
	_expect(_has_substring(registry.validate_proxy_components(bad_proxy_schema), "schema_version must be 1"),
		"validator: proxy component schema version must be 1", failures)
	var missing_shared := {"schema_version": 1, "shared_parameters": {}, "presets": []}
	_expect(not registry.validate_ranger_presets(missing_shared).is_empty(),
		"validator: missing shared_parameters must be rejected", failures)
	var missing_equipped := {
		"schema_version": 1,
		"shared_parameters": {"shared_lifetime": 16.0, "distance": 180.0, "speed": 600.0, "minimum_turn_time": 0.12},
		"presets": [{"id": "valid", "name": "有效", "p": 0.5}],
	}
	_expect(_has_substring(registry.validate_ranger_presets(missing_equipped), "missing prototype_equipped_parameters"),
		"validator: missing equipped parameters must be rejected", failures)


func _near(value: Variant, expected: float) -> bool:
	if value is int or value is float:
		return absf(float(value) - expected) < 0.000001
	return false


func _has_substring(errors: Array[String], needle: String) -> bool:
	for error in errors:
		if error.contains(needle):
			return true
	return false


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
