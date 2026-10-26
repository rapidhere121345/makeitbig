extends "res://tests/helpers/application_state_suite.gd"

## Equip, try-on preview and salvage transactions.
const EarlyItemRegistryScript = preload("res://src/content/early_item_registry.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_atomic_equipment_and_resolved_snapshot(failures)
	_test_equip_preview_errors_are_atomic(failures)
	_test_equip_preview_matches_real_equip(failures)
	_test_equip_preview_interface_deltas(failures)
	_test_equip_preview_session_invariance(failures)
	_test_salvage_validation_errors(failures)
	_test_salvage_track_mapping_and_consistency(failures)
	_test_salvage_commit_and_atomics(failures)
	_test_salvage_persistence_roundtrip(failures)
	return failures


func _test_atomic_equipment_and_resolved_snapshot(failures: Array[String]) -> void:
	var state := ApplicationState.new()
	_expect(_code(state.equip_item("x")) == "profile_required", "equip: profile should be required", failures)
	_expect(_code(state.resolved_build_snapshot()) == "profile_required", "resolve: profile should be required", failures)
	state.start_new_profile()
	state.select_ranger_build("critical")
	var resolved: Dictionary = state.resolved_build_snapshot()
	_expect(bool(resolved.get("ok", false)) and int(resolved.generation_count) == 80
		and _is_fingerprint(String(resolved.build_fingerprint))
		and resolved.equipped_instance_ids.size() == 12,
		"resolve: fixture did not produce a complete deterministic snapshot", failures)
	var before_failure := state.profile
	_expect(_code(state.equip_item("not-owned")) == "item_not_owned", "equip: ownership was not enforced", failures)
	_expect(state.profile == before_failure, "equip: failed ownership check changed state", failures)
	_expect(_code(state.equip_item("calibration_critical_main_hand")) == "item_already_equipped",
		"equip: duplicate instance was not rejected", failures)
	_expect(state.profile == before_failure, "equip: duplicate rejection changed state", failures)
	var mixed: Dictionary = state.equip_item("fixed_start_main_hand")
	_expect(bool(mixed.get("ok", false)) and String(state.profile.active_build.equipped_item_ids.main_hand) == "fixed_start_main_hand",
		"equip: owned mixed-build item was not atomically equipped", failures)
	var unequipped: Dictionary = state.unequip_item("main_hand")
	_expect(bool(unequipped.get("ok", false)) and String(state.profile.active_build.equipped_item_ids.main_hand).is_empty(),
		"unequip: prototype-open slot was not cleared", failures)
	var before_bad_slot := state.profile
	_expect(_code(state.unequip_item("head")) == "slot_not_prototype_open" and state.profile == before_bad_slot,
		"unequip: closed slot failure was not atomic", failures)
	var payload := state.persistent_payload("base")
	_expect(not payload.profile.has("resolved_build") and not payload.profile.active_build.has("resolved_build")
		and not payload.profile.active_build.has("preset_id") and not payload.profile.active_build.has("equipment"),
		"payload: derived build data leaked into persistence", failures)


func _test_equip_preview_errors_are_atomic(failures: Array[String]) -> void:
	var empty_state := ApplicationState.new()
	_expect(_code(empty_state.preview_equip_item("anything")) == "profile_required",
		"preview: profile should be required", failures)

	var state := ApplicationState.new()
	state.start_new_profile()
	var before := state.profile
	_expect(_code(state.preview_equip_item("")) == "invalid_instance_id"
		and _code(state.preview_equip_item("   ")) == "invalid_instance_id",
		"preview: empty or blank instance id should be rejected", failures)
	_expect(_code(state.preview_equip_item("calibration_exponential_main_hand")) == "item_not_owned",
		"preview: unowned item should be rejected", failures)
	_expect(_code(state.preview_equip_item("fixed_start_main_hand")) == "item_already_equipped",
		"preview: already-equipped item should be rejected", failures)
	_expect(state.profile == before, "preview: failed previews changed profile state", failures)

	# Closed-slot parity: registry validation already rejects non-prototype-open slots,
	# so the preview slot guard (mirrored from equip_item) is defense-in-depth only with
	# the current content. This pins that invariant instead of reaching dead code.
	var registry := EarlyItemRegistryScript.new()
	_expect(registry.load_all().is_empty(), "preview: item registry failed to load", failures)
	var closed_slot_item: Dictionary = (before.inventory.equipment as Array)[0].duplicate(true)
	closed_slot_item["slot"] = "head"
	_expect(not registry.validate_item_instance(closed_slot_item).is_empty(),
		"preview: closed-slot items must fail registry validation before the preview slot guard", failures)


func _test_equip_preview_matches_real_equip(failures: Array[String]) -> void:
	var state := ApplicationState.new()
	state.start_new_profile()
	state.select_ranger_build("exponential")
	state.select_ranger_build("critical")
	# Owned = fixed_start + calibration_exponential + calibration_critical;
	# active build = calibration_critical.
	var current := state.resolved_build_snapshot()
	_expect(bool(current.get("ok", false)), "preview: current build did not resolve", failures)
	var current_p := float(current.final_parameters.p)
	var before := state.profile

	var up := state.preview_equip_item("calibration_exponential_main_hand")
	_expect(bool(up.get("ok", false))
		and String(up.instance_id) == "calibration_exponential_main_hand"
		and String(up.slot) == "main_hand",
		"preview: owned inventory candidate was not previewed", failures)
	_expect(float(up.final_parameters.p) > current_p,
		"preview: exponential main_hand should raise final p", failures)
	_expect(_is_fingerprint(String(up.build_fingerprint)) and not String(up.growth_classification).is_empty(),
		"preview: post-equip fingerprint or classification is missing", failures)
	_expect(up.interfaces_gained.is_empty() and up.interfaces_lost.is_empty()
		and up.tags_gained.is_empty() and up.tags_lost.is_empty(),
		"preview: affix-only swap must not fabricate interface or tag deltas", failures)
	_expect(up.current_resolved == current,
		"preview: current_resolved diverges from the authoritative snapshot", failures)

	var down := state.preview_equip_item("fixed_start_main_hand")
	_expect(bool(down.get("ok", false)) and float(down.final_parameters.p) < current_p,
		"preview: fixed main_hand should lower final p", failures)
	_expect(state.profile == before, "preview: previews changed profile state", failures)

	# Repeated previews are deterministic and returned data must not alias internals.
	var pristine := up.duplicate(true)
	_expect(state.preview_equip_item("calibration_exponential_main_hand") == pristine,
		"preview: repeated preview is not deterministic", failures)
	var tampered_parameters: Dictionary = up.resolved_build.final_parameters
	tampered_parameters["p"] = -999.0
	(up.final_parameters as Dictionary)["p"] = -999.0
	(up.interfaces_gained as Array).append("tampered")
	(up.tags_gained as Array).append("tampered")
	(up.current_resolved as Dictionary)["build_fingerprint"] = "tampered"
	_expect(state.preview_equip_item("calibration_exponential_main_hand") == pristine,
		"preview: returned preview data aliases internal state", failures)
	_expect(state.profile == before and state.resolved_build_snapshot() == current,
		"preview: preview mutated profile or resolved state", failures)

	# The previewed build must resolve exactly like the real equip.
	var equipped := state.equip_item("calibration_exponential_main_hand")
	_expect(bool(equipped.get("ok", false)), "preview: real equip after preview failed", failures)
	var after := state.resolved_build_snapshot()
	_expect(pristine.resolved_build == after
		and pristine.final_parameters == after.final_parameters
		and String(pristine.build_fingerprint) == String(after.build_fingerprint)
		and String(pristine.growth_classification) == String(after.growth_classification)
		and pristine.resolved_build.connected_interfaces == after.connected_interfaces,
		"preview: previewed resolved build diverges from the real equip result", failures)


func _test_equip_preview_interface_deltas(failures: Array[String]) -> void:
	var state := ApplicationState.new()
	state.start_new_profile()
	state.select_ranger_build("critical")
	for slot in ["main_hand", "off_hand", "gloves", "ring_1"]:
		_expect(bool(state.unequip_item(slot).get("ok", false)), "preview setup: unequip %s failed" % slot, failures)
		_expect(bool(state.equip_item("fixed_start_%s" % slot).get("ok", false)), "preview setup: equip fixed %s failed" % slot, failures)
	var current := state.resolved_build_snapshot()
	_expect(bool(current.get("ok", false)) and current.connected_interfaces == ["piercing_continuation"],
		"preview setup: fixed-equipment baseline interfaces are wrong", failures)
	var parameters_before: Dictionary = current.final_parameters

	# Calibration gloves carry the breeding_split rune -> exactly one gained interface.
	var gain := state.preview_equip_item("calibration_critical_gloves")
	_expect(bool(gain.get("ok", false))
		and gain.interfaces_gained == ["breedable_event"]
		and gain.interfaces_lost.is_empty(),
		"preview: rune item did not report the gained interface", failures)
	_expect(gain.tags_gained.is_empty() and gain.tags_lost.is_empty(),
		"preview: interface change must not fabricate tag deltas", failures)
	_expect(gain.final_parameters == parameters_before,
		"preview: pure interface item must not change final parameters", failures)

	# The real equip keeps the preview authoritative; dropping the rune reports the loss.
	var equipped := state.equip_item("calibration_critical_gloves")
	_expect(bool(equipped.get("ok", false)), "preview: real equip of rune item failed", failures)
	_expect(equipped.resolved_build == gain.resolved_build,
		"preview: rune preview diverged from the real equip result", failures)
	var before_loss := state.profile
	var loss := state.preview_equip_item("fixed_start_gloves")
	_expect(bool(loss.get("ok", false))
		and loss.interfaces_lost == ["breedable_event"]
		and loss.interfaces_gained.is_empty(),
		"preview: dropping the rune item did not report the lost interface", failures)
	_expect(loss.tags_gained.is_empty() and loss.tags_lost.is_empty(),
		"preview: dropped interface must not fabricate tag deltas", failures)
	_expect(state.profile == before_loss, "preview: loss preview changed profile state", failures)


func _test_equip_preview_session_invariance(failures: Array[String]) -> void:
	var state := ApplicationState.new()
	state.start_new_profile()
	state.select_ranger_build("critical")
	state.prepare_contract({"contract_id": "preview-probe", "mode": "Manual", "seed": 5, "room_count": 2})
	_expect(bool(state.begin_session().get("ok", false)), "preview: session setup failed", failures)
	var profile_before := state.profile
	var session_before := state.active_session
	var result_before := state.last_result
	var pending_before := state.pending_contract
	var preview := state.preview_equip_item("fixed_start_main_hand")
	_expect(bool(preview.get("ok", false)), "preview: probe during active session failed", failures)
	_expect(_code(state.preview_equip_item("missing-instance")) == "item_not_owned",
		"preview: unowned probe during session should fail", failures)
	_expect(state.profile == profile_before and state.active_session == session_before
		and state.last_result == result_before and state.pending_contract == pending_before,
		"preview: preview changed profile, pending, session, or result state", failures)


func _test_salvage_validation_errors(failures: Array[String]) -> void:
	var empty_state := ApplicationState.new()
	_expect(_code(empty_state.salvage_item_preview("fixed_start_main_hand")) == "profile_required"
		and _code(empty_state.salvage_item("fixed_start_main_hand")) == "profile_required",
		"salvage: profile should be required for preview and commit", failures)

	var state := ApplicationState.new()
	state.start_new_profile()
	_expect(_code(state.salvage_item_preview("")) == "invalid_instance_id"
		and _code(state.salvage_item_preview("   ")) == "invalid_instance_id"
		and _code(state.salvage_item("")) == "invalid_instance_id",
		"salvage: empty or blank instance id should be rejected", failures)
	_expect(_code(state.salvage_item_preview("missing-instance")) == "item_not_owned"
		and _code(state.salvage_item("missing-instance")) == "item_not_owned",
		"salvage: unowned instance should be rejected", failures)
	var starter_preview := state.salvage_item_preview("fixed_start_main_hand")
	_expect(bool(starter_preview.get("ok", false)) and String(starter_preview.get("equipped_slot", "")) == "main_hand",
		"salvage: equipped fixed-start item should preview an explicit safe unequip", failures)
	state.select_ranger_build("critical")
	var calibration_preview := state.salvage_item_preview("calibration_critical_main_hand")
	_expect(bool(calibration_preview.get("ok", false)) and String(calibration_preview.get("equipped_slot", "")) == "main_hand",
		"salvage: equipped calibration item should be eligible with safe unequip", failures)
	_inject_salvage_probe(state, _salvage_probe_item("salvage_probe_other", 1, "other"))
	_expect(bool(state.salvage_item_preview("salvage_probe_other").get("ok", false)),
		"salvage: a registry-valid owned item should not be rejected by source type", failures)
	var invalid: Dictionary = _salvage_probe_item("salvage_probe_invalid", 2)
	invalid["base_item_id"] = "no_such_base"
	_inject_salvage_probe(state, invalid)
	_expect(_code(state.salvage_item_preview("salvage_probe_invalid")) == "invalid_item_instance"
		and _code(state.salvage_item("salvage_probe_invalid")) == "invalid_item_instance",
		"salvage: registry-invalid item must be rejected", failures)
	_inject_salvage_probe(state, _salvage_probe_item("salvage_probe_equipped", 7))
	_expect(bool(state.unequip_item("main_hand").get("ok", false))
		and bool(state.equip_item("salvage_probe_equipped").get("ok", false)),
		"salvage: equipping the probe for safe-unequip coverage failed", failures)
	var equipped_preview := state.salvage_item_preview("salvage_probe_equipped")
	_expect(bool(equipped_preview.get("ok", false)) and String(equipped_preview.get("equipped_slot", "")) == "main_hand",
		"salvage: equipped item preview did not expose its safe-unequip slot", failures)
	var before_probes := state.profile
	_expect(bool(state.salvage_item_preview("salvage_probe_other").get("ok", false))
		and bool(state.salvage_item_preview("salvage_probe_equipped").get("ok", false))
		and _code(state.salvage_item("missing-instance")) == "item_not_owned"
		and state.profile == before_probes,
		"salvage: previews or rejected ids changed profile state", failures)

	var equipped_state := ApplicationState.new()
	equipped_state.start_new_profile()
	var equipped_commit := equipped_state.salvage_item("fixed_start_main_hand")
	_expect(bool(equipped_commit.get("ok", false))
		and String(equipped_commit.get("unequipped_slot", "")) == "main_hand"
		and String(equipped_state.profile.active_build.equipped_item_ids.main_hand).is_empty()
		and not _has_equipment_instance(equipped_state.profile.inventory.equipment, "fixed_start_main_hand")
		and bool(equipped_state.resolved_build_snapshot().get("ok", false)),
		"salvage: equipped starter commit did not atomically unequip, remove, and preserve a resolvable build", failures)


func _test_salvage_track_mapping_and_consistency(failures: Array[String]) -> void:
	var probes := {
		"salvage_probe_add": {"seed": 18, "operation": "inscribe"},
		"salvage_probe_rewrite": {"seed": 5, "operation": "rewrite"},
		"salvage_probe_refine": {"seed": 3, "operation": "refine"},
	}
	var registry := EarlyItemRegistryScript.new()
	_expect(registry.load_all().is_empty(), "salvage: item registry failed to load", failures)
	var state := ApplicationState.new()
	state.start_new_profile()
	for probe_id in probes:
		var probe: Dictionary = _salvage_probe_item(probe_id, int((probes[probe_id] as Dictionary).seed))
		_expect(registry.validate_item_instance(probe).is_empty(),
			"salvage: constructed %s probe failed registry validation" % probe_id, failures)
		_inject_salvage_probe(state, probe)
	var before := state.profile
	for probe_id in probes:
		var preview: Dictionary = state.salvage_item_preview(probe_id)
		_expect(bool(preview.get("ok", false))
			and String(preview.instance_id) == probe_id
			and String(preview.operation) == String((probes[probe_id] as Dictionary).operation)
			and int(preview.amount) == 1
			and preview.item == _salvage_probe_item(probe_id, int((probes[probe_id] as Dictionary).seed)),
			"salvage: deterministic track preview for %s is wrong" % probe_id, failures)
		_expect(state.profile == before, "salvage: preview for %s changed profile state" % probe_id, failures)
		var tampered: Dictionary = preview.item
		tampered["instance_id"] = "tampered"
		_expect(state.salvage_item_preview(probe_id).item == _salvage_probe_item(probe_id, int((probes[probe_id] as Dictionary).seed))
			and state.profile == before,
			"salvage: preview item aliased inventory for %s" % probe_id, failures)
	_expect(state.salvage_item_preview("salvage_probe_add").operation == state.salvage_item_preview("salvage_probe_add").operation
		and state.salvage_item_preview("salvage_probe_rewrite").operation == state.salvage_item_preview("salvage_probe_rewrite").operation
		and state.salvage_item_preview("salvage_probe_refine").operation == state.salvage_item_preview("salvage_probe_refine").operation,
		"salvage: repeated previews are not deterministic", failures)

	# A real campaign drop must follow the same chain end to end.
	var drop_state := ApplicationState.new()
	drop_state.start_new_profile()
	drop_state.complete_tutorial()
	_complete_drop_gate_node(drop_state, "mainline_01_first_hunt", 301)
	_complete_drop_gate_node(drop_state, "mainline_02_priority_under_pressure", 302)
	var elite := _complete_drop_gate_node(drop_state, "mainline_03_first_elite", 303)
	var drops: Array = elite.result.rewards.equipment_drops
	var campaign_drops: Array = drops.filter(func(item: Variant) -> bool:
		return item is Dictionary and String((item as Dictionary).get("source", {}).get("type", "")) == "campaign_drop"
	)
	_expect(drops.size() == 2 and campaign_drops.size() == 1, "salvage: room drop and stable reward were not separated", failures)
	if not campaign_drops.is_empty():
		var drop: Dictionary = campaign_drops[0]
		var identity := "%s|%d" % [String(drop.instance_id), int(drop.law_seed)]
		var expected_operation: String = ["inscribe", "rewrite", "refine"][int(("0x" + identity.sha256_text().substr(0, 8)).hex_to_int()) % 3]
		var drop_preview: Dictionary = drop_state.salvage_item_preview(String(drop.instance_id))
		_expect(bool(drop_preview.get("ok", false)) and String(drop_preview.operation) == String(expected_operation)
			and String(drop.source.type) == "campaign_drop",
			"salvage: real campaign drop track mapping is wrong", failures)


func _test_salvage_commit_and_atomics(failures: Array[String]) -> void:
	var state := ApplicationState.new()
	state.start_new_profile()
	_inject_salvage_probe(state, _salvage_probe_item("salvage_probe_add", 18))
	_inject_salvage_probe(state, _salvage_probe_item("salvage_probe_rewrite", 5))
	_inject_salvage_probe(state, _salvage_probe_item("salvage_probe_refine", 3))
	state.prepare_contract({"contract_id": "salvage-probe", "mode": "Manual", "seed": 1, "room_count": 1})
	_expect(bool(state.begin_session().get("ok", false)), "salvage: session setup failed", failures)
	var before := state.profile
	var before_session := state.active_session
	var before_result := state.last_result
	var before_inventory_size := (before.inventory.equipment as Array).size()
	var before_tallies: Dictionary = (before.resources.law_tallies as Dictionary).duplicate(true)

	var preview: Dictionary = state.salvage_item_preview("salvage_probe_add")
	var committed: Dictionary = state.salvage_item("salvage_probe_add")
	_expect(bool(committed.get("ok", false))
		and String(committed.instance_id) == "salvage_probe_add"
		and String(committed.operation) == "inscribe"
		and int(committed.amount) == 1,
		"salvage: valid add-track commit failed", failures)
	_expect(preview.item == committed.salvaged_item and String(preview.operation) == String(committed.operation)
		and int(preview.amount) == int(committed.amount),
		"salvage: preview and commit diverged", failures)
	var after := state.profile
	_expect((after.inventory.equipment as Array).size() == before_inventory_size - 1
		and not _has_equipment_instance(after.inventory.equipment, "salvage_probe_add")
		and _has_equipment_instance(after.inventory.equipment, "salvage_probe_rewrite")
		and _has_equipment_instance(after.inventory.equipment, "salvage_probe_refine"),
		"salvage: commit did not remove exactly the targeted instance", failures)
	_expect(int(after.resources.law_tallies.inscribe) == int(before_tallies.inscribe) + 1
		and int(after.resources.law_tallies.rewrite) == int(before_tallies.rewrite)
		and int(after.resources.law_tallies.refine) == int(before_tallies.refine),
		"salvage: inscribe tally refund is wrong", failures)
	_expect(after.active_build == before.active_build
		and after.training == before.training
		and after.progression == before.progression
		and state.active_session == before_session
		and state.last_result == before_result,
		"salvage: commit touched build, training, progression, cursors, session, or result", failures)
	var tampered: Dictionary = committed.salvaged_item
	tampered["instance_id"] = "tampered"
	_expect(not _has_equipment_instance(state.profile.inventory.equipment, "salvage_probe_add")
		and _code(state.salvage_item("salvage_probe_add")) == "item_not_owned"
		and not _has_equipment_instance(state.profile.inventory.equipment, "tampered"),
		"salvage: returned item aliased state or repeat salvage was not rejected", failures)
	for probe_id in ["salvage_probe_rewrite", "salvage_probe_refine"]:
		var expected_operation: String = "rewrite" if probe_id == "salvage_probe_rewrite" else "refine"
		var tallies_before: Dictionary = (state.profile.resources.law_tallies as Dictionary).duplicate(true)
		var done: Dictionary = state.salvage_item(probe_id)
		_expect(bool(done.get("ok", false)) and String(done.operation) == expected_operation and int(done.amount) == 1,
			"salvage: %s track commit failed" % probe_id, failures)
		_expect(int(state.profile.resources.law_tallies[expected_operation]) == int(tallies_before[expected_operation]) + 1,
			"salvage: %s tally refund is wrong" % probe_id, failures)


func _test_salvage_persistence_roundtrip(failures: Array[String]) -> void:
	var state := ApplicationState.new()
	state.start_new_profile()
	_inject_salvage_probe(state, _salvage_probe_item("salvage_probe_add", 18))
	var committed: Dictionary = state.salvage_item("salvage_probe_add")
	_expect(bool(committed.get("ok", false)), "salvage: persistence setup commit failed", failures)
	var payload: Dictionary = state.persistent_payload("base")
	_expect(payload.schema_version == ApplicationState.PROFILE_SCHEMA_VERSION and int(payload.profile.schema_version) == ApplicationState.PROFILE_SCHEMA_VERSION,
		"salvage: salvage changed the persisted schema version", failures)
	var restored := ApplicationState.new()
	_expect(bool(restored.restore_persistent_payload(payload).get("ok", false))
		and restored.profile == state.profile,
		"salvage: post-salvage payload did not restore round-trip", failures)
	_expect(not _has_equipment_instance(restored.profile.inventory.equipment, "salvage_probe_add")
		and int(restored.profile.resources.law_tallies.inscribe) == 1,
		"salvage: restored refund state is wrong", failures)


func _salvage_probe_item(instance_id: String, law_seed: int, source_type: String = "campaign_drop") -> Dictionary:
	var registry := EarlyItemRegistryScript.new()
	if not registry.load_all().is_empty():
		return {}
	var template: Dictionary = (registry.item_instances.get("fixed_start_main_hand", {}) as Dictionary).duplicate(true)
	if template.is_empty():
		return {}
	template["instance_id"] = instance_id
	template["source"] = {"type": source_type, "id": "salvage_probe"}
	template["law_seed"] = law_seed
	return template


func _inject_salvage_probe(state: ApplicationState, item: Dictionary) -> void:
	(state._profile.inventory.equipment as Array).append(item.duplicate(true))
