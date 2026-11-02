extends SceneTree
## Per-tick authoritative state golden. Runs fixed rooms headless (presentation
## off) in Auto and Manual mode and chains CombatStateSnapshotBuilder's state
## hash over every committed tick. The chains are pinned: they were identical
## before the room session redesign (bff166a) and after it, so any change to
## what the fixed tick computes, or to the hashed state, fails here even when
## the room outcome (the auto-smoke replay hash) stays the same.
##
## Update a pinned chain only for an intended gameplay or state-hash change,
## and say so in the commit.
##   godot --headless --path . --script res://tests/test_state_chain_golden.gd

const Builder := preload("res://src/game/combat_state_snapshot_builder.gd")
const Runtime := preload("res://src/game/combat_room_runtime.gd")
const Items := preload("res://src/content/early_item_registry.gd")
const Resolver := preload("res://src/systems/build_resolver.gd")
const Content := preload("res://src/content/content_registry.gd")
const ProxyBuild := preload("res://src/systems/proxy_build.gd")

const MAX_TICKS := 4000
const ROOMS := [
	{"room_id": "probe.mixed", "layout_id": "corridor", "objective_id": "clear", "hazard_ids": ["moving_fireline"], "enemy_ids": ["melee_pursuer", "fan_ranged", "charging_raider"], "elite_rule_ids": [], "boss_id": "", "drop_tags": ["equipment_general", "inscribe_tally"]},
	{"room_id": "probe.elite", "layout_id": "rectangle_arena", "objective_id": "hunt_elite", "hazard_ids": [], "enemy_ids": ["melee_pursuer"], "elite_rule_ids": ["periodic_barrier", "summon_reinforcements"], "boss_id": "", "drop_tags": []},
	{"room_id": "probe.boss", "layout_id": "rectangle_arena", "objective_id": "hunt_elite", "hazard_ids": ["moving_fireline"], "enemy_ids": [], "elite_rule_ids": [], "boss_id": "threshold_colossus", "drop_tags": ["proxy_core_fixed"]},
]
## room_id/mode -> [ticks, battle_over, battle_victory, chain]
const EXPECTED := {
	"probe.mixed/Auto": [44, true, true, "56d3c827149dbcd65b7a1b148cc8773aebeb49cbc3ff32157cd9ccf57e3aaa9f"],
	"probe.mixed/Manual": [263, true, false, "b47362cd67732293a3f2a70edf4aa125a0dd52354f46fba050e9e29156eb1c3e"],
	"probe.elite/Auto": [66, true, true, "eb8d3c79940c2ab367e4dd2a1903f96e0c953daf440e68e10f4a300f94eae9fc"],
	"probe.elite/Manual": [542, true, false, "110b41995e6da4d7bc54010956f84ce14674839af02900f5365e32ee573ef1ca"],
	"probe.boss/Auto": [931, true, false, "d535a5ddfb6865de87c4be2a27e6eb3f76bf0d2f49e80e924e1298128f7b4040"],
	"probe.boss/Manual": [4000, false, false, "bd861e73fa52d059741e6a18a7c805aa04f834e27c08d3bc10dac1d16dd9b0ae"],
}

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var items = Items.new()
	var item_errors: Array = items.load_all()
	var content = Content.new()
	var content_errors: Array = content.load_all()
	if not item_errors.is_empty() or not content_errors.is_empty():
		failures.append("content failed to load: %s %s" % [str(item_errors), str(content_errors)])
		_finish()
		return
	var compiled: Dictionary = ProxyBuild.compile({"cores": ["near_enemy_horizon", "direct_gait", "single_key_execution", "short_trace_memory"]}, content.cores)
	var proxy: Dictionary = compiled.get("value", {})
	var build: Dictionary = Resolver.new(items).resolve_fixture("calibration_convergent")
	if not bool(compiled.get("ok", false)) or not bool(build.get("ok", false)):
		failures.append("fixture builds failed to resolve")
		_finish()
		return
	for room: Dictionary in ROOMS:
		for mode: String in ["Auto", "Manual"]:
			_check_room(room, build, proxy, mode)
	_finish()


func _check_room(room: Dictionary, build: Dictionary, proxy: Dictionary, mode: String) -> void:
	var key := "%s/%s" % [room.room_id, mode]
	var runtime = Runtime.new()
	root.add_child(runtime)
	runtime.set_process(false)
	var started: Dictionary = runtime.start_session({
		"contract_id": "probe.contract", "mode": mode, "preset_id": String(build.get("growth_classification", "convergent")),
		"seed": 52969, "room_index": 0, "room_count": 1, "presentation_enabled": false, "room": room.duplicate(true),
		"framework_context": {"contract_wins": 3, "active_build": {"skills": ["piercing_arrow", "hunter_mark", "dash"]}, "resolved_build": build, "resolved_proxy_build": proxy},
	})
	if not bool(started.get("ok", false)):
		failures.append("%s: room failed to start: %s" % [key, str(started)])
		root.remove_child(runtime)
		runtime.free()
		return
	var arena = runtime.get("room_instance")
	arena.set_process(false)
	var chain := Builder.hash_runtime(arena, "probe")
	var ticks := 0
	while ticks < MAX_TICKS and not bool(arena.battle_over):
		arena.call("_simulate_tick")
		ticks += 1
		chain = (chain + Builder.hash_runtime(arena, "probe")).sha256_text()
	var actual := [ticks, bool(arena.battle_over), bool(arena.battle_victory), chain]
	if actual != EXPECTED[key]:
		failures.append("%s: state chain changed: expected %s, got %s" % [key, str(EXPECTED[key]), str(actual)])
	root.remove_child(runtime)
	runtime.free()


func _finish() -> void:
	for message in failures:
		printerr(message)
	print("STATE_CHAIN_GOLDEN ", "pass" if failures.is_empty() else "fail", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
