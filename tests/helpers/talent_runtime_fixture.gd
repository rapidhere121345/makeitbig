extends RefCounted

const EarlyItemRegistryScript := preload("res://src/content/early_item_registry.gd")
const BuildResolverScript := preload("res://src/systems/build_resolver.gd")
const LegacyArenaAdapterScript := preload("res://src/game/legacy_arena_adapter.gd")

const LAYER_ONE := [
	"ranger_steady_string",
	"ranger_long_breath",
	"ranger_keen_eye",
	"ranger_light_step",
	"ranger_recovery_pose",
]
const LAYER_TWO := [
	"ranger_close_turn",
	"ranger_continuation_calibration",
	"ranger_defocused_tracking",
]
const LOWER_EIGHT := LAYER_ONE + LAYER_TWO

var registry
var resolver


func _init() -> void:
	registry = EarlyItemRegistryScript.new()
	var errors: Array = registry.load_all()
	assert(errors.is_empty(), "talent fixture registry failed: %s" % str(errors))
	resolver = BuildResolverScript.new(registry)


func resolved_build(layer_three: Array = []) -> Dictionary:
	assert(layer_three.size() <= 2, "this regression explicitly allows at most two layer-3 nodes")
	return resolver.resolve(
		{
			"p": 0.50,
			"T": 2.0,
			"v": 200.0,
			"d": 320.0,
			"turn": 0.10,
			"damage": 100.0,
			"critical_chance": 0.0,
			"max_health": 1000.0,
		},
		{
			"gloves": _item("talent-critical-gloves", "turnfeather_gloves", "gloves", [], "breeding_split"),
			"ring_1": _item("talent-critical-ring", "hawk_eye_ring", "ring_1", [], "", "pack_hunt_mark"),
		},
		"piercing_arrow",
		{
			"talents": {"allocated_ids": LOWER_EIGHT + layer_three, "stance": "mid"},
			"talent_points": 30,
			"unlocked_classes": ["ranger"],
		}
	)


func _item(instance_id: String, base_id: String, slot: String, affixes: Array, rune_id: String = "", law_id: String = "") -> Dictionary:
	return {
		"instance_id": instance_id,
		"base_item_id": base_id,
		"slot": slot,
		"affixes": affixes,
		"rune_id": rune_id,
		"law_id": law_id,
		"source": {"type": "test_fixture", "id": "talent-runtime"},
		"law_seed": 52969,
	}


func start_session(layer_three: Array = [], presentation_enabled: bool = false):
	var build := resolved_build(layer_three)
	assert(bool(build.get("ok", false)), "BuildResolver rejected talent fixture: %s" % str(build.get("errors", [])))
	var adapter = LegacyArenaAdapterScript.new()
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(adapter)
	var started: Dictionary = adapter.start_session({
		"contract_id": "test.talent-runtime",
		"mode": "Manual",
		"preset_id": String(build.growth_classification),
		"seed": 52969,
		"presentation_enabled": presentation_enabled,
		"room": {
			"room_id": "room.talent-runtime",
			"layout_id": "rectangle_arena",
			"objective_id": "clear",
			"hazard_ids": [],
			"enemy_ids": ["melee_pursuer", "fan_ranged"],
			"elite_rule_ids": [],
			"boss_id": "",
			"drop_tags": [],
		},
		"framework_context": {
			"active_build": {"skills": ["piercing_arrow", "hunter_mark", "dash"]},
			"resolved_build": build,
		},
	})
	assert(bool(started.get("ok", false)), "adapter failed: %s" % str(started))
	return {"adapter": adapter, "arena": adapter.get("_legacy"), "build": build}


func free_session(session: Dictionary) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if session.has("adapter") and is_instance_valid(session.adapter):
		tree.root.remove_child(session.adapter)
		session.adapter.free()


func configure_target(arena, offset: Vector2 = Vector2(120.0, 0.0)):
	arena.player_position = arena._arena_rect().get_center()
	arena.player_facing = Vector2.RIGHT
	arena.player_last_displacement = Vector2.ZERO
	arena.sim_tick = 10
	arena.attack_cooldown_ticks = 0
	arena.hunter_mark_cooldown_ticks = 0
	arena.dash_cooldown_ticks = 0
	arena.dodge_cooldown_ticks = 0
	arena.dodge_remaining_ticks = 0
	arena.dash_remaining_ticks = 0
	arena.player_action_timeline.reset()
	arena.combat_event_stream.reset()
	arena.projectiles.clear()
	arena.attack_origins.clear()
	arena.last_attack_outcome.clear()
	arena.boss_damage = arena.BossMaximumMarker if false else arena.boss_damage.from_float(0.0)
	var target = arena.enemies[0]
	target.position = arena.player_position + offset
	target.health = 1000000000.0
	target.maximum_health = target.health
	return target


func release_arrow(arena, target, aim: Vector2 = Vector2.ZERO) -> bool:
	arena._process_player_action_events(arena.player_action_timeline.advance(arena.sim_tick))
	var receipt: Dictionary = arena._request_piercing_arrow(target.entity_id, aim)
	arena._process_player_action_events(arena.player_action_timeline.advance(arena.sim_tick))
	if not bool(receipt.get("accepted", false)):
		return false
	var snapshot: Dictionary = arena.player_action_timeline.snapshot()
	var active: Dictionary = snapshot.get("active", {})
	if active.is_empty():
		return false
	arena.sim_tick = int(active.get("start_tick", arena.sim_tick)) + int(active.get("windup_ticks", 5))
	arena._process_player_action_events(arena.player_action_timeline.advance(arena.sim_tick))
	return not arena.projectiles.is_empty()


func advance_projectiles(arena, maximum_ticks: int = 160) -> void:
	var advanced := 0
	while not arena.projectiles.is_empty() and advanced < maximum_ticks:
		arena.sim_tick += 1
		arena._advance_piercing_projectiles_tick()
		advanced += 1
