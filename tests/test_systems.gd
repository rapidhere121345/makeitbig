extends RefCounted

const DestinyForge = preload("res://src/systems/destiny_forge.gd")
const ProxyRuntime = preload("res://src/systems/proxy_runtime.gd")
const ContentRegistry = preload("res://src/content/content_registry.gd")
const ProxyBuild = preload("res://src/systems/proxy_build.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_forge_determinism_and_cost(failures)
	_test_forge_tracks_and_bag(failures)
	_test_proxy_modes_prediction_and_failure(failures)
	_test_profile_proxy_installation(failures)
	_test_white_ranger(failures)
	return failures


func _test_forge_determinism_and_cost(failures: Array[String]) -> void:
	var families := [
		{"name": "power", "weight": 3},
		{"name": "speed", "weight": 1},
		{"name": "critical", "weight": 1},
	]
	var first := DestinyForge.new(424242, families)
	var second := DestinyForge.new(424242, families)
	first.set_dice(DestinyForge.TRACK_ADD, 8)
	second.set_dice(DestinyForge.TRACK_ADD, 8)
	_expect(first.preview("add", 0, 8) == second.preview("add", 0, 8), "forge: same seed must reproduce previews", failures)
	_expect(first.preview("add", 0, 8) == first.preview("add", 1, 8), "forge: add is one item-wide track, not a per-slot stream", failures)
	var selected: Dictionary = first.choose("add", 0, 3)
	_expect(bool(selected.get("ok", false)), "forge: legal add choice should commit", failures)
	_expect(int(selected.get("cost", 0)) == 3 and first.get_dice("add") == 5, "forge: choosing item n must consume n dice", failures)
	_expect(first.preview("add", 1, 99).size() == 5, "forge: preview must stop at the currently affordable horizon", failures)
	var restored := DestinyForge.new()
	_expect(restored.restore_state(first.state()) and restored.state() == first.state(), "forge: saved seed and track positions must restore exactly", failures)


func _test_forge_tracks_and_bag(failures: Array[String]) -> void:
	var families := [
		{"name": "common", "weight": 3},
		{"name": "rare", "weight": 1},
		{"name": "utility", "weight": 2},
	]
	var forge := DestinyForge.new(99, families)
	forge.set_affix(0, "common", 1)
	forge.set_dice("rewrite", 12)
	forge.set_dice("refine", 12)
	var rewrite_before := forge.preview("rewrite", 0, 6)
	var refined := forge.choose("refine", 0, 2)
	_expect(bool(refined.get("ok", false)) and int(forge.affixes[0].tier) > 1, "forge: refine must preserve family and strictly improve tier", failures)
	_expect(rewrite_before == forge.preview("rewrite", 0, 6), "forge: refine must not advance or perturb rewrite track", failures)
	var bag_preview := forge.preview("rewrite", 0, 3)
	var seen := {}
	for candidate in bag_preview:
		seen[candidate.family] = true
	_expect(seen.has("rare") and seen.has("utility"), "forge: one weighted bag cycle must cover every legal family", failures)


func _test_proxy_modes_prediction_and_failure(failures: Array[String]) -> void:
	var proxy := ProxyRuntime.new()
	var resolved := _resolved_white(failures)
	_expect(bool(proxy.install_resolved(resolved, "boss").ok), "proxy: resolved install should succeed", failures)
	_expect(bool(proxy.begin_contract("auto").ok), "proxy: auto contract should start", failures)
	_expect(not bool(proxy.begin_contract("manual").ok) and proxy.mode == "auto", "proxy: manual and auto modes must be mutually exclusive and locked", failures)
	var requirements := {
		"perception": {"target_count": 1},
		"movement": {"pathing": 1.0},
		"execution": {"skill_count": 1},
		"memory": {"rotation_steps": 1},
	}
	_expect(proxy.predict(requirements) == "stable", "proxy: sufficient known capabilities should predict stable", failures)
	var easy_requirements := {
		"perception": {"target_count": 0},
		"movement": {"pathing": 0.5},
		"execution": {"skill_count": 0},
		"memory": {"rotation_steps": 0},
	}
	_expect(proxy.predict(easy_requirements) == "stable", "proxy: comfortable known margins should predict stable", failures)
	requirements.memory.rotation_steps = 2
	_expect(proxy.predict(requirements) == "strained", "proxy: known capability shortfall should predict strained", failures)
	requirements.memory["unknown_capability"] = 1
	_expect(proxy.predict(requirements) == "unknown", "proxy: absent capability data should predict unknown", failures)
	var bad_context := {
		"visible_targets": ["boss"], "requested_target": "boss", "requested_skill": "piercing_arrow",
		"in_range": true, "path_blocked": false, "skill_ready": true, "rotation_steps": 2,
	}
	var failure_a: Dictionary = proxy.run_pipeline(bad_context)
	var failure_b: Dictionary = proxy.run_pipeline(bad_context)
	_expect(failure_a == failure_b and failure_a.failure.category == "rotation", "proxy: identical failures must produce deterministic categorized records", failures)


func _test_white_ranger(failures: Array[String]) -> void:
	var proxy := ProxyRuntime.new()
	proxy.install_resolved(_resolved_white(failures), "boss")
	proxy.begin_contract("auto")
	var result: Dictionary = proxy.simulate_minimal_ranger({"target_id": "boss", "target_health": 3.0, "skill_1_damage": 1.0})
	_expect(bool(result.get("ok", false)) and int(result.actions) == 3, "proxy: white proxy should complete the minimal one-target ranger scenario", failures)
	_expect(result.trace == ["perception", "memory_update", "tactics", "movement_and_cast", "confirmation", "logistics"], "proxy: runtime pipeline order must be fixed", failures)
	var wrong_skill: Dictionary = proxy.simulate_minimal_ranger({"target_id": "boss", "skill": "hunter_mark"})
	_expect(not bool(wrong_skill.get("ok", true)) and wrong_skill.failure.category == "rotation", "proxy: white proxy must stay locked to skill 1", failures)


func _test_profile_proxy_installation(failures: Array[String]) -> void:
	var proxy := ProxyRuntime.new()
	var resolved := _resolved_white(failures)
	var installed: Dictionary = proxy.install_resolved(resolved, "boss")
	_expect(bool(installed.get("ok", false)) and proxy.cores.size() == 4, "proxy profile: resolved cores were not installed", failures)
	_expect(String((proxy.cores[&"perception"] as Dictionary).core_id) == "near_enemy_horizon", "proxy profile: cores were not indexed by resolved slot", failures)
	var before := proxy.cores.duplicate(true)
	var stale := resolved.duplicate(true)
	stale.cores[0].capabilities.refresh_period_ticks = 31
	var rejected: Dictionary = proxy.install_resolved(stale, "other")
	_expect(String(rejected.get("error", "")) == "semantic_fingerprint_mismatch" and proxy.cores == before and proxy.locked_target == "boss", "proxy profile: invalid installs must fail atomically", failures)
	_expect(not proxy.install_resolved({"cores": []}, "other").ok and proxy.cores == before, "proxy profile: raw ids were accepted or changed installed cores", failures)


func _resolved_white(failures: Array[String]) -> Dictionary:
	var registry := ContentRegistry.new()
	var errors: Array[String] = registry.load_all()
	_expect(errors.is_empty(), "proxy: catalog failed to load: %s" % str(errors), failures)
	if not errors.is_empty():
		return {}
	var compiled := ProxyBuild.compile({"cores": ["near_enemy_horizon", "direct_gait", "single_key_execution", "short_trace_memory"]}, registry.cores)
	_expect(compiled.ok, "proxy: white resolved build failed to compile", failures)
	return compiled.value if compiled.ok else {}


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
