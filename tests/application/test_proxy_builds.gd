extends "res://tests/helpers/application_state_suite.gd"

## Proxy component inventory and equip/configure transactions.


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_proxy_component_transactions(failures)
	return failures


func _test_proxy_component_transactions(failures: Array[String]) -> void:
	var locked := ApplicationState.new()
	locked.start_new_profile()
	var locked_before := locked.profile
	_expect(_code(locked.equip_proxy_core("near_enemy_horizon")) == "proxy_locked" and locked.profile == locked_before,
		"proxy transaction: locked profile equip was not rejected atomically", failures)

	var state := _unlock_auto_certification()
	var initial_build: Dictionary = state.profile.proxy_build
	var expected_initial := ["near_enemy_horizon", "direct_gait", "single_key_execution", "short_trace_memory"]
	_expect(initial_build == {"cores": expected_initial, "settings": {}, "attachments": ["", "", ""]},
		"proxy transaction: initial four-core raw build is not schema 8 canonical shape", failures)
	var initial_inventory: Array = state.profile.inventory.proxy_components
	_expect(initial_inventory.size() == 4, "proxy transaction: initial inventory count is wrong", failures)
	for index in initial_inventory.size():
		var item: Dictionary = initial_inventory[index]
		_expect(item.keys() == ["id", "name", "slot", "rarity", "type", "protocol", "source_contract"]
			and String(item.id) == String(expected_initial[index])
			and not String(item.name).is_empty() and not String(item.protocol).is_empty()
			and String(item.rarity) == "white" and String(item.type) == "proxy_core"
			and String(item.source_contract) == "threshold_colossus",
			"proxy transaction: initial component metadata is incomplete or out of order", failures)

	var snapshot: Dictionary = state.early_game_snapshot()
	var catalog_ids: Array = (snapshot.proxy.catalog as Dictionary).keys()
	for core_id in catalog_ids:
		var entry: Dictionary = snapshot.proxy.catalog[core_id]
		_expect((entry as Dictionary).keys() == ["id", "name", "slot", "protocol", "settings_schema", "default_settings"]
			and String(entry.id) == String(core_id)
			and not String((entry as Dictionary).name).is_empty()
			and not String((entry as Dictionary).protocol).is_empty(),
			"proxy transaction: readable catalog metadata shape is wrong", failures)
	_expect(snapshot.proxy.keys() == ["build", "unlocked", "inventory", "catalog", "resolved_build"]
		and catalog_ids == ["near_enemy_horizon", "marking_prism", "direct_gait", "distance_keeping_gait", "single_key_execution", "short_trace_memory"]
		and snapshot.proxy.inventory.size() == 4
		and _is_fingerprint(String(snapshot.proxy.resolved_build.semantic_fingerprint)),
		"proxy transaction: early snapshot did not expose exactly the six implemented cores", failures)
	(snapshot.proxy.catalog.near_enemy_horizon as Dictionary)["name"] = "tampered"
	(snapshot.proxy.inventory[0] as Dictionary)["protocol"] = "tampered"
	(snapshot.proxy.build.cores as Array)[0] = "tampered"
	(snapshot.proxy.resolved_build.cores[0] as Dictionary)["core_id"] = "tampered"
	var isolated := state.early_game_snapshot()
	_expect(String(isolated.proxy.catalog.near_enemy_horizon.name) != "tampered"
		and String(isolated.proxy.inventory[0].protocol) != "tampered"
		and String(isolated.proxy.build.cores[0]) == "near_enemy_horizon"
		and String(isolated.proxy.resolved_build.cores[0].core_id) == "near_enemy_horizon",
		"proxy transaction: early snapshot aliases internal or derived state", failures)

	var before_unowned := state.profile
	_expect(_code(state.equip_proxy_core("marking_prism")) == "proxy_core_not_owned" and state.profile == before_unowned,
		"proxy transaction: unowned implemented core was not rejected atomically", failures)
	_expect(_code(state.equip_proxy_core("state_parser")) == "unsupported_proxy_core" and state.profile == before_unowned,
		"proxy transaction: catalog-only unimplemented core was accepted or mutated state", failures)

	var first_auto := _grant_session_result(state, "ordinary_auto_one", "Auto", "victory")
	var second_auto := _grant_session_result(state, "ordinary_auto_two", "Auto", "victory")
	_expect(int(state.profile.progression.auto_contract_wins) == 2
		and first_auto.result.proxy_component_drops.size() == 1
		and String(first_auto.result.proxy_component_drops[0].id) == "marking_prism"
		and second_auto.result.proxy_component_drops.size() == 1
		and String(second_auto.result.proxy_component_drops[0].id) == "distance_keeping_gait"
		and state.profile.proxy_build == initial_build
		and state.profile.inventory.proxy_components.size() == 6,
		"proxy rewards: first two successful Auto wins did not grant ordered inventory-only cores", failures)
	var manual := _grant_session_result(state, "manual_after_unlock", "Manual", "victory")
	var defeat := _grant_session_result(state, "auto_defeat_after_unlock", "Auto", "defeat")
	var third_auto := _grant_session_result(state, "ordinary_auto_three", "Auto", "victory")
	_expect(int(state.profile.progression.auto_contract_wins) == 3
		and manual.result.proxy_component_drops.is_empty()
		and defeat.result.proxy_component_drops.is_empty()
		and third_auto.result.proxy_component_drops.is_empty()
		and state.profile.inventory.proxy_components.size() == 6,
		"proxy rewards: Manual, defeat, or third Auto emitted a component drop", failures)

	var marking := state.equip_proxy_core("marking_prism")
	_expect(bool(marking.get("ok", false)) and String(state.profile.proxy_build.cores[0]) == "marking_prism"
		and String(marking.resolved_proxy_build.cores[0].core_id) == "marking_prism",
		"proxy transaction: marking core did not replace only its slot", failures)
	var distance := state.equip_proxy_core("distance_keeping_gait")
	var default_fingerprint := String(distance.resolved_proxy_build.semantic_fingerprint)
	_expect(bool(distance.get("ok", false)) and String(state.profile.proxy_build.cores[1]) == "distance_keeping_gait"
		and (state.profile.proxy_build.settings as Dictionary).is_empty()
		and String(distance.resolved_proxy_build.cores[1].settings.distance_band) == "mid",
		"proxy transaction: distance core did not compile with default mid", failures)
	var near := state.configure_proxy_core("distance_keeping_gait", {"distance_band": "near"})
	var far := state.configure_proxy_core("distance_keeping_gait", {"distance_band": "far"})
	_expect(bool(near.get("ok", false)) and bool(far.get("ok", false))
		and String(near.resolved_proxy_build.semantic_fingerprint) != String(far.resolved_proxy_build.semantic_fingerprint)
		and String(near.resolved_proxy_build.semantic_fingerprint) != default_fingerprint,
		"proxy transaction: near/far settings did not produce distinct resolved fingerprints", failures)
	var direct := state.equip_proxy_core("direct_gait")
	_expect(bool(direct.get("ok", false)) and not state.profile.proxy_build.settings.has("distance_keeping_gait"),
		"proxy transaction: replacing distance with direct retained stale settings", failures)
	var distance_again := state.equip_proxy_core("distance_keeping_gait")
	_expect(bool(distance_again.get("ok", false))
		and not state.profile.proxy_build.settings.has("distance_keeping_gait")
		and String(distance_again.resolved_proxy_build.cores[1].settings.distance_band) == "mid",
		"proxy transaction: re-equipping distance reused removed configuration", failures)

	var before_invalid := state.profile
	_expect(_code(state.configure_proxy_core("distance_keeping_gait", {"distance_band": "meters"})).begins_with("proxy_build_")
		and state.profile == before_invalid,
		"proxy transaction: illegal settings were not rejected atomically", failures)
	state.equip_proxy_core("near_enemy_horizon")
	var before_uninstalled := state.profile
	_expect(_code(state.configure_proxy_core("marking_prism", {})) == "proxy_core_not_equipped"
		and state.profile == before_uninstalled,
		"proxy transaction: uninstalled core configuration was not rejected atomically", failures)

	var returned := state.equip_proxy_core("marking_prism")
	(returned.proxy_build.cores as Array)[0] = "tampered"
	(returned.resolved_proxy_build.cores[0] as Dictionary)["core_id"] = "tampered"
	_expect(String(state.profile.proxy_build.cores[0]) == "marking_prism"
		and String(state.resolved_proxy_build_snapshot().resolved_proxy_build.cores[0].core_id) == "marking_prism",
		"proxy transaction: API return aliases authoritative state", failures)

	var payload := state.persistent_payload("base")
	var missing_settings := payload.duplicate(true)
	missing_settings.profile.proxy_build.erase("settings")
	var extra_build_field := payload.duplicate(true)
	extra_build_field.profile.proxy_build["firmware"] = {}
	var mismatched_metadata := payload.duplicate(true)
	mismatched_metadata.profile.inventory.proxy_components[0].protocol = "tampered"
	var duplicate_component := payload.duplicate(true)
	duplicate_component.profile.inventory.proxy_components.append((duplicate_component.profile.inventory.proxy_components[0] as Dictionary).duplicate(true))
	var unowned_selected := payload.duplicate(true)
	unowned_selected.profile.inventory.proxy_components = []
	var unsupported_attachment := payload.duplicate(true)
	unsupported_attachment.profile.proxy_build.attachments[0] = "future_attachment"
	for invalid_payload in [missing_settings, extra_build_field, mismatched_metadata, duplicate_component, unowned_selected, unsupported_attachment]:
		var restored := ApplicationState.new()
		_expect(_code(restored.restore_persistent_payload(invalid_payload)) == "invalid_profile" and not restored.has_profile(),
			"proxy validation: malformed build or inventory metadata was accepted", failures)
