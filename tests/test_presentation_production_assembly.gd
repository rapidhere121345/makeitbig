extends SceneTree

## Mounted production assembly gate (windowed: run under the host GPU entry).
## Covers the composition-root seam from redesign.md sections 9-10 on REAL
## mounted rooms, not test doubles:
##   1. SceneRuntime binds the detached presentation projector itself at mount,
##      and manifest occlusion-channel pieces enter it as static bindings with
##      art boxes measured on the mounted scene's real drawn art.
##   2. A mounted room with unbound actor visuals fails closed on the next
##      snapshot: recorded errors, no frame, no invented entries, no plan.
##   3. restart_room_instance re-assembles the same static bindings on a fresh
##      projector and clears stale frames/errors at the boundary.
##   4. A presented combat room carries real actor art boxes from the skin,
##      a bound static piece occludes a subject in the detached plan, and the
##      plan drives the drawn sort views through OcclusionController.
##   5. The whole pipeline is display-only: presented and headless twins stay
##      semantically identical, and a presentation-off twin never fabricates
##      display data.

const TownControllerScript := preload("res://src/runtime/world/town_controller.gd")
const CombatRoomRuntimeScript := preload("res://src/game/combat_room_runtime.gd")
const EarlyItemRegistryScript := preload("res://src/content/early_item_registry.gd")
const BuildResolverScript := preload("res://src/systems/build_resolver.gd")
const ContentRegistryScript := preload("res://src/content/content_registry.gd")
const ProxyBuildScript := preload("res://src/systems/proxy_build.gd")
const ArenaWorldViewScript := preload("res://src/presentation/arena_world_view.gd")
const TownPresenterScript := preload("res://src/presentation/town_presenter.gd")
const HamletLifeAnimationScript := preload("res://src/presentation/hamlet_life_animation.gd")
const OcclusionControllerScript := preload("res://src/presentation/occlusion/occlusion_controller.gd")

const TICK_DELTA := 1.0 / 30.0
const OCCLUSION_FLOOR := 0.399

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	_test_town_composition_root_assembly()
	await _test_presented_room_display_driving()
	for failure: String in failures:
		printerr("- %s" % failure)
	print("PASS test_presentation_production_assembly.gd" if failures.is_empty() else "FAIL test_presentation_production_assembly.gd")
	quit(0 if failures.is_empty() else 1)


func _test_town_composition_root_assembly() -> void:
	var town = TownControllerScript.new()
	root.add_child(town)
	var mounted: Dictionary = town.mount(root)
	_expect(bool(mounted.get("ok", false)), "town: real mounted room rejected: %s" % str(mounted), failures)
	if not bool(mounted.get("ok", false)):
		town.queue_free()
		return
	var runtime: Variant = town.get("scene_runtime")
	var port: Variant = runtime.get("presentation_port")
	var projector: Variant = runtime.get("presentation_projector")
	_expect(runtime.get("presentation_projector") != null, "town: composition root did not bind the presentation projector at mount", failures)
	_expect(port != null and bool(port.call("has_projector")), "town: presentation port lost the mounted projector", failures)
	_expect((port.get("last_projection_errors") as Array).is_empty(), "town: mount produced projection errors before any tick: %s" % str(port.get("last_projection_errors")), failures)

	var occlusion_bindings: Array = runtime.get("manifest").call("occlusion_bindings")
	var binding_ids: Array[String] = projector.call("static_binding_ids")
	var expected_ids: Array[String] = []
	for source: Variant in occlusion_bindings:
		expected_ids.append(String((source as Dictionary)["binding_id"]))
	expected_ids.sort()
	_expect(binding_ids == expected_ids and binding_ids.size() == 35, "town: static assembly did not cover every authored occlusion piece (%d vs %d)" % [binding_ids.size(), expected_ids.size()], failures)
	_expect(projector.call("static_binding_count") == occlusion_bindings.size(), "town: static binding count diverged from the manifest", failures)
	_check_town_static_art(runtime, projector, binding_ids)

	var advanced: Dictionary = town.call("advance_frame", Vector2.ZERO, TICK_DELTA)
	_expect(bool(advanced.get("ok", false)), "town: authoritative tick rejected", failures)
	var errors: Array = port.get("last_projection_errors")
	_expect(errors.has("missing_presentation_binding:town/ranger"), "town: unbound actor visuals did not fail closed: %s" % str(errors.slice(0, 3)), failures)
	_expect(port.get("latest_frame") == null, "town: fail-closed tick still produced a frame", failures)
	var blocked_plan: Dictionary = port.call("latest_occlusion_plan")
	_expect(not bool(blocked_plan.get("ok", false)), "town: fail-closed tick still produced an occlusion plan", failures)

	# The hub-side presentation attaches after mount and pushes every
	# registered town actor's real drawn cell into the projector through the
	# production SceneRuntime API. Until that attach the room stays fail-closed
	# (asserted above); after it the mounted town frame must be complete.
	var view = TownPresenterScript.new()
	root.add_child(view)
	var assets: Dictionary = view.call("load_character_assets")
	_expect(bool(assets.get("ok", false)), "town: presenter character assets rejected: %s" % str(assets), failures)
	var attached: Dictionary = view.call("attach", runtime.get("presenter"), town.get("town").call("snapshot"), runtime)
	_expect(bool(attached.get("ok", false)), "town: presenter attach with presentation binding rejected: %s" % str(attached), failures)
	_check_town_actor_bindings(view, projector)

	var bound_tick: Dictionary = town.call("advance_frame", Vector2.ZERO, TICK_DELTA)
	_expect(bool(bound_tick.get("ok", false)), "town: bound authoritative tick rejected", failures)
	var bound_errors: Array = port.get("last_projection_errors")
	_expect(bound_errors.is_empty(), "town: fully bound mounted room still failed projection: %s" % str(bound_errors.slice(0, 3)), failures)
	_run_town_occlusion_chain(port, view, runtime, town.get("town"))

	var projector_before: Variant = projector
	var restarted: Dictionary = runtime.call("restart_room_instance")
	_expect(bool(restarted.get("ok", false)), "town: restart rejected: %s" % str(restarted), failures)
	var projector_after: Variant = runtime.get("presentation_projector")
	_expect(projector_after != null and projector_after != projector_before, "town: restart did not re-assemble a fresh projector", failures)
	_expect((projector_after.call("static_binding_ids") as Array[String]) == binding_ids, "town: restart lost the static authored bindings", failures)
	var port_after: Variant = runtime.get("presentation_port")
	_expect((port_after.get("last_projection_errors") as Array).is_empty() and port_after.get("latest_frame") == null, "town: restart leaked stale frames or errors across the boundary", failures)
	# Actor visual bindings belong to the presentation attach boundary, not to
	# the runtime restart: a restarted town re-attaches through the hub, and
	# until then the projector correctly holds statics only.
	_expect(projector_after.call("actor_binding", "town/ranger") == null, "town: restart kept actor bindings on the fresh projector", failures)

	town.call("abort_loading", {"ok": true, "error": ""})
	_expect(runtime.get("presentation_projector") == null and runtime.get("presentation_port") == null, "town: unmount kept presentation seams alive", failures)
	view.queue_free()
	town.queue_free()


## Cross-checks every actor binding the attach pushed against this test's own
## real metadata sources: the published hero cell metadata and an independent
## HamletLifeAnimation reader for resident clips.
func _check_town_actor_bindings(view: Variant, projector: Variant) -> void:
	var report: Array = view.call("actor_presentation_report")
	_expect(not report.is_empty(), "town: presenter reported no actor bindings", failures)
	var metadata: Dictionary = view.call("hero_visual_metadata")
	var hero_rect: Array = metadata.get("rect", [])
	var hero_anchor: Array = metadata.get("anchor", [])
	var expected_hero_box := Rect2(
		-float(hero_anchor[0]), -float(hero_anchor[1]),
		float(hero_rect[2]), float(hero_rect[3]))
	var life = HamletLifeAnimationScript.new()
	life.load_default_assets()
	var hero_seen := false
	for record: Variant in report:
		var entry: Dictionary = record
		var stable_id := String(entry["stable_id"])
		var binding: Variant = projector.call("actor_binding", stable_id)
		if binding == null:
			_expect(false, "town: %s has no projector actor binding" % stable_id, failures)
			continue
		_expect(String(binding.visual_id) == String(entry["visual_id"]), "town: %s visual identity diverged from the presenter" % stable_id, failures)
		if stable_id == "town/ranger":
			hero_seen = true
			_expect((binding.art_box as Rect2).is_equal_approx(expected_hero_box), "town: hero binding left the real 48x48 cell: %s vs %s" % [str(binding.art_box), str(expected_hero_box)], failures)
			continue
		var frame: Dictionary = life.frame_at(String(entry["visual_id"]), 0.0)
		var cell: Rect2 = frame.get("rect", Rect2())
		var anchor: Vector2 = frame.get("anchor", Vector2.ZERO)
		var expected := Rect2(-anchor.x, -anchor.y, cell.size.x, cell.size.y)
		_expect((binding.art_box as Rect2).is_equal_approx(expected), "town: %s binding left the real resident cell: %s vs %s" % [stable_id, str(binding.art_box), str(expected)], failures)
	_expect(hero_seen, "town: presenter report lost the hero binding", failures)


## Runs the detached occlusion chain over the real mounted town frame: plan,
## deterministic order, controller adoption and at least one real front
## relationship between the authored pieces.
func _run_town_occlusion_chain(port: Variant, view: Variant, runtime: Variant, town: Variant) -> void:
	var frame: Variant = port.get("latest_frame")
	_expect(frame != null, "town: fully bound room produced no presentation frame", failures)
	if frame == null:
		return
	var entries: Array = frame.get("entries")
	var plan_result: Dictionary = port.call("latest_occlusion_plan")
	_expect(bool(plan_result.get("ok", false)), "town: detached plan unavailable for the bound frame", failures)
	if not bool(plan_result.get("ok", false)):
		return
	var plan: Variant = plan_result.get("value")
	_expect((plan as Variant).call("size") == entries.size(), "town: plan size diverged from the projected frame", failures)
	var plan_ids: Array[String] = []
	for entry: Variant in entries:
		plan_ids.append(String((entry as Dictionary)["stable_id"]))
	var controller = OcclusionControllerScript.new()
	var adopted: Dictionary = controller.call("adopt_plan", plan)
	_expect(bool(adopted.get("ok", false)), "town: occlusion controller rejected the mounted plan", failures)
	var tracked: Array[String] = controller.call("tracked_ids")
	tracked.sort()
	var expected_tracked := plan_ids.duplicate()
	expected_tracked.sort()
	_expect(tracked == expected_tracked, "town: controller tracked set diverged from the plan", failures)
	var hero_report: Dictionary = (plan as Variant).call("occlusion_report", "town/ranger")
	_expect(bool(hero_report.get("ok", false)), "town: hero occlusion report rejected", failures)
	var occluded_pairs := 0
	for entry: Variant in entries:
		var subject_report: Dictionary = (plan as Variant).call("occlusion_report", String((entry as Dictionary)["stable_id"]))
		if bool(subject_report.get("occluded", false)):
			occluded_pairs += 1
	_expect(occluded_pairs > 0, "town: no real front relationship found among the authored pieces", failures)

	# Drive the same production projector with one explicit authored test
	# occluder, then consume the detached plan through the real TownPresenter.
	# This proves the town actor sprite receives alpha from presentation data,
	# while the simulation remains responsible for the hero position.
	var hero_binding: Variant = (runtime.get("presentation_projector") as Variant).call("actor_binding", "town/ranger")
	var hero_position: Vector2 = town.hero_world_position()
	var probe_box: Rect2 = hero_binding.art_box
	var probe_anchor := hero_position + Vector2(0.0, 8.0)
	var probe_bound: Dictionary = runtime.bind_static_presentation("town/test/probe", "town.test.probe", 3, probe_box, probe_anchor)
	_expect(bool(probe_bound.get("ok", false)), "town: production occlusion probe binding was rejected: %s" % str(probe_bound), failures)
	if not bool(probe_bound.get("ok", false)):
		return
	town.submit_move(Vector2.ZERO)
	var ticked: Dictionary = town.advance_frame(TICK_DELTA)
	_expect(bool(ticked.get("ok", false)), "town: occlusion probe tick failed", failures)
	view.consume(town.snapshot())
	view.call("_process", TICK_DELTA)
	var display: Dictionary = view.occlusion_report()
	_expect(bool(display.get("available", false)), "town: presenter did not adopt the detached occlusion plan: %s" % str(display), failures)
	var hero_alpha := float(display.get("alphas", {}).get("town/ranger", 1.0))
	_expect(hero_alpha < 0.999 and hero_alpha >= OCCLUSION_FLOOR, "town: actor alpha was not driven by the authored occluder: %.3f" % hero_alpha, failures)
	_expect(is_equal_approx(float(view.actor_alpha("town/ranger")), hero_alpha), "town: drawn hero alpha diverged from controller alpha", failures)


## Cross-checks the assembled static bindings against the mounted scene's
## authored sprite data through an independent formula: authored
## position/offset/centering plus the real loaded texture size.
func _check_town_static_art(runtime: Variant, projector: Variant, binding_ids: Array[String]) -> void:
	# mount_world_scene() reparents authored layer content into the presenter's
	# shared layers, so the real art nodes live under the presenter subtree.
	var mounted_scene: Node = runtime.get("presenter")
	var authored: Dictionary = {}
	var stack: Array[Node] = [mounted_scene]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.has_meta("binding_id"):
			authored[String(node.get_meta("binding_id"))] = node
		for child: Node in node.get_children():
			stack.append(child)
	var checked := 0
	for binding_id: String in binding_ids:
		var node: Variant = authored.get(binding_id, null)
		var binding: Variant = projector.call("static_binding", binding_id)
		if node == null or binding == null or not node is Sprite2D:
			_expect(false, "town: %s did not resolve to mounted sprite art" % binding_id, failures)
			continue
		var sprite := node as Sprite2D
		if sprite.texture == null:
			_expect(false, "town: %s mounted without its real texture" % binding_id, failures)
			continue
		var half := (sprite.texture.get_size() * 0.5) if sprite.centered else Vector2.ZERO
		var world_box := Rect2(sprite.position + sprite.offset - half, sprite.texture.get_size())
		var feet := Vector2(world_box.get_center().x, sprite.position.y)
		var projected_box := Rect2((binding.static_feet_anchor as Vector2) + (binding.art_box as Rect2).position, (binding.art_box as Rect2).size)
		_expect(projected_box.is_equal_approx(world_box), "town: %s art box left the real drawn pixels: %s vs %s" % [binding_id, str(projected_box), str(world_box)], failures)
		_expect((binding.static_feet_anchor as Vector2).is_equal_approx(feet), "town: %s baseline left the native Y-sort anchor" % binding_id, failures)
		_expect(String(binding.visual_id) == binding_id and int(binding.rank) == 0, "town: %s identity diverged from the manifest binding" % binding_id, failures)
		checked += 1
	_expect(checked == binding_ids.size(), "town: static art cross-check skipped pieces", failures)


func _test_presented_room_display_driving() -> void:
	var presented = _start_session(true)
	var headless = _start_session(false)
	_expect(presented.node != null and headless.node != null, "session: mounted combat rooms did not start", failures)
	if presented.node == null or headless.node == null:
		return

	# The occlusion phase runs first, while the pursuer is still near its
	# authored spawn and far from the ranger, so the probe anchor can never sit
	# on the player. The frame, art-box and plan gates then run on the later,
	# settled combat state.
	for _index in 5:
		presented.node.call("_process", TICK_DELTA)
		headless.node.call("_process", TICK_DELTA)
	var stage_a_left := _semantic_snapshot(presented.node)
	var stage_a_right := _semantic_snapshot(headless.node)
	_expect(stage_a_left == stage_a_right, "stage-a: twins diverged before the occlusion phase: %s" % str(_state_diff(stage_a_left, stage_a_right)), failures)
	var enemy_id := _enemy_stable_id(presented.node)
	_drive_occlusion_display(presented, headless, enemy_id)
	var stage_b_left := _semantic_snapshot(presented.node)
	var stage_b_right := _semantic_snapshot(headless.node)
	_expect(stage_b_left == stage_b_right, "stage-b: twins diverged right after the occlusion phase: %s" % str(_state_diff(stage_b_left, stage_b_right)), failures)

	for _index in 85:
		presented.node.call("_process", TICK_DELTA)
		headless.node.call("_process", TICK_DELTA)

	_expect(presented.port.get("latest_frame") != null and (presented.port.get("last_projection_errors") as Array).is_empty(), "presented: mounted room rejected its kernel snapshots: %s" % str((presented.port.get("last_projection_errors") as Array).slice(0, 3)), failures)
	var headless_errors: Array = headless.port.get("last_projection_errors")
	_expect(headless.port.get("latest_frame") == null and headless_errors.has("missing_presentation_binding:ranger"), "headless: presentation-off twin fabricated display data: %s" % str(headless_errors.slice(0, 2)), failures)

	var frame: Variant = presented.port.get("latest_frame")
	var entries: Array = frame.get("entries")
	var ids: Array[String] = []
	for entry: Variant in entries:
		ids.append(String((entry as Dictionary)["stable_id"]))
	_expect(ids.has("ranger"), "presented: frame lost the ranger entry", failures)
	_expect(ids.has(enemy_id), "presented: frame lost the enemy entry %s" % enemy_id, failures)
	_check_real_actor_art_box(presented, entries)

	var plan_result: Dictionary = presented.port.call("latest_occlusion_plan")
	_expect(bool(plan_result.get("ok", false)) and (plan_result.get("value", null) as Variant).call("size") == entries.size(), "presented: detached plan diverged from the projected frame", failures)

	var presented_state := _semantic_snapshot(presented.node)
	var headless_state := _semantic_snapshot(headless.node)
	_expect(presented_state == headless_state, "no-write-back: presented and headless twins diverged: %s" % str(_state_diff(presented_state, headless_state)), failures)

	presented.runtime.queue_free()
	headless.runtime.queue_free()


func _check_real_actor_art_box(session: Dictionary, entries: Array) -> void:
	var world_view: Variant = session.node.get("presentation").get("world_view")
	_expect(world_view != null, "presented: mounted room drew without the native world view", failures)
	if world_view == null:
		return
	var world_box: Rect2 = world_view.call("sprite_art_box", "ranger.south.idle", Vector2.ZERO)
	var scale := ArenaWorldViewScript.GAMEPLAY_TO_WORLD
	var expected_size := world_box.size / scale
	for entry: Variant in entries:
		var record: Dictionary = entry
		if String(record["stable_id"]) != "ranger":
			continue
		var art_box: Rect2 = record["art_box"]
		_expect(art_box.size.is_equal_approx(expected_size), "presented: ranger art box is not the real skin box (%s vs %s)" % [str(art_box.size), str(expected_size)], failures)
		_expect(art_box.size.y > 28.0, "presented: ranger art box collapsed toward the collision footprint", failures)
		var player: Dictionary = session.node.get("player_combat_state").snapshot(int(session.node.get("sim_tick")))
		_expect((record["feet_anchor"] as Vector2).is_equal_approx(player.get("player_position", Vector2.INF)), "presented: ranger feet anchor left the authoritative position", failures)
		return
	_expect(false, "presented: frame had no ranger entry to check", failures)


## Binds one real-art static occluder through the production SceneRuntime API,
## parks the enemy under it, and requires the detached plan to dim the drawn
## enemy view through the OcclusionController while the ranger stays clear.
func _drive_occlusion_display(session: Dictionary, headless: Dictionary, enemy_id: String) -> void:
	var runtime: Variant = session.node.get("scene_runtime")
	var world_view: Variant = session.node.get("presentation").get("world_view")
	var enemy: Variant = _first_enemy(session.node)
	var scale := ArenaWorldViewScript.GAMEPLAY_TO_WORLD
	var probe_world: Rect2 = world_view.call("sprite_art_box", "ranger.south.idle", Vector2.ZERO)
	var probe_box := Rect2(probe_world.position / scale, probe_world.size / scale)
	# The anchor sits below the bound position and the enemy is parked above
	# it, so the pursuer's drift toward the ranger keeps it in front of the
	# probe for the whole assertion window instead of crossing the baseline.
	var anchor: Vector2 = (enemy.get("position") as Vector2) + Vector2(0.0, 8.0)
	var player: Dictionary = session.node.get("player_combat_state").snapshot(int(session.node.get("sim_tick")))
	var probe_world_box := Rect2(anchor + probe_box.position, probe_box.size)
	var ranger_guard := Rect2((player.get("player_position", anchor) as Vector2) + probe_box.position, probe_box.size).grow(20.0)
	_expect(not ranger_guard.intersects(probe_world_box), "occlusion: probe anchor overlaps the ranger box: %s vs %s" % [str(probe_world_box), str(ranger_guard)], failures)
	var bound: Dictionary = runtime.call("bind_static_presentation", "occlusion/probe", "probe.ranger_art", 3, probe_box, anchor)
	_expect(bool(bound.get("ok", false)), "occlusion: production static binding rejected: %s" % str(bound), failures)
	var moved: Dictionary = session.node.call("teleport_actor", enemy_id, anchor + Vector2(0.0, -14.0))
	_expect(bool(moved.get("ok", false)), "occlusion: enemy teleport rejected: %s" % str(moved), failures)
	# The teleport is a simulation input: the headless twin must receive the
	# same command so the semantic equality check stays a pure occlusion gate.
	var twin_moved: Dictionary = headless.node.call("teleport_actor", enemy_id, anchor + Vector2(0.0, -14.0))
	_expect(bool(twin_moved.get("ok", false)), "occlusion: twin teleport rejected: %s" % str(twin_moved), failures)
	_expect((moved.get("position", Vector2.INF) as Vector2).is_equal_approx(twin_moved.get("position", Vector2.INF)), "occlusion: twin teleport input diverged: %s vs %s" % [str(moved.get("position")), str(twin_moved.get("position"))], failures)

	for _index in 3:
		session.node.call("_process", TICK_DELTA)
		headless.node.call("_process", TICK_DELTA)

	var plan_result: Dictionary = session.port.call("latest_occlusion_plan")
	_expect(bool(plan_result.get("ok", false)), "occlusion: plan unavailable after probe binding", failures)
	if bool(plan_result.get("ok", false)):
		var report: Dictionary = (plan_result.get("value") as Variant).call("occlusion_report", enemy_id)
		if not (bool(report.get("occluded", false)) and (report.get("occluder_ids", []) as Array).has("occlusion/probe")):
			var enemy_position: Vector2 = (session.node.get("player_combat_state").snapshot(int(session.node.get("sim_tick"))).get("player_position", Vector2.INF))
			printerr("occlusion-debug: enemy_id=%s tick=%s enemy_pos=%s probe=%s plan=%s" % [enemy_id, str(session.node.get("sim_tick")), str(enemy_position), str(session.node.get("scene_runtime").get("presentation_projector").call("static_binding", "occlusion/probe").art_box), str((plan_result.get("value") as Variant).call("to_payload"))])
			_expect(false, "occlusion: plan did not name the real static occluder: %s" % str(report), failures)
	var sort_report: Dictionary = session.node.get("presentation").call("sort_report")
	var occlusion: Dictionary = sort_report.get("occlusion", {})
	_expect(bool(occlusion.get("available", false)), "occlusion: presentation controller did not adopt the detached plan: %s" % str(occlusion), failures)
	var alphas: Dictionary = occlusion.get("alphas", {})
	var enemy_alpha := float(alphas.get(enemy_id, 1.0))
	_expect(enemy_alpha < 0.999 and enemy_alpha >= OCCLUSION_FLOOR, "occlusion: enemy display alpha not driven by the plan (%.3f)" % enemy_alpha, failures)
	_expect(is_equal_approx(float(alphas.get("ranger", 1.0)), 1.0), "occlusion: clear ranger was dimmed", failures)
	var actor_presenter: Variant = session.node.get("presentation").get("actor_presenter")
	_expect(float(actor_presenter.call("drawn_alpha", enemy_id + "/body")) < 0.999, "occlusion: drawn enemy sort view did not receive the plan alpha", failures)
	_expect(is_equal_approx(float(actor_presenter.call("drawn_alpha", "ranger/body")), 1.0), "occlusion: drawn ranger view changed without an occluder", failures)


func _state_diff(left: Dictionary, right: Dictionary) -> Dictionary:
	var diff: Dictionary = {}
	for key: String in left.keys():
		var leaf: Array[String] = _leaf_diff(left[key], right.get(key, null), key)
		if not leaf.is_empty():
			diff[key] = leaf
	for key: String in right.keys():
		if not left.has(key):
			diff[key] = [null, right[key]]
	return diff


func _leaf_diff(left: Variant, right: Variant, path: String) -> Array[String]:
	if left is Dictionary and right is Dictionary:
		var nested: Array[String] = []
		for key: String in (left as Dictionary).keys():
			nested.append_array(_leaf_diff((left as Dictionary)[key], (right as Dictionary).get(key, null), path + "." + key))
			if nested.size() >= 4:
				return nested
		return nested
	if left is Array and right is Array:
		var nested: Array[String] = []
		var arrays: Array = [left, right]
		for index: int in range((arrays[0] as Array).size()):
			if index >= (arrays[1] as Array).size():
				nested.append("%s[%d] missing in right" % [path, index])
				break
			nested.append_array(_leaf_diff((arrays[0] as Array)[index], (arrays[1] as Array)[index], "%s[%d]" % [path, index]))
			if nested.size() >= 4:
				return nested
		return nested
	if left != right:
		return ["%s: typeof %d vs %d, %s vs %s" % [path, typeof(left), typeof(right), str(left), str(right)]]
	return []

func _start_session(presentation_enabled: bool) -> Dictionary:
	var runtime = CombatRoomRuntimeScript.new()
	root.add_child(runtime)
	var started: Dictionary = runtime.start_session({
		"contract_id": "embedded.presentation-assembly-%s" % str(presentation_enabled),
		"mode": "Manual",
		"preset_id": "convergent",
		"seed": 11,
		"room_count": 1,
		"presentation_enabled": presentation_enabled,
		"room": {
			"room_id": "room.presentation-assembly",
			"layout_id": "corridor",
			"objective_id": "clear",
			"hazard_ids": [],
			"enemy_ids": ["melee_pursuer"],
			"elite_rule_ids": [],
			"boss_id": "",
			"drop_tags": ["equipment_general"],
		},
		"framework_context": {
			"contract_wins": 0,
			"active_build": {"preset_id": "convergent"},
			"resolved_build": _resolved_fixture("calibration_convergent"),
			"resolved_proxy_build": _resolved_proxy_fixture(),
		},
	})
	if not bool(started.get("ok", false)):
		_expect(false, "session(%s): start rejected: %s" % [str(presentation_enabled), str(started)], failures)
		runtime.queue_free()
		return {"runtime": runtime, "node": null, "port": null}
	var node: Variant = runtime.get("room_instance")
	var scene_runtime: Variant = node.get("scene_runtime")
	return {"runtime": runtime, "node": node, "port": scene_runtime.get("presentation_port")}


func _first_enemy(arena: Node) -> Variant:
	var enemies: Array = arena.get("enemies")
	return enemies[0] if not enemies.is_empty() else null


func _enemy_stable_id(arena: Node) -> String:
	var enemy: Variant = _first_enemy(arena)
	return "enemy/%d" % int(enemy.get("entity_id")) if enemy != null else "enemy/-1"


func _semantic_snapshot(arena: Node) -> Dictionary:
	var player: Dictionary = arena.get("player_combat_state").snapshot(int(arena.get("sim_tick")))
	var normalized_player: Variant = _normalize(player)
	var enemies_state: Array[Dictionary] = []
	for enemy in (arena.get("enemies") as Array):
		enemies_state.append({
			"entity_id": int(enemy.entity_id),
			"x": float(enemy.position.x),
			"y": float(enemy.position.y),
			"health": float(enemy.health),
			"action_state": String(enemy.action_state),
			"phase_id": String(enemy.phase_id),
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
		"player": normalized_player,
		"enemies": enemies_state,
		"hazards": hazards_state,
	}


## Snapshot values must stay plain data for cross-session comparison: Big
## instances are duplicated per call, so identity comparison would flag every
## healthy pair. Object values reduce to their string form.
func _normalize(value: Variant) -> Variant:
	if value is Dictionary:
		var out: Dictionary = {}
		for key: String in (value as Dictionary).keys():
			out[key] = _normalize((value as Dictionary)[key])
		return out
	if value is Array:
		var list: Array = []
		for item: Variant in value as Array:
			list.append(_normalize(item))
		return list
	if value is Object:
		return str(value)
	return value


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


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
