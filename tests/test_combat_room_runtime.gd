extends SceneTree

const CombatRoomRuntimeScript := preload("res://src/game/combat_room_runtime.gd")
const EarlyItemRegistryScript := preload("res://src/content/early_item_registry.gd")
const BuildResolverScript := preload("res://src/systems/build_resolver.gd")
const ContentRegistryScript := preload("res://src/content/content_registry.gd")
const ProxyBuildScript := preload("res://src/systems/proxy_build.gd")
const RangerAnimationScript := preload("res://src/presentation/ranger_animation.gd")
const ContractPlanScript := preload("res://src/game/contract_plan.gd")
const SimTickContextScript := preload("res://src/runtime/simulation/sim_tick_context.gd")
const DeathSettlementNotificationScript := preload("res://src/runtime/combat/death_settlement_notification.gd")


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
	var runtime = CombatRoomRuntimeScript.new()
	runtime.completed.connect(func(result: Dictionary) -> void: completed_results.append(result.duplicate(true)))
	root.add_child(runtime)
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
	var started: Dictionary = runtime.start_session(session_config)
	_expect(bool(started.get("ok", false)), "runtime: embedded arena failed to start", failures)
	_expect(bool(runtime.current_config.get("presentation_enabled", false)), "runtime: missing presentation flag was not normalized to true", failures)
	var room_value: Variant = runtime.get("room_instance")
	_expect(room_value is Node, "runtime: mounted room instance is unavailable", failures)
	var duplicate_start := runtime.start_session({})
	_expect(duplicate_start.get("error", "") == "already_started" and runtime.is_processing(), "runtime: a duplicate start stopped the active terminal observer", failures)
	if room_value is Node:
		var room_node := room_value as Node
		var scene_runtime_value: Variant = runtime.get("scene_runtime")
		_expect(scene_runtime_value is Node and scene_runtime_value.call("is_ready"), "runtime: production session did not mount SceneRuntime", failures)
		if scene_runtime_value is Node:
			var scene_runtime := scene_runtime_value as Node
			_expect(scene_runtime.get("mounted_scene") == room_node, "runtime: SceneRuntime did not own the mounted native room scene", failures)
			var world_asset: Dictionary = scene_runtime.call("report").get("world_asset", {})
			_expect(String(world_asset.get("world_scene_path", "")) == "res://content/rooms/combat/corridor.tscn", "runtime: catalog did not select the corridor native room asset", failures)
			_expect(room_node.get("scene_runtime") == scene_runtime, "runtime: native room did not receive its owning SceneRuntime", failures)
			_expect(room_node.get("actor_registry") == scene_runtime.get("actor_registry"), "runtime: combat created a second ActorRegistry", failures)
			_expect(room_node.get("simulation_world") == scene_runtime.get("simulation"), "runtime: combat created a second SimulationWorld", failures)
			_expect(room_node.get_parent() != null and String(room_node.get_parent().name) == "NativeWorld", "runtime: native room was mounted outside the presenter world layer", failures)
		_expect(bool(room_node.get("presentation_enabled")), "runtime: normalized presentation flag was not injected before ready", failures)
		var injected_room: Dictionary = room_node.get("framework_room")
		_expect(int(injected_room.get("room_index", -1)) == 1 and int(injected_room.get("room_count", 0)) == 2,
			"runtime: existing zero-based room index and total were not passed to the arena", failures)
		room_node.call("refresh_presentation")
		var heading := (room_node.get("presentation").get("hud") as Node).find_child("EncounterHeading", true, false) as Label
		_expect(heading != null and heading.text.contains("Room 2/2") and heading.text.contains("Clear foes")
			and heading.tooltip_text.contains("Room 2 / 2") and heading.tooltip_text.contains("Clear"),
			"runtime: second-room metadata did not reach the persistent HUD objective", failures)
		source_room.enemy_ids[0] = "fan_ranged"
		source_room.drop_tags.append("damage")
		_expect(injected_room.enemy_ids == ["melee_pursuer"] and injected_room.drop_tags == ["equipment_general", "inscribe_tally", "rewrite_tally", "refine_tally"], "runtime: caller mutation leaked into injected RoomPlan", failures)
		injected_room.enemy_ids[0] = "charging_raider"
		_expect((runtime.current_config.room as Dictionary).enemy_ids == ["melee_pursuer"], "runtime: room mutation leaked back into stored config", failures)
		session_config["presentation_enabled"] = false
		_expect(bool(runtime.current_config.get("presentation_enabled", false)), "runtime: caller presentation mutation leaked into stored config", failures)
		_expect(bool(room_node.get("presentation_enabled")), "runtime: caller presentation mutation leaked into the arena", failures)
		var config_snapshot: Dictionary = runtime.current_config
		config_snapshot["presentation_enabled"] = false
		_expect(bool(runtime.current_config.get("presentation_enabled", false)), "runtime: current_config presentation copy is not deeply isolated", failures)
		_expect(bool(room_node.get("test_session")), "runtime: embedded persistence guard was not enabled", failures)
		_expect(bool(room_node.get("embedded_session")), "runtime: embedded-session guard was not enabled", failures)
		_expect(int(room_node.get("contract_wins")) == 0, "runtime: framework win count polluted the embedded profile", failures)
		_expect(String((room_node.get("framework_active_build") as Dictionary).get("preset_id", "")) == "convergent", "runtime: active Build was not injected", failures)
		_expect((room_node.get("framework_resolved_build") as Dictionary) == convergent_build, "runtime: frozen resolved Build was not injected", failures)
		var proxy_runtime_instance: Variant = room_node.get("proxy_runtime")
		_expect(proxy_runtime_instance is Object and String(((proxy_runtime_instance as Object).get("cores") as Dictionary)[&"perception"].core_id) == "near_enemy_horizon", "runtime: resolved proxy Build was not installed", failures)
		var fake_store := FakeSaveStore.new()
		room_node.set("save_store", fake_store)
		room_node.set("last_drop_id", "legacy.sentinel")
		room_node.set("last_drop", "Legacy Sentinel")
		var embedded_state_before: Dictionary = room_node.call("_embedded_authority_state_snapshot")
		var typed_clear := _settle_first_encounter_member(room_node)
		_expect(bool(typed_clear.get("ok", false)), "runtime: typed encounter member settlement was rejected", failures)
		room_node.call("_check_battle_end")
		room_node.call("_check_battle_end")
		_expect(room_node.call("_embedded_authority_state_snapshot") == embedded_state_before and fake_store.save_calls == 0, "runtime: repeated terminal checks polluted embedded persistence", failures)
		var snapshot: Dictionary = room_node.get("room_reward_snapshot")
		snapshot["drop_id"] = "must.not.leak"
		snapshot["drop_label"] = "Must Not Leak"
		runtime.call("_process", 0.0)
		room_node.emit_signal("return_requested")
		runtime.request_abandon()
		runtime.call("_process", 0.0)
		snapshot["add_dice_delta"] = 99
	_expect(completed_results.size() == 1, "runtime: completed result was not emitted exactly once", failures)
	if completed_results.size() == 1:
		var rewards_value: Variant = completed_results[0].get("rewards", {})
		var rewards: Dictionary = rewards_value if rewards_value is Dictionary else {}
		var tallies: Dictionary = rewards.get("law_tallies_delta", {}) if rewards.get("law_tallies_delta", {}) is Dictionary else {}
		_expect(int(tallies.get("inscribe", 0)) == 1 and int(tallies.get("rewrite", 0)) == 1 and int(tallies.get("refine", 0)) == 1
			and not rewards.has("add_dice_delta") and not rewards.has("rewrite_dice_delta") and not rewards.has("refine_dice_delta"),
			"runtime: canonical three-track Law Tally reward changed or leaked legacy fields", failures)
		_expect(not rewards.has("drop_id") and not rewards.has("drop_label") and int(rewards.get("contract_wins_delta", 0)) == 0, "runtime: embedded result leaked legacy drop/win rewards", failures)
		_expect(not bool(rewards.get("bonus_lost", true)), "runtime: normal room incorrectly lost timed bonus", failures)
		_expect(String(completed_results[0].get("build_fingerprint", "")) == String(convergent_build.build_fingerprint), "runtime: result lost the frozen Build fingerprint", failures)
		_expect(String(completed_results[0].get("room_id", "")) == "room.deep-copy" and String(completed_results[0].get("layout", "")) == "corridor", "runtime: result lost room/layout identity", failures)
		_expect(String(completed_results[0].get("objective", "")) == "clear" and completed_results[0].get("drop_tags", []) == ["equipment_general", "inscribe_tally", "rewrite_tally", "refine_tally"], "runtime: result lost objective/drop tags", failures)
	root.remove_child(runtime)
	runtime.free()

	var defeat_runtime = CombatRoomRuntimeScript.new()
	var defeat_results: Array[Dictionary] = []
	defeat_runtime.completed.connect(func(result: Dictionary) -> void: defeat_results.append(result.duplicate(true)))
	root.add_child(defeat_runtime)
	var defeat_started: Dictionary = defeat_runtime.start_session({
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
	_expect(bool(defeat_started.get("ok", false)), "runtime defeat: arena failed to start", failures)
	var defeat_room_value: Variant = defeat_runtime.get("room_instance")
	if defeat_room_value is Node:
		var defeat_room := defeat_room_value as Node
		while int(defeat_room.get("sim_tick")) < 44:
			defeat_room.call("_simulate_tick")
		var state = defeat_room.get("player_combat_state")
		var rules = defeat_room.get("player_combat_rules")
		var player: Dictionary = state.snapshot(44)
		var damage: Dictionary = rules.apply_damage(44, float(player.player_health) + 1.0, "enemy/melee_pursuer", (defeat_room.get("enemies") as Array)[0].position)
		_expect(bool(damage.get("accepted", false)), "runtime defeat: real lethal damage was rejected", failures)
		defeat_room.call("_check_battle_end")
		defeat_runtime.call("_process", 0.0)
		defeat_runtime.call("_process", 0.0)
		defeat_room.emit_signal("return_requested")
		defeat_runtime.request_abandon()
	if defeat_results.size() == 1:
		_expect(String(defeat_results[0].get("failure_reason", "")) == "enemy/melee_pursuer"
			and int(defeat_results[0].get("death_tick", -1)) == 44,
			"runtime defeat: authoritative death source was not exported", failures)
	else:
		_expect(false, "runtime defeat: result was not emitted", failures)
	root.remove_child(defeat_runtime)
	defeat_runtime.free()

	# presentation: an identical Auto contract in both visual modes must stay
	# semantically identical across a fixed number of authoritative ticks, while
	# the headless twin must never load world assets or draw the HUD.
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
	var presented_runtime = CombatRoomRuntimeScript.new()
	var headless_runtime = CombatRoomRuntimeScript.new()
	root.add_child(presented_runtime)
	root.add_child(headless_runtime)
	var presented_start: Dictionary = presented_runtime.start_session(presented_config)
	var headless_start: Dictionary = headless_runtime.start_session(headless_config)
	_expect(bool(presented_start.get("ok", false)), "presentation twins: presented arena failed to start", failures)
	_expect(bool(headless_start.get("ok", false)), "presentation twins: headless arena failed to start", failures)
	var presented_room_value: Variant = presented_runtime.get("room_instance")
	var headless_room_value: Variant = headless_runtime.get("room_instance")
	_expect(presented_room_value is Node and headless_room_value is Node, "presentation twins: mounted room instance is unavailable", failures)
	if presented_room_value is Node and headless_room_value is Node:
		var presented_node := presented_room_value as Node
		var headless_node := headless_room_value as Node
		_expect(bool(presented_node.get("presentation_enabled")), "presentation twins: enabled flag did not reach the arena", failures)
		_expect(not bool(headless_node.get("presentation_enabled")), "presentation twins: disabled flag did not reach the arena", failures)
		_expect(bool(headless_node.get("in_arena")), "presentation twins: headless arena did not enter the arena", failures)
		_expect(presented_node.get("presentation").get("world_view") != null, "presentation twins: enabled arena did not load the native world asset", failures)
		_expect(headless_node.get("presentation").get("world_view") == null, "presentation twins: headless arena still loaded native world assets", failures)
		_expect(bool((presented_node.get("presentation").get("hud") as Control).visible), "presentation twins: enabled arena HUD was not shown", failures)
		_expect(bool((headless_node.get("presentation").get("hud") as Control).visible) and is_zero_approx((headless_node.get("presentation").get("hud") as Control).modulate.a), "presentation twins: off HUD changed input participation or remained drawn", failures)
		_test_ranger_action_wiring(presented_node, failures)
		_expect(not bool((headless_node.get("lab_view").get("base_panel") as Control).visible), "presentation twins: headless base panel stayed visible", failures)
		_expect(not bool((headless_node.get("lab_view").get("systems_panel") as Control).visible), "presentation twins: headless systems panel stayed visible", failures)
		_expect(headless_node.has_signal("return_requested"), "presentation twins: room return signal is unavailable", failures)
		_expect((headless_node.get("presentation").get("hud") as Control).has_signal("return_requested"), "presentation twins: HUD return signal is unavailable", failures)
		for _index in TWIN_TICKS:
			presented_node.call("_process", 1.0 / 30.0)
			headless_node.call("_process", 1.0 / 30.0)
		_expect(int(presented_node.get("sim_tick")) == TWIN_TICKS, "presentation twins: presented arena did not consume %d fixed ticks" % TWIN_TICKS, failures)
		var presented_scene: Variant = presented_runtime.get("scene_runtime")
		var presented_port: Variant = presented_scene.get("presentation_port") if presented_scene != null else null
		var projection_errors: Array = presented_port.get("last_projection_errors") if presented_port != null else ["presentation_port_unavailable"]
		_expect(projection_errors.is_empty() and presented_port != null and presented_port.get("latest_frame") != null, "presentation twins: presented room rejected its kernel snapshots at the actor-movement seam: %s" % str(projection_errors.slice(0, 3)), failures)
		var presented_state: Dictionary = _semantic_snapshot(presented_node)
		var headless_state: Dictionary = _semantic_snapshot(headless_node)
		_expect(presented_state == headless_state, "presentation twins: semantic state diverged after %d fixed ticks" % TWIN_TICKS, failures)
		_expect((headless_node.get("presentation").get("feedback").get("traces") as Array).is_empty(), "presentation twins: disabled arena accumulated visual traces", failures)
	root.remove_child(presented_runtime)
	presented_runtime.free()
	root.remove_child(headless_runtime)
	headless_runtime.free()

	var invalid_presentation_int_runtime = CombatRoomRuntimeScript.new()
	root.add_child(invalid_presentation_int_runtime)
	var invalid_presentation_int: Dictionary = invalid_presentation_int_runtime.start_session({
		"contract_id": "embedded.invalid-presentation-int",
		"mode": "Manual",
		"seed": 12,
		"room_count": 1,
		"presentation_enabled": 1,
		"framework_context": {"resolved_build": convergent_build},
	})
	_expect(String(invalid_presentation_int.get("error", "")) == "invalid_presentation_enabled", "runtime: non-bool presentation flag (int) was not rejected", failures)
	_expect(invalid_presentation_int_runtime.get_child_count() == 0, "runtime: rejected presentation config left a residual child", failures)
	_expect(invalid_presentation_int_runtime.get("room_instance") == null, "runtime: rejected presentation config left a residual arena", failures)
	_expect(not bool(invalid_presentation_int_runtime.call("_session_is_active")), "runtime: rejected presentation config left an active session", failures)
	_expect(String(invalid_presentation_int_runtime.start_session({"mode": "Manual"}).get("error", "")) == "already_started", "runtime: rejected presentation config was not an atomic one-shot", failures)
	root.remove_child(invalid_presentation_int_runtime)
	invalid_presentation_int_runtime.free()

	var invalid_presentation_string_runtime = CombatRoomRuntimeScript.new()
	root.add_child(invalid_presentation_string_runtime)
	var invalid_presentation_string: Dictionary = invalid_presentation_string_runtime.start_session({
		"mode": "Manual",
		"presentation_enabled": "false",
		"framework_context": {"resolved_build": convergent_build},
	})
	_expect(String(invalid_presentation_string.get("error", "")) == "invalid_presentation_enabled", "runtime: non-bool presentation flag (string) was not rejected", failures)
	_expect(invalid_presentation_string_runtime.get_child_count() == 0, "runtime: rejected string presentation config left a residual child", failures)
	root.remove_child(invalid_presentation_string_runtime)
	invalid_presentation_string_runtime.free()

	var missing_proxy_runtime = CombatRoomRuntimeScript.new()
	root.add_child(missing_proxy_runtime)
	var missing_proxy: Dictionary = missing_proxy_runtime.start_session({
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
	_expect(String(missing_proxy.get("error", "")) == "invalid_resolved_proxy_build", "runtime: Auto silently installed hardcoded proxy cores", failures)
	root.remove_child(missing_proxy_runtime)
	missing_proxy_runtime.free()

	var missing_build_runtime = CombatRoomRuntimeScript.new()
	root.add_child(missing_build_runtime)
	var missing_build: Dictionary = missing_build_runtime.start_session({
		"contract_id": "embedded.missing-build",
		"mode": "Manual",
		"seed": 9,
		"room_count": 1,
		"framework_context": {"contract_wins": 0, "active_build": {}, "proxy_build": {}},
	})
	_expect(String(missing_build.get("error", "")) == "invalid_resolved_build", "runtime: embedded arena accepted a missing resolved Build", failures)
	root.remove_child(missing_build_runtime)
	missing_build_runtime.free()

	var invalid_room_runtime = CombatRoomRuntimeScript.new()
	root.add_child(invalid_room_runtime)
	var invalid_room: Dictionary = invalid_room_runtime.start_session({"mode": "Manual", "room": "not-a-dictionary", "framework_context": {"resolved_build": convergent_build}})
	_expect(String(invalid_room.get("error", "")) == "invalid_room", "runtime: non-Dictionary room was accepted", failures)
	root.remove_child(invalid_room_runtime)
	invalid_room_runtime.free()

	var unknown_enemy_runtime = CombatRoomRuntimeScript.new()
	root.add_child(unknown_enemy_runtime)
	var unknown_enemy: Dictionary = unknown_enemy_runtime.start_session({
		"mode": "Manual",
		"room": {"room_id": "bad.enemy", "layout_id": "rectangle_arena", "objective_id": "clear", "hazard_ids": [], "enemy_ids": ["not_registered"], "elite_rule_ids": [], "boss_id": "", "drop_tags": []},
		"framework_context": {"resolved_build": convergent_build},
	})
	_expect(String(unknown_enemy.get("error", "")) == "room_runtime_start_failed", "runtime: unknown enemy did not fail arena startup", failures)
	root.remove_child(unknown_enemy_runtime)
	unknown_enemy_runtime.free()
	_test_authored_campaign_rooms(convergent_build, failures)

	if failures.is_empty():
		print("PASS  test_combat_room_runtime.gd")
		quit(0)
		return
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _test_authored_campaign_rooms(resolved_build: Dictionary, failures: Array[String]) -> void:
	var loaded_layouts: Dictionary = {}
	for contract_id: String in ["mainline_01_first_hunt", "mainline_02_priority_under_pressure"]:
		var planned := ContractPlanScript.build({"contract_id": contract_id, "seed": 4242, "mode": "Manual"})
		_expect(bool(planned.get("ok", false)), "native campaign: authored contract did not compile", failures)
		if not bool(planned.get("ok", false)):
			continue
		var plan: Dictionary = planned["plan"]
		for index in (plan["rooms"] as Array).size():
			var room: Dictionary = plan["rooms"][index]
			var runtime := CombatRoomRuntimeScript.new()
			var abandons: Array[Dictionary] = []
			runtime.abandoned.connect(func(result: Dictionary) -> void: abandons.append(result.duplicate(true)))
			root.add_child(runtime)
			var started := runtime.start_session({
				"contract_id": contract_id, "seed": 4242, "mode": "Manual", "presentation_enabled": false,
				"room_index": index, "room_count": plan["room_count"], "room": room,
				"framework_context": {"resolved_build": resolved_build},
			})
			_expect(bool(started.get("ok", false)), "native campaign: %s failed to mount: %s" % [room["room_id"], str(started)], failures)
			if bool(started.get("ok", false)):
				var arena: Node = runtime.room_instance
				arena.set_process(false)
				loaded_layouts[room["layout_id"]] = true
				for _tick in 30:
					arena.call("_process", 1.0 / 30.0)
				_expect(int(arena.get("sim_tick")) == 30 and runtime.scene_runtime.simulation.tick == 30, "native campaign: room and shared simulation ticks diverged", failures)
				var registry = runtime.scene_runtime.actor_registry
				for actor_id: String in registry.actor_ids():
					var actor = registry.actor(actor_id)
					_expect(registry.is_position_clear(actor.feet_position, runtime.scene_runtime.authored_arena_rect, actor.footprint_radius), "native campaign: %s left authored geometry in %s" % [actor_id, room["room_id"]], failures)
				if room["layout_id"] == "ring":
					var boundary: Dictionary = runtime.scene_runtime.movement_boundary
					_expect(String(boundary.get("type", "")) == "ring" and not registry.is_position_clear(boundary["center"], runtime.scene_runtime.authored_arena_rect, 14.0), "native campaign: ring manifest lost its physical hole", failures)
				arena.set_process(true)
				arena.emit_signal("return_requested")
				arena.emit_signal("return_requested")
				runtime.request_abandon()
				_expect(abandons.size() == 1 and abandons[0].get("outcome", "") == "abandoned" and not arena.is_processing(), "native campaign: return did not finalize/stop the room once", failures)
			root.remove_child(runtime)
			runtime.free()
	_expect(loaded_layouts.size() == 3, "native campaign: the real contracts did not exercise all three authored scenes", failures)


func _test_ranger_action_wiring(arena: Node, failures: Array[String]) -> void:
	## The arena draws the shared action frame from authoritative tick fields, and
	## the defeat clip ages on a float presentation clock: 144 tiny steps have to
	## add up to the same ticks as one big step instead of rounding away to zero.
	_expect(bool(arena.get("in_arena")), "ranger wiring: the arena never entered the arena", failures)
	_expect(String(arena.get("presentation").get("animations").get("ranger_action_pending_reason")) == "", "ranger wiring: the published action atlas reads as pending: %s" % String(arena.get("presentation").get("animations").get("ranger_action_pending_reason")), failures)
	var report: Dictionary = arena.call("ranger_animation_report")

	_expect(report.has("state") and report.has("frame"), "ranger wiring: the arena exposed no runtime diagnostic", failures)
	var frame: Dictionary = report.get("frame", {})
	_expect(not frame.is_empty(), "ranger wiring: the arena resolved no hero frame", failures)
	_expect(frame.get("fallback", true) == false, "ranger wiring: the arena hero frame is a fallback", failures)
	_expect((frame.get("rect", Rect2i()) as Rect2i).size == RangerAnimationScript.CELL, "ranger wiring: the arena hero frame is %s" % str(frame.get("rect", Rect2i())), failures)
	_expect((frame.get("anchor", Vector2i.ZERO) as Vector2i) == RangerAnimationScript.DEFAULT_ANCHOR, "ranger wiring: the arena hero anchor is %s" % str(frame.get("anchor", Vector2i.ZERO)), failures)
	_expect(report.get("death_clip_visible", true) == false, "ranger wiring: a living arena claimed a visible defeat clip", failures)
	## Real damage arms the presentation clock; a new room resets player and
	## presentation authority before the twin comparison resumes.
	_lethal_damage(arena, failures)
	for _index in range(144):
		arena.get("presentation").get("animations").call("advance_time", arena.call("gameplay_snapshot"), 1.0 / 144.0)
	var high_rate: int = int((arena.get("presentation").get("animations").call("ranger_state", arena.call("gameplay_snapshot")) as Dictionary).get("death_ticks", -1))
	_expect(high_rate == 30, "ranger wiring: 144 steps of 1/144s aged the defeat clip to %d ticks instead of 30" % high_rate, failures)
	arena.call("start_room")
	arena.get("presentation").get("animations").call("advance_time", arena.call("gameplay_snapshot"), 0.5)
	_expect(int((arena.get("presentation").get("animations").call("ranger_state", arena.call("gameplay_snapshot")) as Dictionary).get("death_ticks", -1)) == 0, "ranger wiring: new-room health did not reset the defeat clock", failures)
	_lethal_damage(arena, failures)
	arena.get("presentation").get("animations").call("advance_time", arena.call("gameplay_snapshot"), 1.0)
	_expect(int((arena.get("presentation").get("animations").call("ranger_state", arena.call("gameplay_snapshot")) as Dictionary).get("death_ticks", -1)) == 30, "ranger wiring: one whole second did not age the defeat clip to 30 ticks", failures)
	arena.call("start_room")
	arena.get("presentation").get("animations").call("advance_time", arena.call("gameplay_snapshot"), 0.0)
	_expect(int((arena.get("presentation").get("animations").call("ranger_state", arena.call("gameplay_snapshot")) as Dictionary).get("death_ticks", -1)) == 0, "ranger wiring: the defeat clock stayed armed after restart", failures)


func _lethal_damage(arena: Node, failures: Array[String]) -> void:
	var tick := int(arena.get("sim_tick"))
	var player: Dictionary = arena.get("player_combat_state").snapshot(tick)
	var applied: Dictionary = arena.get("player_combat_rules").apply_damage(tick, float(player.player_health) + 1.0, "fixture/defeat", player.player_position)
	_expect(bool(applied.get("accepted", false)), "ranger wiring: real lethal damage was rejected", failures)


func _settle_first_encounter_member(arena: Node) -> Dictionary:
	# Exercise the mounted RoomEncounter authority through its typed death
	# notification.  The old test cleared Main.enemies directly, which bypassed
	# the encounter member state and could no longer prove terminal semantics.
	arena.call("_simulate_tick")
	var port: Variant = arena.get("room_encounter_port")
	if port == null:
		return {"ok": false, "error": "encounter_port_unavailable"}
	var snapshot: Dictionary = port.snapshot()
	var notifications: Array = snapshot.get("spawned_notifications", [])
	if notifications.is_empty() or not notifications[0] is Dictionary:
		return {"ok": false, "error": "encounter_member_not_spawned"}
	var notification: Dictionary = notifications[0]
	var context := SimTickContextScript.new()
	context.tick = int(arena.get("sim_tick"))
	var scene_runtime: Variant = arena.get("scene_runtime")
	context.room_instance_id = String(scene_runtime.get("room_instance_id"))
	context.world_revision = int(scene_runtime.get("world_revision"))
	var typed_death := DeathSettlementNotificationScript.new()
	typed_death.entity_key = String(notification.get("entity_key", ""))
	typed_death.tick = context.tick
	typed_death.room_id = context.room_instance_id
	typed_death.world_revision = context.world_revision
	port.on_death_settlement(typed_death, context)
	var encounter_state: Dictionary = port.snapshot().get("encounter", {})
	var records: Array = encounter_state.get("spawn_records", [])
	if records.is_empty() or String((records[0] as Dictionary).get("state", "")) != "dead":
		return {"ok": false, "error": "encounter_member_not_dead"}
	return {"ok": true, "error": ""}
	arena.call("_check_battle_end")



func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _semantic_snapshot(arena: Node) -> Dictionary:
	var player: Dictionary = arena.get("player_combat_state").snapshot(int(arena.get("sim_tick")))
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
		"marked_entity_id": int(player["marked_entity_id"]),
		"attack_cooldown_ticks": int(player["attack_cooldown_ticks"]),
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
