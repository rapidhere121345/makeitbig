extends SceneTree

const ActorPresenter := preload("res://src/presentation/arena_actor_presenter.gd")
const WorldView := preload("res://src/presentation/arena_world_view.gd")
const WorldPresenterScript := preload("res://src/runtime/world/world_presenter.gd")
const Snapshot := preload("res://src/presentation/combat_presentation_snapshot.gd")
const FrameBuilder := preload("res://src/presentation/combat_presentation_frame_builder.gd")
const Enemy := preload("res://src/runtime/world/combat_enemy_state.gd")
const Codec := preload("res://src/game/combat_state_codec.gd")
const Big := preload("res://src/core/big_value.gd")
const Assert := preload("res://tests/helpers/assert.gd")

# Record the real production sprite dispatch, then issue the real draw command.
# Test textures/visual-parts definitions are not substituted for the atlas.
class RecordingView extends WorldView:
	var sprite_calls: Array[String] = []
	var reverse_parts := false

	func boss_draw_parts(feet: Vector2, phase: int, left: Vector2, right: Vector2, pose: Dictionary = {}) -> Array[Dictionary]:
		var parts := super.boss_draw_parts(feet, phase, left, right, pose)
		if reverse_parts:
			parts.reverse()
		return parts

	func draw_sprite(canvas: CanvasItem, id: String, feet: Vector2, flip := false, tint := Color.WHITE, cut := Rect2(), alpha := 1.0) -> void:
		sprite_calls.append(id)
		super.draw_sprite(canvas, id, feet, flip, tint, cut, alpha)


class CountingPresenter extends ActorPresenter:
	var health_bar_calls: Array[int] = []

	func _draw_boss_world_bar(canvas: CanvasItem, frame: Dictionary, view: RefCounted, enemy: CombatEnemyState) -> void:
		health_bar_calls.append(enemy.entity_id)
		super._draw_boss_world_bar(canvas, frame, view, enemy)


class ActorCanvas extends Node2D:
	var renderer: ActorPresenter
	var frame: Dictionary
	var view: RefCounted

	func _draw() -> void:
		draw_set_transform_matrix(view.world_transform())
		renderer.draw(self, frame, view)


var failures: Array[String] = []
var view := RecordingView.new()
var presenter := CountingPresenter.new()
var boss := Enemy.new(Vector2(640, 450), 777.0, true, 7, "threshold_colossus")
var builder := FrameBuilder.new()
var authoritative_values: Dictionary
var snapshot: Dictionary
var frame: Dictionary


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_expect(view.load_assets(), "approved arena assets failed to load")
	view.begin_frame(Rect2(0, 0, 1280, 720), Vector2(640, 480), Rect2(42, 190, 1196, 488))
	boss.left_hand_position = boss.position + Vector2(-34, 100)
	boss.target_shape = {"type": "circle", "origin": Vector2(500, 450), "radius": 10.0}
	authoritative_values = {
		"in_arena": true, "sim_tick": 10,
		"player_position": Vector2(640, 480), "player_facing": Vector2.DOWN,
		"enemies": [boss], "boss": boss,
		"boss_damage": Big.from_float(250), "boss_maximum": Big.from_float(1000),
	}
	var before := _authority_hash()
	_expect(before.length() == 64, "authority fixture failed canonical hashing")
	snapshot = Snapshot.capture(authoritative_values)
	frame = builder.actor_frame(snapshot, _visual())
	_test_projection()
	await _test_equal_baseline_occlusion()
	await _test_real_draw_order()
	await _test_shared_native_sort()
	_expect(_authority_hash() == before, "draw/sort projection changed canonical authority hash")
	_test_detached_values()
	_expect(_authority_hash() == before, "mutating detached presentation values changed canonical authority hash")
	if failures.is_empty():
		print("PASS test_boss_parts_presentation.gd: real draw dispatch, shared native SortRoot, detached authority")
		quit(0)
		return
	for failure: String in failures:
		printerr("- %s" % failure)
	quit(1)


func _test_projection() -> void:
	var entries := presenter.draw_list(frame, view)
	var ids := _ids(entries)
	_expect(ids.count("enemy/7/body") == 1 and ids.count("enemy/7/core") == 1 and ids.count("enemy/7/left_hand") == 1 and ids.count("enemy/7/right_hand") == 1, "Boss parts lack unique stable entity/part identities")
	_expect(ids.find("enemy/7/body") < ids.find("ranger/body") and ids.find("ranger/body") < ids.find("enemy/7/left_hand"), "player cannot sort between body and gameplay-positioned hand")
	var body := _entry(entries, "enemy/7/body")
	var core := _entry(entries, "enemy/7/core")
	var hand := _entry(entries, "enemy/7/left_hand")
	_expect(body.enemy == core.enemy and core.enemy == hand.enemy and is_equal_approx(frame.boss_health_ratio, 0.75), "parts split shared Boss health/phase identity")
	_expect(body.part.sprite_id == "boss.body_phase1" and core.part.sprite_id == "boss.core_phase1", "parts do not read one shared phase")
	var expected_anchor: Vector2 = view.gameplay_to_world(boss.position) + WorldView.BOSS_HAND_LEFT_OFFSET + Vector2(0, 100) * WorldView.GAMEPLAY_TO_WORLD
	_expect((hand.world as Vector2).is_equal_approx(expected_anchor), "hand sort anchor did not follow gameplay pose and authored art baseline")
	view.reverse_parts = true
	_expect(_ids(presenter.draw_list(frame, view)) == ids, "part source insertion order changed stable sort")
	view.reverse_parts = false
	var other := Enemy.new(boss.position, 100.0, false, 8)
	var reordered := frame.duplicate(true)
	reordered.enemies = [other, frame.enemies[0]]
	var first := _ids(presenter.draw_list(reordered, view))
	reordered.enemies.reverse()
	_expect(first == _ids(presenter.draw_list(reordered, view)), "enemy insertion order changed stable sort")


func _test_equal_baseline_occlusion() -> void:
	## All Boss parts share the player's baseline here. The hand gameplay pose then
	## moves both hand anchors onto that same baseline, exercising rank/id ties in
	## the draw list, prepass, cutaway lookup and Boss group helper.
	var equal_boss: CombatEnemyState = Snapshot.enemy_record(frame.enemies[0])
	equal_boss.position = boss.position
	# Pull both posed hands just into the hero cell while keeping all four
	# authored sort baselines equal. This makes the production prepass exercise
	# the worst case where every Boss part contributes to one cutaway budget.
	equal_boss.left_hand_position = equal_boss.position + Vector2(30.0, 25.0)
	equal_boss.right_hand_position = equal_boss.position + Vector2(-30.0, 25.0)
	var equal_frame := frame.duplicate(true)
	equal_frame.player_position = equal_boss.position
	equal_frame.enemies = [equal_boss]
	equal_frame.boss = equal_boss
	view.begin_frame(Rect2(0, 0, 1280, 720), equal_boss.position, Rect2(42, 190, 1196, 488))
	var entries := presenter.draw_list(equal_frame, view)
	var ids := _ids(entries)
	_expect(ids.find("ranger/body") < ids.find("enemy/7/body") and ids.find("enemy/7/body") < ids.find("enemy/7/core") and ids.find("enemy/7/core") < ids.find("enemy/7/left_hand") and ids.find("enemy/7/left_hand") < ids.find("enemy/7/right_hand"), "equal-y body/core/hand order did not use rank then stable id")
	var canvas := ActorCanvas.new()
	canvas.renderer = presenter
	canvas.frame = equal_frame
	canvas.view = view
	root.add_child(canvas)
	await _redraw(canvas)
	_expect(view.sprite_calls.find("ranger.south.idle") < view.sprite_calls.find("boss.body_phase1") and view.sprite_calls.find("boss.body_phase1") < view.sprite_calls.find("boss.core_phase1") and view.sprite_calls.find("boss.core_phase1") < view.sprite_calls.find("boss.hand_left") and view.sprite_calls.find("boss.hand_left") < view.sprite_calls.find("boss.hand_right"), "equal-y actual draw pass diverged from stable sort")
	canvas.free()
	for entry: Dictionary in entries:
		if entry.kind == "boss_part":
			var part: Dictionary = entry.part
			## Use the real part baseline and a one-cell overlap probe so this check
			## isolates the sort relation from the hands' lateral art placement.
			var cut: Dictionary = view.cutaway_for(view.hero_cell_world(view.gameplay_to_world(equal_boss.position)), entry.world, view.gameplay_to_world(equal_boss.position), int(entry.rank), String(entry.id))
			_expect(bool(cut.in_front), "equal-y Boss part %s disagrees with draw order" % String(entry.id))
	presenter._prepare_occlusion(entries, equal_frame, view)
	var hero_world := view.gameplay_to_world(equal_boss.position)
	var production_report: Dictionary = view.occlusion_report(hero_world)
	for part_id in ["enemy/7/body", "enemy/7/core", "enemy/7/left_hand", "enemy/7/right_hand"]:
		_expect((production_report.front_ids as Array).has(part_id), "production actor prepass dropped Boss part %s from the shared cutaway budget" % part_id)
	_expect(float(production_report.local_opacity_total) <= 0.160001, "production Boss parts exceeded the shared local opacity budget")
	var probe_cells: Array[Dictionary] = []
	for entry: Dictionary in entries:
		if entry.kind == "boss_part":
			probe_cells.append({"id": entry.id, "stable_id": entry.id, "sort_rank": int(entry.rank), "baseline_y": float(entry.baseline_y), "feet_world": entry.world, "art_box": view.hero_cell_world(hero_world), "base_alpha": 1.0})
	view.prepare_actor_occlusion(probe_cells, hero_world)
	var report: Dictionary = view.occlusion_report(hero_world)
	for part_id in ["enemy/7/body", "enemy/7/core", "enemy/7/left_hand", "enemy/7/right_hand"]:
		_expect((report.front_ids as Array).has(part_id), "equal-y occlusion prepass dropped %s" % part_id)
	var parts: Array[Dictionary] = view.boss_draw_parts(view.gameplay_to_world(equal_boss.position), 1, Vector2(0, 25), Vector2(0, 25))
	var sprite_ids: Array = parts.map(func(part: Dictionary) -> String: return String(part.sprite_id))
	var feet_list: Array = parts.map(func(part: Dictionary) -> Vector2: return part.feet)
	var boss_cut: Dictionary = view._boss_cutaway(sprite_ids, feet_list, view.gameplay_to_world(equal_boss.position), view.gameplay_to_world(equal_boss.position))
	_expect((boss_cut.window as Rect2).size.x > 0.0, "equal-y Boss group helper disagreed with part sort anchors")


func _test_real_draw_order() -> void:
	var canvas := ActorCanvas.new()
	canvas.renderer = presenter
	canvas.frame = frame
	canvas.view = view
	root.add_child(canvas)
	await _redraw(canvas)
	var first: Array[String] = view.sprite_calls.duplicate()
	_expect(first.find("boss.body_phase1") < first.find("ranger.south.idle") and first.find("ranger.south.idle") < first.find("boss.hand_left"), "actual production draw calls did not place player between body and hand")
	_expect(first.count("boss.body_phase1") == 1 and first.count("boss.core_phase1") == 1 and first.count("boss.hand_left") == 1 and first.count("boss.hand_right") == 1, "actual draw dispatched a Boss part twice")
	_expect(presenter.health_bar_calls == [7], "Boss drew multiple health bars")
	view.reverse_parts = true
	await _redraw(canvas)
	_expect(view.sprite_calls == first and presenter.health_bar_calls == [7], "reversed part insertion changed actual production draw dispatch")
	view.reverse_parts = false
	canvas.free()


func _test_shared_native_sort() -> void:
	var domain := WorldPresenterScript.new()
	# Combat native coordinates are gameplay coordinates. The host applies the
	# same explicit camera transform to all native/dynamic children.
	domain.transform = view.gameplay_transform()
	root.add_child(domain)
	var native := Node2D.new()
	native.name = "NativeOccluder"
	native.position = Vector2(640, 470)
	domain.sort_root.add_child(native)
	var result := presenter.sync_sort_views(domain, frame, view)
	_expect(result.ok and domain.sort_root.y_sort_enabled, "shared sort submission failed")
	var nodes := _actor_nodes(domain)
	var body: Node2D = nodes["enemy/7/body"]
	var player: Node2D = nodes["ranger/body"]
	var hand: Node2D = nodes["enemy/7/left_hand"]
	_expect(body != player and player != hand and body.get_parent() == native.get_parent() and hand.get_parent() == native.get_parent(), "actors/parts/native remain flattened in separate CanvasItems or sort roots")
	_expect(body.position.y < native.position.y and native.position.y < player.position.y and player.position.y < hand.position.y, "native node cannot interleave body/player/hand in the same y-sort domain")
	# Equal baselines are ordered by the shared rank/id contract, including a
	# native child that was authored before the dynamic views existed.
	native.position.y = player.position.y
	native.set_meta("sort_rank", 3)
	native.set_meta("sort_stable_id", "aaa/native")
	domain.reorder_sort_root()
	var equal_order := _sort_root_names(domain)
	_expect(equal_order.find("ranger_body") < equal_order.find("NativeOccluder"), "equal-baseline rank did not outrank stable id: %s" % str(equal_order))
	native.set_meta("sort_rank", 2)
	domain.reorder_sort_root()
	equal_order = _sort_root_names(domain)
	_expect(equal_order.find("NativeOccluder") < equal_order.find("ranger_body"), "equal-baseline stable id did not resolve a rank tie: %s" % str(equal_order))
	for node: Node2D in nodes.values():
		_expect(node.z_index == 0 and not node.y_sort_enabled, "part used arbitrary z or another nested sorting domain")
		_expect(not node.frame.enemies.is_empty() and node.frame.enemies[0] != frame.enemies[0], "native views retained mutable actor-frame enemy references")
	# The equal-baseline body/core pair must stay stable after native registration
	# starts from the opposite sibling insertion order.
	var original_ids: Array = result.ids.duplicate()
	var reverse_nodes := nodes.values()
	reverse_nodes.reverse()
	for node: Node2D in reverse_nodes:
		domain.sort_root.move_child(node, domain.sort_root.get_child_count() - 1)
	view.reverse_parts = true
	var reversed_result := presenter.sync_sort_views(domain, frame, view)
	_expect(reversed_result.ids == original_ids, "native registration changed stable entity/part order")
	_expect(_registered_order(domain) == original_ids, "native equal-y sibling order depends on insertion")
	view.reverse_parts = false
	view.sprite_calls.clear()
	presenter.health_bar_calls.clear()
	for node: Node2D in nodes.values():
		node.queue_redraw()
	await process_frame
	await process_frame
	_expect(view.sprite_calls.has("boss.hand_left") and view.sprite_calls.has("ranger.south.idle") and presenter.health_bar_calls == [7], "native nodes did not execute actual production part/player drawing and single blood bar")
	var no_boss := frame.duplicate(true)
	no_boss.enemies = []
	presenter.sync_sort_views(domain, no_boss, view)
	_expect(not domain.actor_ids().has("enemy/7/body") and not domain.actor_ids().has("enemy/7/left_hand"), "despawn left stale Boss part views")
	presenter.release_sort_views()
	_expect(domain.actor_ids().is_empty() and native.get_parent() == domain.sort_root, "view teardown removed native content or leaked actors")
	domain.free()
	await process_frame


func _test_detached_values() -> void:
	_expect(snapshot.boss == snapshot.enemies[0] and snapshot.boss != boss and frame.enemies[0] != snapshot.boss, "snapshot/frame failed to detach one logical Boss")
	frame.enemies[0].health = 0.0
	frame.enemies[0].phase_id = "awakened"
	frame.enemies[0].left_hand_position += Vector2(300, 100)
	frame.enemies[0].parts[0].hurtbox.radius = 9999.0
	frame.enemies[0].target_shape.radius = 9999.0
	_expect(snapshot.boss.health == 777.0 and snapshot.boss.phase_id == "sealed" and snapshot.boss.parts[0].hurtbox.radius != 9999.0, "actor-frame mutation reached detached source snapshot")
	_expect(boss.health == 777.0 and boss.phase_id == "sealed" and boss.parts[0].hurtbox.radius != 9999.0 and boss.target_shape.radius == 10.0, "presentation retained live gameplay dictionaries")
	var phase_parts := presenter.draw_list(frame, view).filter(func(entry: Dictionary) -> bool: return entry.kind == "boss_part")
	_expect(phase_parts.all(func(entry: Dictionary) -> bool: return entry.enemy.phase_id == "awakened"), "parts diverged from their single phase record")


func _authority_hash() -> String:
	var fields := {}
	for field: String in Snapshot.ENEMY_FIELDS:
		fields[field] = boss.get(field)
	return Codec.sha256_canonical(Codec.hash_safe({"enemy": fields, "player_position": authoritative_values.player_position, "damage": {"layer": authoritative_values.boss_damage.layer, "magnitude": authoritative_values.boss_damage.magnitude}, "maximum": {"layer": authoritative_values.boss_maximum.layer, "magnitude": authoritative_values.boss_maximum.magnitude}}))


func _redraw(canvas: Node2D) -> void:
	view.sprite_calls.clear()
	presenter.health_bar_calls.clear()
	canvas.queue_redraw()
	await process_frame
	await process_frame


func _actor_nodes(domain: WorldPresenter) -> Dictionary:
	var nodes := {}
	for node: Node in domain.sort_root.get_children():
		if node is ActorPresenter.SortView:
			nodes[String(node.drawable.id)] = node
	return nodes


func _registered_order(domain: WorldPresenter) -> Array:
	var ids := []
	for node: Node in domain.sort_root.get_children():
		if node is ActorPresenter.SortView:
			ids.append(String(node.drawable.id))
	return ids


func _sort_root_names(domain: WorldPresenter) -> Array:
	var names: Array[String] = []
	for node: Node in domain.sort_root.get_children():
		names.append(String(node.name))
	return names


func _visual() -> Dictionary:
	return {"ranger_visual_time": 0.0, "ranger_frame": {}, "enemy_frames": {}, "enemy_corpses": []}


func _ids(entries: Array[Dictionary]) -> Array:
	return entries.map(func(entry: Dictionary) -> String: return String(entry.id))


func _entry(entries: Array[Dictionary], id: String) -> Dictionary:
	for entry: Dictionary in entries:
		if entry.id == id:
			return entry
	return {}


func _expect(condition: bool, message: String) -> void: Assert.expect(condition, message, failures)
