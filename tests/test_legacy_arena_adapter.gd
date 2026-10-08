extends SceneTree

const LegacyArenaAdapterScript := preload("res://src/game/legacy_arena_adapter.gd")
const EarlyItemRegistryScript := preload("res://src/content/early_item_registry.gd")
const BuildResolverScript := preload("res://src/systems/build_resolver.gd")
const ContentRegistryScript := preload("res://src/content/content_registry.gd")
const ProxyBuildScript := preload("res://src/systems/proxy_build.gd")
const RangerAnimationScript := preload("res://src/presentation/ranger_animation.gd")


class FakeSaveStore:
	extends RefCounted

	var save_calls := 0

	func save(_payload: Variant) -> Dictionary:
		save_calls += 1
		return {"ok": true, "generation": save_calls, "slot": "test"}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var completed_results: Array[Dictionary] = []
	var convergent_build := _resolved_fixture("calibration_convergent")
	var white_proxy_build := _resolved_proxy_fixture()
	var source_room := {
		"room_id": "room.deep-copy",
		"layout_id": "corridor",
		"objective_id": "clear",
		"hazard_ids": ["moving_fireline"],
		"enemy_ids": ["melee_pursuer"],
		"elite_rule_ids": [],
		"boss_id": "",
		"drop_tags": ["equipment_general", "inscribe_tally", "rewrite_tally", "refine_tally"],
	}
	var adapter = LegacyArenaAdapterScript.new()
	adapter.completed.connect(func(result: Dictionary) -> void: completed_results.append(result.duplicate(true)))
	root.add_child(adapter)
	var session_config := {
		"contract_id": "embedded.test",
		"mode": "Auto",
		"preset_id": "convergent",
		"seed": 7,
		"room_index": 1,
		"room_count": 2,
		"room": source_room,
		"framework_context": {
			"contract_wins": 7,
			"active_build": {"preset_id": "convergent"},
			"resolved_build": convergent_build,
			"resolved_proxy_build": white_proxy_build,
		},
	}
	var started: Dictionary = adapter.start_session(session_config)
	_expect(bool(started.get("ok", false)), "adapter: embedded arena failed to start", failures)
	_expect(bool(adapter.current_config.get("presentation_enabled", false)), "adapter: missing presentation flag was not normalized to true", failures)
	var legacy: Variant = adapter.get("_legacy")
	_expect(legacy is Node, "adapter: legacy arena instance is unavailable", failures)
	if legacy is Node:
		var legacy_node := legacy as Node
		_expect(bool(legacy_node.get("presentation_enabled")), "adapter: normalized presentation flag was not injected before ready", failures)
		var injected_room: Dictionary = legacy_node.get("framework_room")
		_expect(int(injected_room.get("room_index", -1)) == 1 and int(injected_room.get("room_count", 0)) == 2,
			"adapter: existing zero-based room index and total were not passed to the arena", failures)
		legacy_node.call("_update_hud")
		var heading := (legacy_node.get("hud_panel") as Node).find_child("EncounterHeading", true, false) as Label
		_expect(heading != null and heading.text.contains("第 2 / 2 房") and heading.text.contains("清除"),
			"adapter: second-room metadata did not reach the persistent HUD objective", failures)
		source_room.enemy_ids[0] = "fan_ranged"
		source_room.drop_tags.append("damage")
		_expect(injected_room.enemy_ids == ["melee_pursuer"] and injected_room.drop_tags == ["equipment_general", "inscribe_tally", "rewrite_tally", "refine_tally"], "adapter: caller mutation leaked into injected RoomPlan", failures)
		injected_room.enemy_ids[0] = "charging_raider"
		_expect((adapter.current_config.room as Dictionary).enemy_ids == ["melee_pursuer"], "adapter: legacy mutation leaked back into stored config", failures)
		session_config["presentation_enabled"] = false
		_expect(bool(adapter.current_config.get("presentation_enabled", false)), "adapter: caller presentation mutation leaked into stored config", failures)
		_expect(bool(legacy_node.get("presentation_enabled")), "adapter: caller presentation mutation leaked into the arena", failures)
		var config_snapshot: Dictionary = adapter.current_config
		config_snapshot["presentation_enabled"] = false
		_expect(bool(adapter.current_config.get("presentation_enabled", false)), "adapter: current_config presentation copy is not deeply isolated", failures)
		_expect(bool(legacy_node.get("test_session")), "adapter: legacy persistence guard was not enabled", failures)
		_expect(bool(legacy_node.get("embedded_session")), "adapter: legacy embedded-session guard was not enabled", failures)
		_expect(int(legacy_node.get("contract_wins")) == 0, "adapter: framework win count polluted the legacy profile", failures)
		_expect(String((legacy_node.get("framework_active_build") as Dictionary).get("preset_id", "")) == "convergent", "adapter: active Build was not injected", failures)
		_expect((legacy_node.get("framework_resolved_build") as Dictionary) == convergent_build, "adapter: frozen resolved Build was not injected", failures)
		var runtime: Variant = legacy_node.get("proxy_runtime")
		_expect(runtime is Object and String(((runtime as Object).get("cores") as Dictionary)[&"perception"].core_id) == "near_enemy_horizon", "adapter: resolved proxy Build was not installed", failures)
		var fake_store := FakeSaveStore.new()
		legacy_node.set("save_store", fake_store)
		legacy_node.set("last_drop_id", "legacy.sentinel")
		legacy_node.set("last_drop", "Legacy Sentinel")
		var legacy_before: Dictionary = legacy_node.call("_legacy_reward_state")
		legacy_node.call("_grant_victory_reward")
		_expect(legacy_node.call("_legacy_reward_state") == legacy_before and fake_store.save_calls == 0, "adapter: embedded reward path polluted or saved legacy state", failures)
		(legacy_node.get("enemies") as Array).clear()
		legacy_node.call("_check_battle_end")
		var snapshot: Dictionary = legacy_node.get("room_reward_snapshot")
		snapshot["drop_id"] = "must.not.leak"
		snapshot["drop_label"] = "Must Not Leak"
		adapter.call("_process", 0.0)
		snapshot["add_dice_delta"] = 99
	_expect(completed_results.size() == 1, "adapter: completed result was not emitted exactly once", failures)
	if completed_results.size() == 1:
		var rewards_value: Variant = completed_results[0].get("rewards", {})
		var rewards: Dictionary = rewards_value if rewards_value is Dictionary else {}
		var tallies: Dictionary = rewards.get("law_tallies_delta", {}) if rewards.get("law_tallies_delta", {}) is Dictionary else {}
		_expect(int(tallies.get("inscribe", 0)) == 1 and int(tallies.get("rewrite", 0)) == 1 and int(tallies.get("refine", 0)) == 1
			and not rewards.has("add_dice_delta") and not rewards.has("rewrite_dice_delta") and not rewards.has("refine_dice_delta"),
			"adapter: canonical three-track Law Tally reward changed or leaked legacy fields", failures)
		_expect(not rewards.has("drop_id") and not rewards.has("drop_label") and int(rewards.get("contract_wins_delta", 0)) == 0, "adapter: embedded result leaked legacy drop/win rewards", failures)
		_expect(not bool(rewards.get("bonus_lost", true)), "adapter: normal room incorrectly lost timed bonus", failures)
		_expect(String(completed_results[0].get("build_fingerprint", "")) == String(convergent_build.build_fingerprint), "adapter: result lost the frozen Build fingerprint", failures)
		_expect(String(completed_results[0].get("room_id", "")) == "room.deep-copy" and String(completed_results[0].get("layout", "")) == "corridor", "adapter: result lost room/layout identity", failures)
		_expect(String(completed_results[0].get("objective", "")) == "clear" and completed_results[0].get("drop_tags", []) == ["equipment_general", "inscribe_tally", "rewrite_tally", "refine_tally"], "adapter: result lost objective/drop tags", failures)
	root.remove_child(adapter)
	adapter.free()

	var defeat_adapter = LegacyArenaAdapterScript.new()
	var defeat_results: Array[Dictionary] = []
	defeat_adapter.completed.connect(func(result: Dictionary) -> void: defeat_results.append(result.duplicate(true)))
	root.add_child(defeat_adapter)
	var defeat_started: Dictionary = defeat_adapter.start_session({
		"contract_id": "embedded.defeat-reason",
		"mode": "Manual",
		"seed": 21,
		"presentation_enabled": false,
		"room": {
			"room_id": "room.defeat-reason",
			"layout_id": "rectangle_arena",
			"objective_id": "clear",
			"hazard_ids": [],
			"enemy_ids": ["melee_pursuer"],
			"elite_rule_ids": [],
			"boss_id": "",
			"drop_tags": [],
		},
		"framework_context": {"resolved_build": convergent_build},
	})
	_expect(bool(defeat_started.get("ok", false)), "adapter defeat: arena failed to start", failures)
	var defeat_legacy_value: Variant = defeat_adapter.get("_legacy")
	if defeat_legacy_value is Node:
		var defeat_legacy := defeat_legacy_value as Node
		defeat_legacy.set("player_health", 1.0)
		defeat_legacy.set("last_damage_source_id", "enemy/melee_pursuer")
		defeat_legacy.set("last_damage_tick", 44)
		defeat_legacy.set("battle_over", true)
		defeat_legacy.set("battle_victory", false)
		defeat_adapter.call("_process", 0.0)
	if defeat_results.size() == 1:
		_expect(String(defeat_results[0].get("failure_reason", "")) == "enemy/melee_pursuer"
			and int(defeat_results[0].get("death_tick", -1)) == 44,
			"adapter defeat: authoritative death source was not exported", failures)
	else:
		_expect(false, "adapter defeat: result was not emitted", failures)
	root.remove_child(defeat_adapter)
	defeat_adapter.free()

	# presentation: an identical Auto contract in both visual modes must stay
	# semantically identical across a fixed number of authoritative ticks, while
	# the headless twin must never load assets, present the HUD, or redraw.
	root.size = Vector2i(1280, 720)
	const TWIN_TICKS := 300
	var twin_config := {
		"contract_id": "embedded.presentation-twins",
		"mode": "Auto",
		"preset_id": "convergent",
		"seed": 11,
		"room_count": 1,
		"room": {
			"room_id": "room.presentation-twins",
			"layout_id": "corridor",
			"objective_id": "clear",
			"hazard_ids": ["moving_fireline"],
			"enemy_ids": ["melee_pursuer", "charging_raider", "fan_ranged"],
			"elite_rule_ids": [],
			"boss_id": "threshold_colossus",
			"drop_tags": ["equipment_general"],
		},
		"framework_context": {
			"contract_wins": 0,
			"active_build": {"preset_id": "convergent"},
			"resolved_build": convergent_build,
			"resolved_proxy_build": white_proxy_build,
		},
	}
	var presented_config: Dictionary = twin_config.duplicate(true)
	presented_config["presentation_enabled"] = true
	var headless_config: Dictionary = twin_config.duplicate(true)
	headless_config["presentation_enabled"] = false
	var presented_adapter = LegacyArenaAdapterScript.new()
	var headless_adapter = LegacyArenaAdapterScript.new()
	root.add_child(presented_adapter)
	root.add_child(headless_adapter)
	var presented_start: Dictionary = presented_adapter.start_session(presented_config)
	var headless_start: Dictionary = headless_adapter.start_session(headless_config)
	_expect(bool(presented_start.get("ok", false)), "presentation twins: presented arena failed to start", failures)
	_expect(bool(headless_start.get("ok", false)), "presentation twins: headless arena failed to start", failures)
	var presented_legacy: Variant = presented_adapter.get("_legacy")
	var headless_legacy: Variant = headless_adapter.get("_legacy")
	_expect(presented_legacy is Node and headless_legacy is Node, "presentation twins: legacy arena instance is unavailable", failures)
	if presented_legacy is Node and headless_legacy is Node:
		var presented_node := presented_legacy as Node
		var headless_node := headless_legacy as Node
		_expect(bool(presented_node.get("presentation_enabled")), "presentation twins: enabled flag did not reach the arena", failures)
		_expect(not bool(headless_node.get("presentation_enabled")), "presentation twins: disabled flag did not reach the arena", failures)
		_expect(bool(headless_node.get("in_arena")), "presentation twins: headless arena did not enter the arena", failures)
		_expect(presented_node.get("actors_atlas") != null, "presentation twins: enabled arena did not load visual assets", failures)
		_expect(headless_node.get("actors_atlas") == null, "presentation twins: headless arena still loaded visual assets", failures)
		_expect(bool((presented_node.get("hud_panel") as Control).visible), "presentation twins: enabled arena HUD was not shown", failures)
		_expect(not bool((headless_node.get("hud_panel") as Control).visible), "presentation twins: headless HUD panel stayed visible", failures)
		_test_ranger_action_wiring(presented_node, failures)
		_expect(not bool((headless_node.get("base_panel") as Control).visible), "presentation twins: headless base panel stayed visible", failures)
		_expect(not bool((headless_node.get("systems_panel") as Control).visible), "presentation twins: headless systems panel stayed visible", failures)
		_expect(headless_node.get("return_button") is Button, "presentation twins: headless arena kept no return button node", failures)
		_expect(not bool((headless_node.get("return_button") as Button).visible), "presentation twins: headless return button stayed visible", failures)
		for _index in TWIN_TICKS:
			presented_node.call("_process", 1.0 / 30.0)
			headless_node.call("_process", 1.0 / 30.0)
		_expect(int(presented_node.get("sim_tick")) == TWIN_TICKS, "presentation twins: presented arena did not consume %d fixed ticks" % TWIN_TICKS, failures)
		var presented_state: Dictionary = _semantic_snapshot(presented_node)
		var headless_state: Dictionary = _semantic_snapshot(headless_node)
		_expect(presented_state == headless_state, "presentation twins: semantic state diverged after %d fixed ticks" % TWIN_TICKS, failures)
		_expect((headless_node.get("traces") as Array).is_empty(), "presentation twins: disabled arena accumulated visual traces", failures)
	root.remove_child(presented_adapter)
	presented_adapter.free()
	root.remove_child(headless_adapter)
	headless_adapter.free()

	var invalid_presentation_int_adapter = LegacyArenaAdapterScript.new()
	root.add_child(invalid_presentation_int_adapter)
	var invalid_presentation_int: Dictionary = invalid_presentation_int_adapter.start_session({
		"contract_id": "embedded.invalid-presentation-int",
		"mode": "Manual",
		"seed": 12,
		"room_count": 1,
		"presentation_enabled": 1,
		"framework_context": {"resolved_build": convergent_build},
	})
	_expect(String(invalid_presentation_int.get("error", "")) == "invalid_presentation_enabled", "adapter: non-bool presentation flag (int) was not rejected", failures)
	_expect(invalid_presentation_int_adapter.get_child_count() == 0, "adapter: rejected presentation config left a residual child", failures)
	_expect(invalid_presentation_int_adapter.get("_legacy") == null, "adapter: rejected presentation config left a residual arena", failures)
	_expect(not bool(invalid_presentation_int_adapter.call("_session_is_active")), "adapter: rejected presentation config left an active session", failures)
	_expect(String(invalid_presentation_int_adapter.start_session({"mode": "Manual"}).get("error", "")) == "already_started", "adapter: rejected presentation config was not an atomic one-shot", failures)
	root.remove_child(invalid_presentation_int_adapter)
	invalid_presentation_int_adapter.free()

	var invalid_presentation_string_adapter = LegacyArenaAdapterScript.new()
	root.add_child(invalid_presentation_string_adapter)
	var invalid_presentation_string: Dictionary = invalid_presentation_string_adapter.start_session({
		"mode": "Manual",
		"presentation_enabled": "false",
		"framework_context": {"resolved_build": convergent_build},
	})
	_expect(String(invalid_presentation_string.get("error", "")) == "invalid_presentation_enabled", "adapter: non-bool presentation flag (string) was not rejected", failures)
	_expect(invalid_presentation_string_adapter.get_child_count() == 0, "adapter: rejected string presentation config left a residual child", failures)
	root.remove_child(invalid_presentation_string_adapter)
	invalid_presentation_string_adapter.free()

	var missing_proxy_adapter = LegacyArenaAdapterScript.new()
	root.add_child(missing_proxy_adapter)
	var missing_proxy: Dictionary = missing_proxy_adapter.start_session({
		"contract_id": "embedded.missing-proxy",
		"mode": "Auto",
		"preset_id": "convergent",
		"seed": 8,
		"room_count": 1,
		"framework_context": {
			"contract_wins": 0,
			"active_build": {"preset_id": "convergent"},
			"resolved_build": convergent_build,
			"resolved_proxy_build": {},
		},
	})
	_expect(String(missing_proxy.get("error", "")) == "invalid_resolved_proxy_build", "adapter: Auto silently installed hardcoded proxy cores", failures)
	root.remove_child(missing_proxy_adapter)
	missing_proxy_adapter.free()

	var missing_build_adapter = LegacyArenaAdapterScript.new()
	root.add_child(missing_build_adapter)
	var missing_build: Dictionary = missing_build_adapter.start_session({
		"contract_id": "embedded.missing-build",
		"mode": "Manual",
		"seed": 9,
		"room_count": 1,
		"framework_context": {"contract_wins": 0, "active_build": {}, "proxy_build": {}},
	})
	_expect(String(missing_build.get("error", "")) == "invalid_resolved_build", "adapter: embedded arena accepted a missing resolved Build", failures)
	root.remove_child(missing_build_adapter)
	missing_build_adapter.free()

	var invalid_room_adapter = LegacyArenaAdapterScript.new()
	root.add_child(invalid_room_adapter)
	var invalid_room: Dictionary = invalid_room_adapter.start_session({"mode": "Manual", "room": "not-a-dictionary", "framework_context": {"resolved_build": convergent_build}})
	_expect(String(invalid_room.get("error", "")) == "invalid_room", "adapter: non-Dictionary room was accepted", failures)
	root.remove_child(invalid_room_adapter)
	invalid_room_adapter.free()

	var unknown_enemy_adapter = LegacyArenaAdapterScript.new()
	root.add_child(unknown_enemy_adapter)
	var unknown_enemy: Dictionary = unknown_enemy_adapter.start_session({
		"mode": "Manual",
		"room": {"room_id": "bad.enemy", "layout_id": "rectangle_arena", "objective_id": "clear", "hazard_ids": [], "enemy_ids": ["not_registered"], "elite_rule_ids": [], "boss_id": "", "drop_tags": []},
		"framework_context": {"resolved_build": convergent_build},
	})
	_expect(String(unknown_enemy.get("error", "")) == "arena_start_failed", "adapter: unknown enemy did not fail arena startup", failures)
	root.remove_child(unknown_enemy_adapter)
	unknown_enemy_adapter.free()

	if failures.is_empty():
		print("PASS  test_legacy_arena_adapter.gd")
		quit(0)
		return
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _test_ranger_action_wiring(arena: Node, failures: Array[String]) -> void:
	## The arena draws the shared action frame from authoritative tick fields, and
	## the defeat clip ages on a float presentation clock: 144 tiny steps have to
	## add up to the same ticks as one big step instead of rounding away to zero.
	_expect(bool(arena.get("in_arena")), "ranger wiring: the arena never entered the arena", failures)
	_expect(String(arena.get("ranger_action_pending_reason")) == "", "ranger wiring: the published action atlas reads as pending: %s" % String(arena.get("ranger_action_pending_reason")), failures)
	var report: Dictionary = arena.call("ranger_animation_report")

	_expect(report.has("state") and report.has("frame"), "ranger wiring: the arena exposed no runtime diagnostic", failures)
	var frame: Dictionary = report.get("frame", {})
	_expect(not frame.is_empty(), "ranger wiring: the arena resolved no hero frame", failures)
	_expect(frame.get("fallback", true) == false, "ranger wiring: the arena hero frame is a fallback", failures)
	_expect((frame.get("rect", Rect2i()) as Rect2i).size == RangerAnimationScript.CELL, "ranger wiring: the arena hero frame is %s" % str(frame.get("rect", Rect2i())), failures)
	_expect((frame.get("anchor", Vector2i.ZERO) as Vector2i) == RangerAnimationScript.DEFAULT_ANCHOR, "ranger wiring: the arena hero anchor is %s" % str(frame.get("anchor", Vector2i.ZERO)), failures)
	_expect(report.get("death_clip_visible", true) == false, "ranger wiring: a living arena claimed a visible defeat clip", failures)
	## The arena is shared with the twin comparison that follows, so the health this
	## check drives is restored before it leaves.
	var previous_health: float = float(arena.get("player_health"))
	arena.set("player_health", 0.0)
	for _index in range(144):
		arena.call("_update_ranger_action_events", 1.0 / 144.0)
	var high_rate: int = int((arena.call("_ranger_animation_state") as Dictionary).get("death_ticks", -1))
	_expect(high_rate == 30, "ranger wiring: 144 steps of 1/144s aged the defeat clip to %d ticks instead of 30" % high_rate, failures)
	arena.set("player_health", 100.0)
	arena.call("_update_ranger_action_events", 0.5)
	_expect(int((arena.call("_ranger_animation_state") as Dictionary).get("death_ticks", -1)) == 0, "ranger wiring: the defeat clock did not reset while healthy", failures)
	arena.set("player_health", 0.0)
	arena.call("_update_ranger_action_events", 1.0)
	_expect(int((arena.call("_ranger_animation_state") as Dictionary).get("death_ticks", -1)) == 30, "ranger wiring: one whole second did not age the defeat clip to 30 ticks", failures)
	arena.set("player_health", previous_health)
	arena.call("_update_ranger_action_events", 0.0)
	_expect(int((arena.call("_ranger_animation_state") as Dictionary).get("death_ticks", -1)) == 0, "ranger wiring: the defeat clock stayed armed after the check", failures)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _semantic_snapshot(arena: Node) -> Dictionary:
	var enemies_state: Array[Dictionary] = []
	for enemy in (arena.get("enemies") as Array):
		enemies_state.append({
			"entity_id": int(enemy.entity_id),
			"kind_id": String(enemy.kind_id),
			"x": float(enemy.position.x),
			"y": float(enemy.position.y),
			"health": float(enemy.health),
			"action_state": String(enemy.action_state),
			"action_id": String(enemy.action_id),
			"phase_id": String(enemy.phase_id),
			"phase_state": String(enemy.phase_state),
		})
	var hazards_state: Array[Dictionary] = []
	for state in (arena.get("hazard_states") as Array):
		hazards_state.append((state as Dictionary).duplicate(true))
	return {
		"sim_tick": int(arena.get("sim_tick")),
		"elapsed": float(arena.get("elapsed")),
		"shots": int(arena.get("shots")),
		"defeated": int(arena.get("defeated")),
		"battle_over": bool(arena.get("battle_over")),
		"battle_victory": bool(arena.get("battle_victory")),
		"player_health": float(arena.get("player_health")),
		"player_x": float((arena.get("player_position") as Vector2).x),
		"player_y": float((arena.get("player_position") as Vector2).y),
		"command_sequence": int(arena.get("command_sequence")),
		"next_entity_id": int(arena.get("next_entity_id")),
		"marked_entity_id": int(arena.get("marked_entity_id")),
		"attack_cooldown_ticks": int(arena.get("attack_cooldown_ticks")),
		"boss_damage": String((arena.get("boss_damage") as Object).call("to_short_string", 6)),
		"enemies": enemies_state,
		"hazards": hazards_state,
		"room_reward_snapshot": (arena.get("room_reward_snapshot") as Dictionary).duplicate(true),
		"elite_barrier_active": bool(arena.get("elite_barrier_active")),
		"timed_bonus_available": bool(arena.get("timed_bonus_available")),
	}


func _resolved_fixture(fixture_id: String) -> Dictionary:
	var registry = EarlyItemRegistryScript.new()
	if not registry.load_all().is_empty():
		return {}
	return BuildResolverScript.new(registry).resolve_fixture(fixture_id)


func _resolved_proxy_fixture() -> Dictionary:
	var registry = ContentRegistryScript.new()
	if not registry.load_all().is_empty():
		return {}
	var compiled: Dictionary = ProxyBuildScript.compile({
		"cores": ["near_enemy_horizon", "direct_gait", "single_key_execution", "short_trace_memory"],
	}, registry.cores)
	return (compiled.get("value", {}) as Dictionary).duplicate(true) if bool(compiled.get("ok", false)) else {}
