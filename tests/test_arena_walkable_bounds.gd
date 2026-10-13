extends SceneTree

## 2026-10-10 playtest fix: battle rooms are bounded by the map's walkable
## rectangle, never by a circular arena. These checks pin that law for ring
## rooms through the real Main instance: geometry, player walk/dodge, enemy
## locomotion, Boss slam targets, the published proxy snapshot, the replay
## hash mechanism, spawn placement and the room presentation copy.

const MainScript := preload("res://src/game/main.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Pin the viewport so presentation setup behaves like the other arena suites.
	root.size = Vector2i(1280, 720)
	var arena = MainScript.new()
	arena.embedded_session = true
	root.add_child(arena)
	await process_frame

	_test_ring_geometry_is_map_rectangle(arena)
	_test_map_center_and_edges(arena)
	_test_enemy_locomotion_respects_edges(arena)
	_test_boss_slam_target_respects_edges(arena)
	_test_public_proxy_geometry(arena)
	_test_replay_hash_mechanism(arena)
	_test_spawns_inside_map_rectangle(arena)
	_test_room_copy_and_concept_routing(arena)
	_test_other_layouts_unchanged(arena)

	root.remove_child(arena)
	arena.free()
	if failures.is_empty():
		print("PASS  test_arena_walkable_bounds.gd")
		quit(0)
		return
	for failure: String in failures:
		printerr("- %s" % failure)
	quit(1)


func _configure_room(arena: Node, layout: String, enemy_ids: Array, boss_id: String = "") -> void:
	arena.embedded_session = true
	arena.framework_room = {
		"room_id": "bounds.%s" % layout,
		"layout_id": layout,
		"layout": layout,
		"objective_id": "clear",
		"objective": "clear",
		"hazard_ids": [],
		"enemy_ids": enemy_ids.duplicate(),
		"elite_rule_ids": [],
		"boss_id": boss_id,
		"drop_tags": ["equipment_general"],
	}
	arena._spawn_wave()


func _test_ring_geometry_is_map_rectangle(arena: Node) -> void:
	_configure_room(arena, "ring", ["melee_pursuer"])
	_expect(String(arena.layout_id) == "ring", "ring: room identity was rewritten")
	_expect(String(arena._walkable_layout_id()) == "rectangle_arena", "ring: collision layout did not resolve to the map rectangle")
	var geometry: Dictionary = arena._walkable_geometry(14.0)
	var expected_bounds: Rect2 = (arena._arena_rect() as Rect2).grow(-14.0)
	_expect(String(geometry.get("kind", "")) == "rectangle", "ring: walkable geometry is not the map rectangle")
	_expect(Rect2(geometry.get("bounds", Rect2())) == expected_bounds, "ring: walkable bounds are not the padded map rectangle")
	_expect(is_zero_approx(float(geometry.get("inner_radius", -1.0))) and is_zero_approx(float(geometry.get("outer_radius", -1.0))), "ring: annulus radii leaked into the walkable geometry")


func _test_map_center_and_edges(arena: Node) -> void:
	_configure_room(arena, "ring", ["melee_pursuer"])
	var center: Vector2 = arena._arena_rect().get_center()
	var bounds: Rect2 = (arena._arena_rect() as Rect2).grow(-14.0)

	# The old annulus pushed the exact centre out to its inner radius.
	arena.player_position = center
	arena._advance_player_tick(Vector2.ZERO, 1.0)
	_expect(arena.player_position == center, "ring: standing still on the map centre was displaced by the retired circle")
	_expect(Vector2(arena._clamp_to_arena(center, 14.0)) == center, "ring: the map centre is not walkable")

	# Far outside points clamp onto the rectangle, not onto a ring band.
	_expect(Vector2(arena._clamp_to_arena(Vector2(9999.0, -9999.0), 14.0)) == Vector2(bounds.end.x, bounds.position.y), "ring: the top-right map corner is not the clamp target")
	_expect(Vector2(arena._clamp_to_arena(Vector2(-9999.0, 9999.0), 14.0)) == Vector2(bounds.position.x, bounds.end.y), "ring: the bottom-left map corner is not the clamp target")

	# Sustained walking stops exactly at the map edge and never leaves the map.
	arena.player_position = center
	var maximum_x := center.x
	for tick in 400:
		arena._advance_player_tick(Vector2.RIGHT, 1.0)
		maximum_x = maxf(maximum_x, float(arena.player_position.x))
	_expect(Vector2(arena.player_position) == Vector2(bounds.end.x, center.y), "ring: sustained walking did not stop exactly on the right map edge")
	_expect(maximum_x <= bounds.end.x + 0.000001, "ring: walking crossed the right map edge")

	# Dodge is clamped by the same rectangle.
	arena.player_position = Vector2(bounds.end.x - 8.0, center.y)
	arena.dodge_direction = Vector2.RIGHT
	arena.dodge_remaining_ticks = 6
	for tick in 6:
		arena._advance_player_tick(Vector2.ZERO, 1.0)
		if float(arena.player_position.x) > bounds.end.x + 0.000001:
			failures.append("ring: dodge crossed the right map edge at tick %d" % tick)
			break
	_expect(Vector2(arena.player_position) == Vector2(bounds.end.x, center.y), "ring: dodge did not stop exactly on the map edge")


func _test_enemy_locomotion_respects_edges(arena: Node) -> void:
	_configure_room(arena, "ring", ["melee_pursuer"])
	var center: Vector2 = arena._arena_rect().get_center()
	var enemy_bounds: Rect2 = (arena._arena_rect() as Rect2).grow(-16.0)
	var enemy = arena.enemies[0]
	enemy.position = center
	for tick in 700:
		arena._commit_normal_enemy_intent(enemy, {"move_direction": Vector2.RIGHT, "speed_scale": 1.0, "reason": "bounds_test"})
		if float(enemy.position.x) > enemy_bounds.end.x + 0.000001:
			failures.append("ring: enemy locomotion crossed the right map edge at tick %d" % tick)
			break
	_expect(Vector2(enemy.position) == Vector2(enemy_bounds.end.x, center.y), "ring: enemy locomotion did not stop exactly on the map edge")


func _test_boss_slam_target_respects_edges(arena: Node) -> void:
	_configure_room(arena, "ring", [], "threshold_colossus")
	var center: Vector2 = arena._arena_rect().get_center()
	var slam_bounds: Rect2 = (arena._arena_rect() as Rect2).grow(-28.0)
	var boss = arena.boss
	_expect(boss != null, "ring: boss fixture did not spawn")
	if boss == null:
		return

	arena.player_position = Vector2(9999.0, -9999.0)
	arena._start_boss_action(boss, "slam")
	var corner_shape: Dictionary = boss.target_shape
	_expect(String(corner_shape.get("type", "")) == "rect", "ring: boss slam did not freeze a rect target")
	_expect(Rect2(corner_shape.get("rect", Rect2())).get_center() == Vector2(slam_bounds.end.x, slam_bounds.position.y), "ring: boss slam target left the map rectangle")

	boss.action_state = "none"
	arena.player_position = center
	arena._start_boss_action(boss, "slam")
	var center_shape: Dictionary = boss.target_shape
	_expect(Rect2(center_shape.get("rect", Rect2())).get_center() == center, "ring: boss slam target on the map centre was displaced by the retired circle")


func _test_public_proxy_geometry(arena: Node) -> void:
	_configure_room(arena, "ring", ["melee_pursuer"])
	var snapshot: Dictionary = arena._public_proxy_snapshot()
	var geometry: Dictionary = snapshot.get("walkable_geometry", {})
	_expect(not geometry.is_empty() and String(geometry.get("kind", "")) == "rectangle", "ring: published proxy geometry is not the map rectangle")
	_expect(not geometry.has("layout_id"), "ring: published proxy geometry leaked the room layout id")
	var normalized: Dictionary = arena.WalkableGeometryScript.normalize(geometry)
	_expect(bool(normalized.get("ok", false)), "ring: published proxy geometry no longer normalizes")


func _test_replay_hash_mechanism(arena: Node) -> void:
	_configure_room(arena, "ring", ["melee_pursuer"])
	var first: String = arena._semantic_state_hash("test")
	var repeated: String = arena._semantic_state_hash("test")
	_expect(not first.is_empty() and first == repeated, "ring: replay hash lost determinism on identical state")
	arena.player_position += Vector2(37.0, -11.0)
	var moved: String = arena._semantic_state_hash("test")
	_expect(moved != first, "ring: replay hash stopped reacting to player position")


func _test_spawns_inside_map_rectangle(arena: Node) -> void:
	_configure_room(arena, "ring", ["melee_pursuer", "charging_raider", "fan_ranged", "melee_pursuer", "fan_ranged", "melee_pursuer"])
	var enemy_bounds: Rect2 = (arena._arena_rect() as Rect2).grow(-16.0)
	for enemy in arena.enemies:
		_expect(enemy_bounds.grow(0.001).has_point(enemy.position), "ring: spawn %s started outside the map rectangle" % [str(enemy.position)])
	arena.player_position = arena._arena_rect().get_center() + Vector2(-220.0, 100.0)
	_expect((arena._arena_rect() as Rect2).grow(-14.0).grow(0.001).has_point(arena.player_position), "ring: the player did not start inside the map rectangle")


func _test_room_copy_and_concept_routing(arena: Node) -> void:
	# The shipped campaign content owns the ring copy. Pin the exact sentences:
	# they must teach the whole-map walkable ground and never replay the retired
	# central-well wording, because contract_plan merges them into every ring
	# room and the HUD banner/summary read them verbatim.
	var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/early_campaign.json"))
	_expect(not content.is_empty(), "ring copy: shipped campaign content did not parse")
	if content.is_empty():
		return
	var ring: Dictionary = {}
	for layout_value: Variant in content.get("layouts", []):
		var layout: Dictionary = layout_value
		if String(layout.get("id", "")) == "ring":
			ring = layout
			break
	_expect(not ring.is_empty(), "ring copy: shipped content lost the ring layout")
	if ring.is_empty():
		return
	var shipped_concept := String(ring.get("concept", ""))
	var shipped_entry_hint := String(ring.get("entry_hint", ""))
	_expect(shipped_concept.contains("整片"), "ring copy: shipped concept no longer teaches the whole-map walkable ground")
	_expect(shipped_entry_hint.contains("整片"), "ring copy: shipped entry hint no longer teaches the whole-map walkable ground")
	_expect(not shipped_concept.contains("内圈空井") and not shipped_entry_hint.contains("内圈空井"),
		"ring copy: shipped content replayed the retired central-well wording")
	_expect(not shipped_entry_hint.contains("沿外环"), "ring copy: shipped entry hint replayed the retired outer-ring wording")
	_expect(String(ring.get("display_name", "")) == "回收环场" and String(ring.get("landmark", "")) == "环形灯标",
		"ring copy: shipped content lost the ring name and landmark")

	# The same sentences must survive the room merge exactly as contract_plan
	# delivers them at runtime.
	arena.embedded_session = true
	arena.framework_room = {
		"room_id": "bounds.ring.copy",
		"layout_id": "ring",
		"layout": "ring",
		"objective_id": "clear",
		"objective": "clear",
		"hazard_ids": [],
		"enemy_ids": ["melee_pursuer"],
		"elite_rule_ids": [],
		"boss_id": "",
		"drop_tags": ["equipment_general"],
		"display_name": String(ring.get("display_name", "")),
		"concept": shipped_concept,
		"landmark": String(ring.get("landmark", "")),
		"entry_hint": shipped_entry_hint,
		"exit_hint": String(ring.get("exit_hint", "")),
	}
	arena._spawn_wave()
	var info: Dictionary = arena._room_presentation_info()
	_expect(String(info.get("concept", "")) == shipped_concept and String(info.get("entry_hint", "")) == shipped_entry_hint,
		"ring copy: the merged room copy no longer matches the shipped content")
	_expect(String(info.get("display_name", "")) == "回收环场" and String(info.get("landmark", "")) == "环形灯标", "ring copy: content-owned name and landmark were dropped")
	_expect(String(info.get("exit_hint", "")) == "清场后沿东南环门离场。", "ring copy: content-owned exit hint was dropped")
	_expect(String(arena._walkable_layout_id()) == "rectangle_arena", "ring copy: room concept art still routes to the retired ring landmark")


func _test_other_layouts_unchanged(arena: Node) -> void:
	_configure_room(arena, "corridor", ["melee_pursuer"])
	_expect(String(arena._walkable_layout_id()) == "corridor", "corridor: collision layout id changed")
	var corridor: Dictionary = arena._walkable_geometry(16.0)
	_expect(String(corridor.get("kind", "")) == "corridor" and float(corridor.get("corridor_half_height", -1.0)) > 0.0, "corridor: walkable strip geometry changed")
	_configure_room(arena, "rectangle_arena", ["melee_pursuer"])
	var rectangle: Dictionary = arena._walkable_geometry(14.0)
	_expect(String(rectangle.get("kind", "")) == "rectangle" and Rect2(rectangle.get("bounds", Rect2())) == (arena._arena_rect() as Rect2).grow(-14.0), "rectangle: walkable geometry changed")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
