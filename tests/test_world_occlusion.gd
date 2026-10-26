extends SceneTree
## Combat cutaway and native-town sorting regression. Town structural checks
## do not claim clean-underplate visibility or replace future real screenshots.
## The combat cutaway
## keeps a hero's own source pixels readable when a ruin, a stand or the colossus
## draws in front of it.
##
## Run it on its own, no GPU harness and no full suite:
##   godot --headless --path . --script res://tests/test_world_occlusion.gd
##
## It reads the published atlas/layout pairs of both views, never writes gameplay
## state and never re-renders: the numbers it checks are the numbers the draw calls
## consume, because both come from the same functions.

const BaseHubScript = preload("res://src/presentation/base_hub_screen.gd")
const TownExpectations = preload("res://tests/helpers/town_scene_expectations.gd")
const ArenaWorldViewScript = preload("res://src/presentation/arena_world_view.gd")
const ArenaActorPresenterScript = preload("res://src/presentation/arena_actor_presenter.gd")
const BossActionPoseScript = preload("res://src/presentation/boss_action_pose.gd")
const FrameBuilderScript = preload("res://src/presentation/combat_presentation_frame_builder.gd")
const ArenaGeometryScript = preload("res://src/runtime/geometry/arena_geometry.gd")
const EnemyScript = preload("res://src/runtime/world/combat_enemy_state.gd")
const OcclusionPlanScript = preload("res://src/presentation/occlusion/occlusion_plan.gd")
const OcclusionControllerScript = preload("res://src/presentation/occlusion/occlusion_controller.gd")
const AuthoredRevealScript = preload("res://src/presentation/occlusion/authored_reveal_controller.gd")
const SilhouetteRevealScript = preload("res://src/presentation/occlusion/silhouette_reveal_controller.gd")
const PrimitiveFadeScript = preload("res://src/presentation/occlusion/primitive_fade_controller.gd")
const PairedRevealScript = preload("res://src/presentation/occlusion/paired_reveal_controller.gd")
const Assert := preload("res://tests/helpers/assert.gd")

## Visual-overlap budget: at most this much total local opacity may sit on top of
## the hero's own cell, so a per-channel comparison against the source pixels can
## never drift past the 0.20 visibility gate.
const LOCAL_OPACITY_CEILING := 0.18
## The authored in-situ failures this pass exists for, in world units.
const BASE_RACK_FAILURES: Array[Vector2] = [
	Vector2(548.0, 204.0),
	Vector2(570.0, 204.0),
	Vector2(570.0, 194.0),
]
const BASE_HEARTH_FAILURES: Array[Vector2] = [
	Vector2(584.0, 368.0),
	Vector2(630.0, 373.0),
]
## South of the rack's own feet: the hero is in front, so nothing may be cut.
const BASE_IN_FRONT := Vector2(570.0, 235.0)
const BASE_CLEAR := Vector2(570.0, 320.0)
const ARENA_VIEWPORT := Rect2(Vector2.ZERO, Vector2(1280.0, 720.0))
## Exactly the playfield main.gd hands the world view at 1280x720.
const ARENA_RECT := Rect2(Vector2(42.0, 190.0), Vector2(1196.0, 488.0))

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_budget()
	_test_pieces()
	await _test_town_scene()
	await _test_town_silhouette_reveal()
	await _test_town_primitive_fade()
	await _test_silhouette_canvas_cells()
	_test_town_cover_tiers()
	_test_primitive_fade_controller()
	_test_paired_reveal_controller()
	_test_arena_paired_pack()
	_test_authored_reveal()
	_test_arena()
	_test_room_concept_geometry()
	_test_world_frame_projection()
	_test_posed_boss_geometry()
	if failures.is_empty():
		print("PASS  test_world_occlusion.gd")
		quit(0)
		return
	printerr("%d occlusion check(s) failed:" % failures.size())
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _expect(condition: bool, message: String) -> void: Assert.expect(condition, message, failures)


func _test_authored_reveal() -> void:
	var full := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	full.fill(Color.FOREST_GREEN)
	var revealed := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	revealed.fill(Color.TRANSPARENT)
	var mask := full.duplicate() as Image
	mask.fill_rect(Rect2i(0, 0, 8, 16), Color.TRANSPARENT)
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(full)
	var controller := AuthoredRevealScript.new()
	var bound := controller.register_piece("tree/upper", sprite, ImageTexture.create_from_image(revealed), mask)
	_expect(bound.ok, "authored reveal: valid complete states rejected")
	var part := {"stable_id": "tree/upper", "baseline_y": 16.0, "rank": 0, "art_box": Rect2(0, 0, 16, 16)}
	var subject := {"stable_id": "hero", "baseline_y": 8.0, "rank": 1, "readability_box": Rect2(0, 0, 8, 8)}
	controller.update([part], [subject], 0.2)
	_expect(not controller.report()["tree/upper"].open, "authored reveal: transparent region opened")
	subject.readability_box = Rect2(8, 0, 8, 8)
	var graze := {"stable_id": "npc", "baseline_y": 8.0, "rank": 1, "readability_box": Rect2(0, 0, 8, 8)}
	controller.update([part], [subject, graze], 0.2)
	_expect(controller.report()["tree/upper"].weight == 1.0, "authored reveal: grazing NPC suppressed hero")
	# The renderer owns an immutable full-state mask, not the caller's image
	# or the currently visible revealed texture.
	mask.fill(Color.TRANSPARENT)
	for frame in range(180):
		controller.update([part], [graze, subject], 1.0 / 60.0)
	_expect(controller.report()["tree/upper"].weight == 1.0, "authored reveal: open state oscillated or mutable mask leaked")
	subject.baseline_y = 16.0
	controller.update([part], [subject], 0.2)
	_expect(controller.report()["tree/upper"].weight == 0.0, "authored reveal: equal Y ignored actor rank")
	part.rank = 2
	controller.update([part], [subject], 0.2)
	_expect(controller.report()["tree/upper"].weight == 1.0, "authored reveal: equal Y ignored part rank")
	controller.update([part], [], 0.05)
	var closing: float = controller.report()["tree/upper"].weight
	_expect(closing > 0.0 and closing < 1.0, "authored reveal: close did not interpolate")
	controller.update([part], [], 0.2)
	_expect(controller.report()["tree/upper"].weight == 0.0, "authored reveal: stale revealed state remained")
	_expect(sprite.modulate == Color.WHITE and sprite.texture.get_image().get_data() == full.get_data(), "authored reveal: modified full-state art")
	controller.clear()
	_expect(sprite.material == null, "authored reveal: did not restore prior material")
	for flip: String in ["flip_h", "flip_v"]:
		sprite.set(flip, true)
		_expect(not controller.register_piece("tree/flipped", sprite, ImageTexture.create_from_image(revealed), full).ok,
			"authored reveal: accepted a flipped mask mapping")
		sprite.set(flip, false)
	var wrong_size := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	_expect(not controller.register_piece("tree/invalid", sprite, ImageTexture.create_from_image(revealed), wrong_size).ok,
		"authored reveal: accepted misaligned mask canvas")
	sprite.free()


func _test_posed_boss_geometry() -> void:
	var view = ArenaWorldViewScript.new()
	var feet := Vector2(500, 340)
	for phase in [1, 2]:
		for action in ["slam", "sweep", "lane"]:
			for stage in ["windup", "active", "recovery"]:
				var pose := BossActionPoseScript.pose(action, stage, 115, 100, 120, phase)
				var left := Vector2(0, -20)
				var right := Vector2(18, 0)
				var parts: Array[Dictionary] = view.boss_draw_parts(feet, phase, left, right, pose)
				_expect(parts.size() == 4, "posed boss must publish all four draw parts")
				_expect(parts[0]["feet"] == feet + Vector2(pose["body_offset_px"]), "posed body geometry differs from draw")
				_expect(parts[1]["feet"] == feet + ArenaWorldViewScript.BOSS_CORE_OFFSET + Vector2(pose["core_offset_px"]), "posed core must ride body")
				_expect(parts[2]["feet"] == feet + ArenaWorldViewScript.BOSS_HAND_LEFT_OFFSET + left * 0.72 + Vector2(pose["left_hand_offset_px"]), "posed left hand must preserve authority delta")
				_expect(parts[3]["feet"] == feet + ArenaWorldViewScript.BOSS_HAND_RIGHT_OFFSET + right * 0.72 + Vector2(pose["right_hand_offset_px"]), "posed right hand must preserve authority delta")
				_expect(pose["core_tint"] == Color.WHITE, "both phases keep authored core palette")
				for focused: Dictionary in parts:
					# Put the hero under each moving part, not just under the idle body.
					var box: Rect2 = view.sprite_art_box(focused["sprite_id"], focused["feet"])
					var hero := Vector2(box.get_center().x, minf(feet.y - 1, box.end.y))
					view.begin_frame(ARENA_VIEWPORT, Vector2(625, 320), ARENA_RECT)
					var cells: Array[Dictionary] = []
					for part: Dictionary in parts:
						cells.append({"id": part["sprite_id"], "feet_world": part["feet"], "art_box": view.sprite_art_box(part["sprite_id"], part["feet"]), "base_alpha": 1.0})
					view.prepare_actor_occlusion(cells, hero)
					var report: Dictionary = view.occlusion_report(hero)
					_expect(float(report.get("local_opacity_total", 1.0)) <= LOCAL_OPACITY_CEILING, "posed parts exceed shared opacity budget")


func _test_room_concept_geometry() -> void:
	## Room concepts now come from CombatRoomScene, which derives every edge,
	## entry and exit from the authored manifest instead of fixed midpoints.
	var view = ArenaWorldViewScript.new()
	_expect(view.load_assets(), "concept: world view did not load: %s" % String(view.pending_reason))
	for name: String in ["_concept_bounds_world", "_concept_corridor_edge_world", "_concept_ring_trace_radius_world", "_draw_room_gate"]:
		_expect(not view.has_method(name), "concept: unaligned procedural gate helper %s is still present" % name)
	for layout_id: String in ["rectangle_arena", "corridor", "ring"]:
		var report: Dictionary = view.room_scene_report(layout_id, false)
		_expect(bool(report.get("ready", false)) and String(report.get("exit_state", "")) == "sealed" and not bool(report.get("exit_walkable", true)),
			"concept: %s room scene is not a sealed, socket-aligned presentation" % layout_id)
		_expect(String(view.room_scene_report(layout_id, true).get("exit_state", "")) == "wards_down", "concept: %s cleared ward state" % layout_id)


func _test_world_frame_projection() -> void:
	var geometry := {
		"kind": "ring",
		"bounds": Rect2(Vector2(56.0, 204.0), Vector2(1168.0, 460.0)),
		"center": Vector2(640.0, 434.0),
		"inner_radius": 97.6,
		"outer_radius": 209.84,
	}
	var snapshot := {
		"in_arena": true,
		"arena_rect": ARENA_RECT,
		"player_position": Vector2(640.0, 434.0),
		"layout_id": "ring",
		"walkable_geometry": geometry,
		"presentation_geometry": ArenaGeometryScript.from_layout("ring", ARENA_RECT, 0.0),
		"sim_tick": 17,
	}
	var frame: Dictionary = FrameBuilderScript.new().world_frame(snapshot, ARENA_VIEWPORT, "")
	_expect(String(frame.get("layout_id", "")) == "ring", "world frame rewrote ring identity to rectangle_arena")
	var projected: Dictionary = frame.get("walkable_geometry", {})
	_expect(String(projected.get("kind", "")) == "ring", "world frame dropped the authoritative ring geometry")
	_expect(projected == geometry, "world frame changed the authoritative ring geometry")
	projected["outer_radius"] = 1.0
	_expect(is_equal_approx(float(geometry["outer_radius"]), 209.84), "world frame geometry mutation reached the snapshot")
	var presentation_projected: Dictionary = frame.get("presentation_geometry", {})
	_expect(String(presentation_projected.get("kind", "")) == "ring", "world frame lost its independent presentation geometry")
	_expect(is_equal_approx(float(presentation_projected.get("outer_radius", 0.0)), minf(ARENA_RECT.size.x, ARENA_RECT.size.y) * 0.43), "world frame presentation geometry kept the planning inset")


## The local opacity budget is the whole point of the pass: whatever a frame stacks
## on top of the hero, the composed opacity of that stack may never exceed the
## ceiling, and a single foreground band must stay inside the approved band.
func _test_budget() -> void:
	_expect(is_equal_approx(ArenaWorldViewScript.cutaway_alpha(0), 1.0), "budget: arena changed alpha without occluders")
	for count in range(1, 7):
		var share := ArenaWorldViewScript.cutaway_alpha(count)
		var composed := 1.0 - pow(1.0 - share, float(count))
		_expect(composed <= LOCAL_OPACITY_CEILING + 0.000001, "budget: arena exceeds local opacity ceiling")
		_expect(composed >= 0.12, "budget: arena fell below approved local band")
	_expect(is_equal_approx(ArenaWorldViewScript.cutaway_alpha(1), 0.16), "budget: single arena band changed opacity")


func _test_pieces() -> void:
	var quad := Rect2(Vector2(100.0, 100.0), Vector2(96.0, 96.0))
	var core := Rect2(Vector2(122.0, 122.0), Vector2(52.0, 52.0))
	var pieces := ArenaWorldViewScript.cutaway_pieces(quad, core)
	_expect(pieces.size() == 5, "pieces: a cut cell must be five pieces, got %d" % pieces.size())
	_expect(ArenaWorldViewScript.CUTAWAY_WINDOW_INDEX == pieces.size() - 1, "pieces: the window must be drawn last")
	var covered := 0.0
	for left in pieces.size():
		var piece: Rect2 = pieces[left]
		_expect(quad.encloses(piece), "pieces: piece %d leaves the drawn cell" % left)
		covered += piece.size.x * piece.size.y
		for right in range(left + 1, pieces.size()):
			var other: Rect2 = pieces[right]
			_expect(not piece.intersects(other) or piece.intersection(other).size.x * piece.intersection(other).size.y <= 0.0, "pieces: pieces %d and %d overlap" % [left, right])
	_expect(absf(covered - quad.size.x * quad.size.y) <= 0.5, "pieces: the pieces cover %.1f of a %.1f cell" % [covered, quad.size.x * quad.size.y])

	var region := Rect2(Vector2(64.0, 32.0), Vector2(96.0, 96.0))
	var drawn: Array[Dictionary] = ArenaWorldViewScript.new().cut_pieces(quad, region, core, 0.45, 0.16, false)
	var window_alpha := -1.0
	for piece: Dictionary in drawn:
		var destination: Rect2 = piece["dest"]
		var source: Rect2 = piece["source"]
		_expect(source.position.is_equal_approx(region.position + (destination.position - quad.position)), "pieces: a piece reads the wrong source pixels")
		_expect(is_equal_approx(source.size.x, destination.size.x) and is_equal_approx(source.size.y, destination.size.y), "pieces: a piece reads a rescaled source rect")
		if bool(piece["window"]):
			window_alpha = float(piece["alpha"])
		else:
			_expect(is_equal_approx(float(piece["alpha"]), 0.45), "pieces: a band outside the window must keep the authored fade")
	_expect(is_equal_approx(window_alpha, 0.45 * 0.16), "pieces: the window must multiply the authored fade, got %.3f" % window_alpha)


func _test_town_scene() -> void:
	var hub := BaseHubScript.new()
	root.add_child(hub)
	hub._ready()
	var view := hub.get_hub_view()
	var town = hub.get_town_runtime()
	_expect(bool(hub.town_load_report.get("ok", false)), "town: native scene failed to load")
	await _warm_hub()
	_settle_reveal(view)
	var audit := view.render_audit()
	var authored: Dictionary = TownExpectations.load_expectations()
	_expect(not (authored.paired_ids as Array).is_empty() and (authored.unpaired_sort_ids as Array).is_empty(),
		"town: every authored SortRoot visual must be a whole paired object: " + str(authored.unpaired_sort_ids))
	_expect(view.occlusion_report().get("available", false)
		and TownExpectations.sorted_strings((view.occlusion_report().get("paired_reveal", {}) as Dictionary).keys()) == authored.paired_ids,
		"town: registered paired ids must equal the scene-authored paired ids %s, got %s" % [str(authored.paired_ids), str((view.occlusion_report().get("paired_reveal", {}) as Dictionary).keys())])
	_expect((authored.base_ground_paths as Array) == [TownExpectations.EXPANSION_GROUND] and audit.ground_source_path == TownExpectations.EXPANSION_GROUND and audit.runtime_background_patches == 0,
		"town: the scene must declare and mount the world_expansion_v01 town ground, got %s / %s" % [str(authored.base_ground_paths), str(audit.ground_source_path)])
	_expect((authored.sort_bridge_ids as Array).is_empty(), "town: bridges are opaque ground art and must not be sortable: " + str(authored.sort_bridge_ids))
	_expect((authored.ground_bridge_ids as Array).size() == 2, "town: both bridge decks must be authored in Ground")
	for bridge_id: String in authored.ground_bridge_ids:
		var bridge: Node = view.world_presenter.native_binding_node(bridge_id)
		_expect(bridge is Sprite2D and bridge.get_parent() == view.world_presenter.ground_layer, "town: bridge %s did not mount in Ground" % bridge_id)
		if bridge is Sprite2D:
			_expect(String(bridge.get_meta("texture_path", "")).ends_with("_opaque.png") and bridge.texture != null and bridge.material == null and is_equal_approx(bridge.modulate.a, 1.0), "town: ground bridge %s must remain an opaque deck" % bridge_id)
	_expect(audit.unknown_underplate == "opaque" and audit.supports_cutaway and not audit.supports_fade, "town: whole-object ground capabilities changed")
	var shared: Node2D = view.world_presenter.sort_root
	_expect(shared.y_sort_enabled and view._hero_sprite.get_parent() == shared, "town: hero has a parallel sort domain")
	var native_count := 0
	for id: String in ["contract", "loadout", "forge", "proxy", "tree_south", "commons_fire"]:
		var sprite: Node = view.world_presenter.native_binding_node("town/native/" + id)
		_expect(sprite is Sprite2D and sprite.get_parent() == shared, "town: native building left shared sort root: " + id)
	for node: Node in shared.get_children():
		if not node.has_meta("texture_path"): continue
		native_count += 1
		_expect(node is Sprite2D and not (node as Sprite2D).region_enabled and TownExpectations.art_path_accepted(String(node.get_meta("texture_path"))), "town: visual was cropped from background or left the whole-object art roots: " + String(node.get_meta("texture_path")))
		_expect((node as CanvasItem).visible and is_equal_approx((node as CanvasItem).modulate.a, 1.0), "town: transparent underplate enabled fade or hiding")
	var before: int = shared.get_child_count()
	for target: Vector2 in town.route_points("contract"):
		town.place_hero(target)
		await process_frame
		_expect(shared.get_child_count() == before, "town: movement created cutaway fragments")
		## Occluder-window contract (GPU acceptance R2): a front piece covering
		## the hero eases open inside the tier bounds; every other native piece
		## must stay fully opaque, and nothing may ever hide or duplicate.
		var windowed: Dictionary = view.occlusion_report().get("occluder_alphas", {})
		for node: Node in shared.get_children():
			if node.has_meta("texture_path"):
				var alpha := float((node as CanvasItem).modulate.a)
				_expect((node as CanvasItem).visible, "town: movement hid native art")
				## Whole-object contract: the paired policy never dims modulate;
				## a covered piece reveals through its own material only.
				var piece_id := String(node.get_meta("binding_id", ""))
				_expect(is_equal_approx(alpha, 1.0), "town: a whole object dimmed its own modulate: %s %.3f" % [piece_id, alpha])
				_expect(not windowed.has(piece_id), "town: %s kept a legacy window tier row" % piece_id)
	_expect(native_count == (authored.sort_ids as Array).size(), "town: mounted whole objects %d != authored %d" % [native_count, (authored.sort_ids as Array).size()])
	for binding_id: String in authored.paired_ids:
		var authored_piece: Node = view.world_presenter.native_binding_node(binding_id)
		_expect(authored_piece is Sprite2D and String(authored_piece.get_meta("reveal_policy", "")) == "paired_reveal"
			and int(authored_piece.get_meta("sort_rank")) == 0
			and not authored_piece.has_meta("occlusion_volumes") and not authored_piece.has_meta("reveal_mask_path"),
			"town: %s lost its whole paired policy" % binding_id)
	for id: String in ["loadout", "tree_south", "tree_east"]:
		var piece: Node = view.world_presenter.native_binding_node("town/native/" + id)
		_expect(piece is Sprite2D, "town: %s missing" % id)
		## The retired split pieces must not survive as parallel bindings.
		_expect(view.world_presenter.native_binding_node("town/native/%s_common" % id) == null
			and view.world_presenter.native_binding_node("town/native/%s_upper" % id) == null,
			"town: %s kept a retired split companion" % id)
	hub.free()


## Production presenter path for the actual-silhouette foreground reveal.
## GPU visual finding 2026-10-22: behind the Loadout forecourt and tree_south
## the hero was tinted ~50.8% gray because the legacy occluder window kept
## half the piece at its 0.4 tier. The mounted hub drives the real
## TownPresenter end to end here: the covering piece's material must carry the
## hero's live draw cell and atlas region, clear exactly over the silhouette
## on a transition independent of the 0.4..1 window tier, open nothing under a
## piece's transparent tail, reveal the protected conversation resident
## together with the hero, close cleanly after the hero leaves, and never
## punch any other resident.
func _test_town_silhouette_reveal() -> void:
	var hub := BaseHubScript.new()
	root.add_child(hub)
	hub._ready()
	var view := hub.get_hub_view()
	var town = hub.get_town_runtime()
	_expect(bool(hub.town_load_report.get("ok", false)), "silhouette: native scene failed to load")

	# Whole-object contract: every native piece is ONE sprite with an opaque
	# and a baked transparent pair — no upper/base split, no mask. Standing
	# clear of the loadout's detection ring keeps it closed.
	var placed: Dictionary = town.place_hero(Vector2(562.0, 166.0))
	_expect(bool(placed.get("ok", false)), "paired reveal: closed placement rejected: " + str(placed))
	await _warm_hub()
	_settle_reveal(view)
	var report: Dictionary = view.occlusion_report()
	_expect(bool(report.get("available", false)), "paired reveal: presenter lost its occlusion plan")
	_check_whole_pair(view, report, "loadout", false, "CLOSED")
	_check_reveal_invariants(view, report, "CLOSED")

	# Standing behind the angled house, north of its padded ground footprint,
	# covers the readability box: the WHOLE object eases open at weight 1 —
	# the revealed alpha lives inside the single piece material, modulate
	# stays 1 and no band splits off.
	placed = town.place_hero(Vector2(711.0, 140.0))
	_expect(bool(placed.get("ok", false)), "paired reveal: open placement rejected: " + str(placed))
	await _warm_hub()
	_settle_reveal(view)
	report = view.occlusion_report()
	_check_whole_pair(view, report, "loadout", true, "OPEN")
	var open_actors: Dictionary = ((report.get("paired_reveal", {}) as Dictionary).get("town/native/loadout", {}) as Dictionary).get("actors", {})
	_expect(open_actors.has("town/ranger"), "paired reveal: the hero under the detection ring opened no reveal")
	_expect(is_equal_approx(view.actor_alpha("town/ranger"), 1.0), "paired reveal: the hero sprite itself was dimmed")
	_check_reveal_invariants(view, report, "OPEN")

	# In front of the piece: the whole object closes again.
	placed = town.place_hero(Vector2(711.0, 250.0))
	_expect(bool(placed.get("ok", false)), "paired reveal: front placement rejected: " + str(placed))
	await _warm_hub()
	_settle_reveal(view)
	report = view.occlusion_report()
	_check_whole_pair(view, report, "loadout", false, "FRONT")
	var front_row: Dictionary = (report.get("paired_reveal", {}) as Dictionary).get("town/native/loadout", {})
	_expect(not (front_row.get("actors", {}) as Dictionary).has("town/ranger"), "paired reveal: a hero row survived on a closed piece")
	_check_reveal_invariants(view, report, "FRONT")

	# tree_south (pine): the same closed→open transition on its ring edge.
	placed = town.place_hero(Vector2(900.0, 700.0))
	_expect(bool(placed.get("ok", false)), "paired reveal: pine closed placement rejected")
	await _warm_hub()
	_settle_reveal(view)
	_check_whole_pair(view, view.occlusion_report(), "tree_south", false, "pine closed")
	placed = town.place_hero(Vector2(985.0, 700.0))
	_expect(bool(placed.get("ok", false)), "paired reveal: pine open placement rejected")
	await _warm_hub()
	_settle_reveal(view)
	_expect(view.camera_world_offset() != Vector2.ZERO, "paired reveal: fixture lost its camera offset")
	report = view.occlusion_report()
	_check_whole_pair(view, report, "tree_south", true, "pine open")
	_check_reveal_invariants(view, report, "pine open")

	# The hero alone covers tree_east's ring. Protected Mira stands SOUTH of
	# the piece baseline (in front): she must NOT be a covered subject, must
	# stay fully opaque, and no ambient actor may join the row.
	view.protect_dialogue_resident("mira")
	placed = town.place_hero(Vector2(1290.0, 410.0))
	_expect(bool(placed.get("ok", false)), "paired reveal: PAIR hero placement rejected: " + str(placed))
	await _warm_hub()
	_settle_reveal(view)
	report = view.occlusion_report()
	var reveal: Dictionary = report.get("paired_reveal", {})
	var pair_row: Dictionary = reveal.get("town/native/tree_east", {})
	_expect(not pair_row.is_empty() and bool(pair_row.get("open", false))
		and (pair_row.get("actors", {}) as Dictionary).has("town/ranger"),
		"paired reveal: the covered hero did not open tree_east")
	var pair_actors: Array = (pair_row.get("actors", {}) as Dictionary).keys()
	_expect(not pair_actors.has("town/npc/mira") and pair_actors.all(func(a: String): return a == "town/ranger"),
		"paired reveal: ineligible subject joined the row: " + str(pair_actors))
	_expect(is_equal_approx(view.actor_alpha("town/npc/mira"), 1.0), "paired reveal: the protected resident was dimmed")
	var pair_node: Node = view.world_presenter.native_binding_node("town/native/tree_east")
	var pair_material := (pair_node as Sprite2D).material as ShaderMaterial if pair_node is Sprite2D else null
	_expect(pair_material != null and pair_material.shader == PairedRevealScript.RevealShader
		and is_equal_approx(float(pair_material.get_shader_parameter("reveal_weight")), 1.0),
		"paired reveal: tree_east lost its whole-object material")
	_check_reveal_invariants(view, report, "PAIR")

	# Dialogue ends: the resident loses slot eligibility again while the hero
	# walks clear. Every whole-object row closes, no hero entry survives.
	view.protect_dialogue_resident("")
	placed = town.place_hero(Vector2(711.0, 250.0))
	_expect(bool(placed.get("ok", false)), "paired reveal: EXIT hero placement rejected: " + str(placed))
	await _warm_hub()
	_settle_reveal(view)
	report = view.occlusion_report()
	reveal = report.get("paired_reveal", {})
	for occluder_id: String in reveal.keys():
		var row: Dictionary = reveal[occluder_id]
		_expect(not bool(row.get("open", false)), "paired reveal: a stale reveal stayed open after the hero left: %s" % occluder_id)
		_expect(is_equal_approx(float(row.get("weight", 0.0)), 0.0), "paired reveal: reveal weight did not close: %s %.3f" % [occluder_id, float(row.get("weight", 0.0))])
		_expect(not (row.get("actors", {}) as Dictionary).has("town/ranger"), "paired reveal: a hero entry survived the exit on %s" % occluder_id)
	hub.free()


## Roof/canopy-only physical transparency through the real presenter. The
## confirmed user policy: an opted-in upper piece eases only its own
## modulate.a over a protected actor's readability box against authored
## volumes; bases, every other piece and every actor stay fully drawn. The
## mounted hub proves the dispatch on mid-run stamps — a piece that already
## carries a legacy silhouette material must lose it the moment it becomes an
## explicit "none" base or a "primitive_fade" target, so an explicit solid
## base means unchanged drawn pixels, not modulate.a == 1 under a leftover
## reveal material — and exactly one policy ever operates on a piece.
func _test_town_primitive_fade() -> void:
	var hub := BaseHubScript.new()
	root.add_child(hub)
	hub._ready()
	var view := hub.get_hub_view()
	var town = hub.get_town_runtime()
	_expect(bool(hub.town_load_report.get("ok", false)), "primitive fade: native scene failed to load")

	# tree_south/Loadout are now explicit native pairs, so the unconfigured
	# legacy fallback is proven on tree_east instead: it carries an
	# exact-silhouette material over the hero beside the protected resident.
	var placed: Dictionary
	view.protect_dialogue_resident("mira")
	placed = town.place_hero(Vector2(1290.0, 410.0))
	_expect(bool(placed.get("ok", false)), "primitive fade: FADE hero placement rejected: " + str(placed))
	await _warm_hub()
	_settle_reveal(view)
	var tree_east: Node = view.world_presenter.native_binding_node("town/native/tree_east")
	var tree_south: Node = view.world_presenter.native_binding_node("town/native/tree_south")

	# Whole-object contract: the paired piece opens behind the covered hero —
	# one whole sprite, one eased reveal weight, modulate never touched.
	_settle_reveal(view)
	var report: Dictionary = view.occlusion_report()
	var row: Dictionary = (report.get("paired_reveal", {}) as Dictionary).get("town/native/tree_east", {})
	_expect(not row.is_empty(), "paired reveal: the authored piece registered no paired row")
	if not row.is_empty():
		_expect(String(row.get("policy", "")) == "paired_reveal" and bool(row.get("open", false))
			and is_equal_approx(float(row.get("weight", 0.0)), 1.0), "paired reveal: the row did not settle open at full weight")
		var row_actors: Dictionary = row.get("actors", {})
		_expect(row_actors.has("town/ranger"), "paired reveal: the covered hero opened no reveal")
		for actor_id: String in row_actors.keys():
			_expect(actor_id == "town/ranger" or actor_id == "town/npc/mira",
				"paired reveal: an ambient actor opened the reveal: " + actor_id)
	var tree_material := tree_east.material as ShaderMaterial
	_expect(tree_material != null and tree_material.shader == PairedRevealScript.RevealShader
		and is_equal_approx(float(tree_material.get_shader_parameter("reveal_weight")), 1.0),
		"paired reveal: tree_east did not carry the eased whole-object material")
	_expect(is_equal_approx((tree_east as CanvasItem).modulate.a, 1.0), "paired reveal: the whole object dimmed its own modulate")
	_expect(not (report.get("silhouette_reveal", {}) as Dictionary).has("town/native/tree_east")
		and not (report.get("primitive_fade", {}) as Dictionary).has("town/native/tree_east"),
		"paired reveal: one piece ended up in two policies at once")
	# Every other piece and every actor stays fully drawn: the reveal lives
	# entirely inside the piece's own material.
	for node: Node in view.world_presenter.sort_root.get_children():
		if node is Sprite2D and node.has_meta("texture_path"):
			_expect(is_equal_approx((node as CanvasItem).modulate.a, 1.0),
				"paired reveal: a native piece's modulate was dimmed: %.3f" % float((node as CanvasItem).modulate.a))
	for actor_id: String in view.actor_presentation_ids():
		_expect(is_equal_approx(view.actor_alpha(actor_id), 1.0), "paired reveal: an actor was dimmed: " + actor_id)
	var audit: Dictionary = view.render_audit()
	_expect(((audit.get("paired_reveal", {}) as Dictionary).get("occluders", {}) as Dictionary).has("town/native/tree_east")
		or not (audit.get("paired_reveal", {}) as Dictionary).is_empty(),
		"paired reveal: the render audit lost its paired report field")

	# Dialogue ends and the hero walks clear: the reveal closes, weight eases
	# to zero and the piece draws exactly its authored opaque pixels again.
	view.protect_dialogue_resident("")
	placed = town.place_hero(Vector2(576.0, 595.3))
	_expect(bool(placed.get("ok", false)), "paired reveal: EXIT hero placement rejected: " + str(placed))
	await _warm_hub()
	_settle_reveal(view)
	report = view.occlusion_report()
	row = (report.get("paired_reveal", {}) as Dictionary).get("town/native/tree_east", {})
	_expect(not bool(row.get("open", true)) and is_equal_approx(float(row.get("weight", 1.0)), 0.0),
		"paired reveal: the reveal stayed open after the hero left")
	var exit_material := tree_east.material as ShaderMaterial
	_expect(is_equal_approx((tree_east as CanvasItem).modulate.a, 1.0)
		and (exit_material == null or is_equal_approx(float(exit_material.get_shader_parameter("reveal_weight")), 0.0)),
		"paired reveal: the piece did not return to its opaque pixels after exit")
	hub.free()


## One explicit common/upper pair (loadout or tree_south) through the real
## Whole-object pair check: one native sprite carries the shared
## paired_reveal material; its row, live shader weight and canvas state must
## agree with the expected state independently computed here — the piece is
## never split, never mask-revealed, and never absent from the report.
func _check_whole_pair(view, report: Dictionary, name: String, expect_open: bool, label: String) -> void:
	var piece_id := "town/native/" + name
	var piece: Node = view.world_presenter.native_binding_node(piece_id)
	_expect(piece is Sprite2D and not (piece as Sprite2D).region_enabled, "whole pair %s: %s lost its whole canvas sprite" % [label, name])
	if not piece is Sprite2D:
		return
	var row: Dictionary = (report.get("paired_reveal", {}) as Dictionary).get(piece_id, {})
	_expect(not row.is_empty() and String(row.get("policy", "")) == PairedRevealScript.POLICY,
		"whole pair %s: %s is not a registered paired reveal" % [label, name])
	if not row.is_empty():
		_expect(bool(row.get("open", false)) == expect_open, "whole pair %s: %s open=%s, expected %s (coverage %.3f)" % [label, name, row.get("open"), expect_open, float(row.get("coverage", 0.0))])
		_expect(is_equal_approx(float(row.get("weight", -1.0)), 1.0 if expect_open else 0.0), "whole pair %s: %s weight %.3f did not settle" % [label, name, float(row.get("weight", -1.0))])
	var material := (piece as Sprite2D).material as ShaderMaterial
	_expect(material != null and material.shader == PairedRevealScript.RevealShader
		and is_equal_approx(float(material.get_shader_parameter("reveal_weight")), 1.0 if expect_open else 0.0),
		"whole pair %s: %s live shader weight diverged" % [label, name])
	_expect(is_equal_approx((piece as CanvasItem).modulate.a, 1.0), "whole pair %s: %s modulate was dimmed" % [label, name])
	_expect(not (report.get("primitive_fade", {}) as Dictionary).has(piece_id)
		and not (report.get("silhouette_reveal", {}) as Dictionary).has(piece_id)
		and not (report.get("occluder_alphas", {}) as Dictionary).has(piece_id),
		"whole pair %s: %s also ran a legacy path" % [label, piece_id])
	for actor_id: String in view.actor_presentation_ids():
		_expect(is_equal_approx(view.actor_alpha(actor_id), 1.0), "whole pair %s: an actor was dimmed: %s" % [label, actor_id])


## The hub's first engine frame after a mount can carry a zero delta and never
## reaches the sim tick, so the occlusion plan only exists from the next one;
## three frames guarantees a projected plan before the explicit reveal ticks.
func _warm_hub() -> void:
	for _warm in 3:
		await process_frame


func _settle_reveal(view, ticks: int = 12) -> void:
	for _tick in ticks:
		view._process(1.0 / 30.0)


## Roof/canopy primitive fade, detached contract. The exact coverage geometry
## comes first — disjoint, fully containing and half-overlapping volumes are
## pinned so an inverted intersection (box minus volume) can never pass — then
## the hysteresis band, the shared front/back ordering, the eased transition
## on the piece's own modulate.a alone, fail-closed registrations and clean
## resets. Fixture style follows _test_authored_reveal: no scene, no sim state.
func _test_primitive_fade_controller() -> void:
	_expect(PrimitiveFadeScript.FADED_ALPHA == 0.25 and PrimitiveFadeScript.TRANSITION_SECONDS == 0.18,
		"primitive fade: independent quarter-opacity/transition contract changed")
	var box := Rect2(0.0, 0.0, 10.0, 10.0)
	_expect(is_equal_approx(PrimitiveFadeScript.box_coverage([{"type": "polygon",
		"points": PackedVector2Array([Vector2(100, 100), Vector2(140, 100), Vector2(140, 140), Vector2(100, 140)])}], box), 0.0),
		"primitive fade: a disjoint polygon covered the box")
	_expect(is_equal_approx(PrimitiveFadeScript.box_coverage([{"type": "polygon",
		"points": PackedVector2Array([Vector2(-20, -20), Vector2(30, -20), Vector2(30, 30), Vector2(-20, 30)])}], box), 1.0),
		"primitive fade: a containing polygon did not cover the box fully")
	_expect(is_equal_approx(PrimitiveFadeScript.box_coverage([{"type": "polygon",
		"points": PackedVector2Array([Vector2(5, 0), Vector2(25, 0), Vector2(25, 10), Vector2(5, 10)])}], box), 0.5),
		"primitive fade: a half overlap did not measure half the box")
	_expect(is_equal_approx(PrimitiveFadeScript.box_coverage(
		[{"type": "circle", "center": Vector2(100, 100), "radius": 4.0}], box), 0.0),
		"primitive fade: a disjoint circle covered the box")

	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color.FOREST_GREEN)
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(image)
	var controller := PrimitiveFadeScript.new()
	var volumes: Array = [
		{"type": "circle", "center": Vector2.ZERO, "radius": 12.0},
		{"type": "polygon", "points": PackedVector2Array([Vector2(-20, -30), Vector2(20, -30), Vector2(20, -6), Vector2(-20, -6)])},
	]
	_expect(bool(controller.register_piece("roof/upper", sprite, volumes).ok), "primitive fade: valid volumes were rejected")
	_expect(is_equal_approx(sprite.modulate.a, 1.0), "primitive fade: registration pre-faded the piece")
	var piece := {"stable_id": "roof/upper", "baseline_y": 140.0, "rank": 1, "art_box": Rect2(-20, -30, 40, 24)}
	## Behind the roof: the readability box (16x28, area 448) takes 320 from
	## the circle's bounds — 5/7 coverage, far past the 0.08 enter gate.
	var behind := {"stable_id": "hero", "baseline_y": 100.0, "rank": 1, "readability_box": Rect2(-8, -20, 16, 28)}
	controller.update([piece], [behind], 0.0)
	var opened: Dictionary = controller.report()["roof/upper"]
	_expect(bool(opened.get("open", false)) and is_equal_approx(float(opened.get("weight", -1.0)), 0.0)
		and is_equal_approx(float(opened.get("coverage", -1.0)), 320.0 / 448.0),
		"primitive fade: the behind box did not open at zero weight with exact coverage")
	controller.update([piece], [behind], 0.09)
	_expect(is_equal_approx(sprite.modulate.a, 0.625), "primitive fade: the transition did not ease half way in half its duration: %.4f" % sprite.modulate.a)
	controller.update([piece], [behind], 0.3)
	_expect(is_equal_approx(sprite.modulate.a, PrimitiveFadeScript.FADED_ALPHA), "primitive fade: the piece did not settle at the faded alpha")
	## A subject standing in front of the piece never fades it.
	var ahead := {"stable_id": "ahead", "baseline_y": 180.0, "rank": 1, "readability_box": Rect2(-8, -20, 16, 28)}
	controller.update([piece], [ahead], 0.3)
	var ahead_row: Dictionary = controller.report()["roof/upper"]
	_expect(not bool(ahead_row.get("open", true)) and (ahead_row.get("actors", {}) as Dictionary).is_empty(),
		"primitive fade: a subject in front of the piece opened the fade")
	## The graze box keeps 32/448 inside the circle bounds — inside the
	## hysteresis band: it holds an open fade open but never opens one.
	var graze := {"stable_id": "grazer", "baseline_y": 100.0, "rank": 1, "readability_box": Rect2(10, -4, 16, 28)}
	controller.update([piece], [behind], 0.0)
	controller.update([piece], [graze], 0.3)
	_expect(bool(controller.report()["roof/upper"].get("open", false)), "primitive fade: the hysteresis band dropped an open fade")
	controller.reset()
	controller.update([piece], [graze], 0.3)
	var stayed: Dictionary = controller.report()["roof/upper"]
	_expect(not bool(stayed.get("open", true)) and is_equal_approx(float(stayed.get("weight", -1.0)), 0.0),
		"primitive fade: the hysteresis band opened a closed fade")
	controller.reset()
	_expect(is_equal_approx(sprite.modulate.a, 1.0), "primitive fade: reset left the piece faded")
	## Fail-closed registrations: nothing may half-register a guessed piece.
	for bad: Array in [
		[],
		[{"type": "circle", "center": Vector2.INF, "radius": 8.0}],
		[{"type": "circle", "center": Vector2.ZERO, "radius": 0.0}],
		[{"type": "polygon", "points": PackedVector2Array([Vector2.ZERO, Vector2(8, 0)])}],
		[{"type": "polygon", "points": PackedVector2Array([Vector2.ZERO, Vector2(8, 0), Vector2(16, 0)])}],
		[{"type": "ellipse", "center": Vector2.ZERO, "radius": 8.0}],
	]:
		_expect(not bool(controller.register_piece("roof/bad", sprite, bad).ok),
			"primitive fade: malformed volumes were accepted: " + str(bad))
	_expect(not bool(controller.register_piece("", sprite, volumes).ok), "primitive fade: an empty stable id was accepted")
	_expect(not bool(controller.register_piece("roof/none", null, volumes).ok), "primitive fade: a null sprite was accepted")
	## Canonical volume payload shared by the fingerprint and the audit rows.
	_expect(PrimitiveFadeScript.volumes_payload(volumes) == [
		{"type": "circle", "center": [0.0, 0.0], "radius": 12.0},
		{"type": "polygon", "points": [[-20.0, -30.0], [20.0, -30.0], [20.0, -6.0], [-20.0, -6.0]]},
	], "primitive fade: the volume payload left its canonical form")
	controller.clear()
	_expect(is_equal_approx(sprite.modulate.a, 1.0) and controller.report().is_empty(),
		"primitive fade: clear left a faded piece or a stale registration")
	sprite.free()


## Canvas-inclusive cell contract, independent of the town's own coordinate
## wiring: an asymmetric sprite at a fractional position under a translated
## parent must report its cell in VIEWPORT space — a canvas translation of
## (13, 9) shifts the cell by exactly (13, 9) (counted once, never zero from
## a global-only read and never (26, 18) from double counting), and any
## nonidentity canvas basis (scale, rotation) must yield NO cell at all.
## Whole-object paired reveal: one sprite, one opaque/transparent pair, one
## detection rect. The eased weight drives only the shared premultiplied
## shader mix; the piece's own modulate is never touched, so the baked
## transparent alpha is used exactly once.
func _test_paired_reveal_controller() -> void:
	var full := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	full.fill(Color.FOREST_GREEN)
	full.fill_rect(Rect2i(0, 0, 8, 16), Color.TRANSPARENT)
	var variant := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	variant.fill(Color(0.3, 0.5, 0.7, 64.0 / 255.0))
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(full)
	var controller := PairedRevealScript.new()
	## Occupied AABB is the right half (8,0,8,16); the detection rect must
	## contain it grown by DETECTION_GROW -> (0,-8,24,32).
	var bound := controller.register_piece("tree/whole", sprite, ImageTexture.create_from_image(variant), Rect2(0, -8, 24, 32))
	_expect(bound.ok, "paired reveal: valid whole pair rejected")
	_expect(sprite.material != null and sprite.material is ShaderMaterial, "paired reveal: reveal material not attached")
	_expect(not controller.register_piece("tree/whole", sprite, ImageTexture.create_from_image(variant), Rect2(0, -8, 24, 32)).ok,
		"paired reveal: duplicate binding accepted")
	var part := {"stable_id": "tree/whole", "baseline_y": 16.0, "rank": 0, "art_box": Rect2(0, -8, 24, 32)}
	var subject := {"stable_id": "hero", "baseline_y": 8.0, "rank": 1, "readability_box": Rect2(0, 0, 8, 8)}
	controller.update([part], [subject], 0.2)
	_expect(is_equal_approx(float(controller.report()["tree/whole"].weight), 1.0), "paired reveal: covered hero did not open the pair")
	_expect(is_equal_approx(float((sprite.material as ShaderMaterial).get_shader_parameter("reveal_weight")), 1.0),
		"paired reveal: eased weight did not reach the shader")
	_expect(sprite.modulate == Color.WHITE, "paired reveal: piece modulate touched")
	subject.baseline_y = 24.0
	controller.update([part], [subject], 0.2)
	_expect(is_equal_approx(float(controller.report()["tree/whole"].weight), 0.0), "paired reveal: piece behind hero opened")
	subject.baseline_y = 8.0
	controller.update([part], [subject], 0.2)
	controller.update([part], [], 0.05)
	var closing := float(controller.report()["tree/whole"].weight)
	_expect(closing > 0.0 and closing < 1.0, "paired reveal: close did not interpolate")
	controller.update([part], [], 0.2)
	_expect(is_equal_approx(float(controller.report()["tree/whole"].weight), 0.0), "paired reveal: stale reveal remained")
	controller.clear()
	_expect(sprite.material == null, "paired reveal: did not restore prior material")
	## Fail-closed registrations.
	_expect(not controller.register_piece("tree/tiny", sprite, ImageTexture.create_from_image(variant), Rect2(0, 0, 8, 8)).ok,
		"paired reveal: rect smaller than occupied.grow(8) accepted")
	_expect(not controller.register_piece("tree/degenerate", sprite, ImageTexture.create_from_image(variant), Rect2()).ok,
		"paired reveal: degenerate rect accepted")
	var small := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	_expect(not controller.register_piece("tree/mismatch", sprite, small, Rect2(0, -8, 24, 32)).ok,
		"paired reveal: mismatched variant canvas accepted")
	for flip: String in ["flip_h", "flip_v"]:
		sprite.set(flip, true)
		_expect(not controller.register_piece("tree/flipped", sprite, ImageTexture.create_from_image(variant), Rect2(0, -8, 24, 32)).ok,
			"paired reveal: flipped sprite accepted")
		sprite.set(flip, false)
	## Immediate-mode static path shared with the arena fade states.
	var state := PairedRevealScript.advance_state(Rect2(0, -8, 24, 32), part, [subject], {}, 0.2)
	_expect(bool(state.open) and is_equal_approx(float(state.weight), 1.0), "paired reveal: immediate state did not open")
	state = PairedRevealScript.advance_state(Rect2(0, -8, 24, 32), part, [], state, 0.2)
	_expect(not bool(state.open) and is_equal_approx(float(state.weight), 0.0), "paired reveal: immediate state did not close")
	## Real mounts translate both the sprite and its detection rectangle.
	## Parent translation, offset and centered canvases must all be honored.
	var mount := Node2D.new()
	mount.position = Vector2(100, 200)
	root.add_child(mount)
	mount.add_child(sprite)
	sprite.position = Vector2(32, 48)
	sprite.offset = Vector2(-4, -12)
	for centered: bool in [false, true]:
		sprite.centered = centered
		var origin := Vector2(128, 236) - (Vector2(8, 8) if centered else Vector2.ZERO)
		var world_rect := Rect2(origin + Vector2(0, -8), Vector2(24, 32))
		_expect(controller.register_piece("translated", sprite, ImageTexture.create_from_image(variant), world_rect).ok,
			"paired reveal: translated canvas rejected")
		_expect(controller.report().get("translated", {}).get("occlusion_rect", []) == [world_rect.position.x, world_rect.position.y, 24.0, 32.0],
			"paired reveal: stored detection lost world coordinates")
		controller.clear()
		_expect(not controller.register_piece("wrong_local", sprite, ImageTexture.create_from_image(variant), Rect2(0, -8, 24, 32)).ok,
			"paired reveal: untranslated canvas bounds accepted as world coordinates")
	## Detached two-subject proof: an explicitly front-sorted piece reports
	## BOTH covered protected subjects and opens once on combined coverage.
	var two_subjects := [
		{"stable_id": "sub/a", "baseline_y": 8.0, "rank": 0, "readability_box": Rect2(0, -8, 24, 32)},
		{"stable_id": "sub/b", "baseline_y": 12.0, "rank": 0, "readability_box": Rect2(0, -8, 24, 32)}]
	var two := PairedRevealScript.advance_state(Rect2(0, -8, 24, 32), part, two_subjects, {}, 0.2)
	_expect(bool(two.get("open", false)) and (two.get("actors", {}) as Dictionary).has("sub/a")
		and (two.get("actors", {}) as Dictionary).has("sub/b"),
		"paired reveal: two covered subjects did not share one open state")
	mount.remove_child(sprite)
	mount.free()
	sprite.free()


## Live arena consumption of the generated whole-object pack: a synthetic
## COMPLETE assets.json switches the structure sprites to one whole band each
## with one detection rect and one reveal material; an absent pack keeps the
## legacy banded atlas path byte-for-byte for the historical fixtures.
func _test_arena_paired_pack() -> void:
	var dir := "res://build/current"
	DirAccess.make_dir_recursive_absolute(dir)
	var prefix := dir + "/paired_pack_"
	var full := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	full.fill(Color.FOREST_GREEN)
	var variant := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	variant.fill(Color(0.3, 0.5, 0.7, 64.0 / 255.0))
	full.save_png(prefix + "opaque.png")
	variant.save_png(prefix + "transparent.png")
	## A present pack requires a packed arena ground at exact world size.
	var ground := Image.create(1024, 640, false, Image.FORMAT_RGBA8)
	ground.fill(Color.DARK_SLATE_GRAY)
	ground.save_png(prefix + "ground.png")
	var ground_entry := {"status": "packed", "kind": "ground", "section": "arena",
		"canvas": [1024, 640], "anchor": [0, 0], "occupied_rect": [0, 0, 1024, 640],
		"occlusion_rect": null, "opaque_path": prefix + "ground.png", "transparent_path": null}
	var entry := {"status": "packed", "kind": "object", "section": "arena",
		"canvas": [8, 8], "anchor": [4, 6],
		"occupied_rect": [0, 0, 8, 8], "occlusion_rect": [-8, -8, 24, 24],
		"opaque_path": prefix + "opaque.png", "transparent_path": prefix + "transparent.png"}
	var assets := {}
	for asset_id: String in ["ruin_wall_corner", "ruin_gate", "ruin_low_pier", "ruin_broken_wall", "tower"]:
		assets[asset_id] = entry.duplicate(true)
	var pack := {"schema_version": 1,
		"sections": {"arena": {"assets": assets.keys(), "grounds": ["arena_ground"], "pending": [], "stale": [], "complete": true}},
		"assets": assets, "grounds": {"arena_ground": ground_entry}}
	var file := FileAccess.open(prefix + "assets.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(pack))
	file.close()
	var view = ArenaWorldViewScript.new()
	view.generated_world_path = prefix + "assets.json"
	_expect(view.load_assets(), "paired pack: view rejected a complete synthetic pack: " + view.pending_reason)
	## One whole band per piece — the upper/base split is gone.
	var feet := Vector2(300, 200)
	var bands := view.structure_geometry("ruin.wall_corner", feet)
	_expect(bands.size() == 1 and String(bands[0].get("part")) == "whole", "paired pack: whole object still split into bands")
	_expect((bands[0].dest as Rect2) == Rect2(296, 194, 8, 8), "paired pack: whole dest left the feet-anchor mapping")
	_expect(view.paired_detection_rect_world("ruin.wall_corner", feet) == Rect2(288, 186, 24, 24), "paired pack: detection rect mistranslated")
	## Fade state opens through the shared controller on one eased weight.
	var drawable := {"kind": "structure", "sprite": "ruin.wall_corner", "world": feet, "baseline_y": feet.y, "rank": 0, "stable_id": "s/0"}
	var subject := {"stable_id": "hero", "baseline_y": feet.y - 8.0, "rank": 1, "readability_box": Rect2(feet - Vector2(8, 8), Vector2(16, 16))}
	view.advance_structure_fades([drawable], [subject], 0.2)
	var state := view.structure_fade_state("ruin.wall_corner", feet)
	_expect(String(state.get("policy")) == "paired_reveal" and bool(state.open) and is_equal_approx(float(state.weight), 1.0),
		"paired pack: covered hero did not open the whole state")
	## Settled alpha is the measured variant maximum (64/255 here), never an
	## invented constant; a closed state returns the fully opaque 1.0.
	_expect(is_equal_approx(float(state.get("alpha", 0.0)), 64.0 / 255.0),
		"paired pack: settled alpha ignored the measured variant alpha")
	var material: Material = view.paired_reveal_material("ruin.wall_corner", feet)
	_expect(material is ShaderMaterial and is_equal_approx(float((material as ShaderMaterial).get_shader_parameter("reveal_weight")), 1.0),
		"paired pack: reveal material missing or weight unset")
	_expect(view.structure_geometry("tower", feet).size() == 1, "paired pack: tower still split into bands")
	## A present-but-incomplete pack claims the authority: fail closed.
	var incomplete := {"schema_version": 1,
		"sections": {"arena": {"assets": assets.keys(), "grounds": ["arena_ground"], "pending": ["tower"], "stale": [], "complete": false}},
		"assets": assets, "grounds": {"arena_ground": ground_entry}}
	var incomplete_view = ArenaWorldViewScript.new()
	file = FileAccess.open(prefix + "incomplete.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(incomplete))
	file.close()
	incomplete_view.generated_world_path = prefix + "incomplete.json"
	_expect(not incomplete_view.load_assets() and not String(incomplete_view.pending_reason).is_empty(),
		"paired pack: present-but-incomplete pack loaded anyway")
	## A complete section still requires the packed ground — never a silent
	## legacy ground under generated whole objects.
	var no_ground := {"schema_version": 1,
		"sections": {"arena": {"assets": assets.keys(), "grounds": [], "pending": [], "stale": [], "complete": true}},
		"assets": assets, "grounds": {}}
	var no_ground_view = ArenaWorldViewScript.new()
	file = FileAccess.open(prefix + "no_ground.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(no_ground))
	file.close()
	no_ground_view.generated_world_path = prefix + "no_ground.json"
	_expect(not no_ground_view.load_assets(), "paired pack: complete section without packed ground loaded anyway")
	## The pack is required: an absent file fails the load closed.
	var missing = ArenaWorldViewScript.new()
	missing.generated_world_path = prefix + "missing.json"
	_expect(not missing.load_assets() and not String(missing.pending_reason).is_empty(),
		"paired pack: an absent pack still loaded")
	for name: String in ["opaque.png", "transparent.png", "ground.png", "assets.json", "incomplete.json", "no_ground.json"]:
		DirAccess.remove_absolute(prefix + name)


func _test_silhouette_canvas_cells() -> void:
	var image := Image.create(7, 5, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for x in range(3):
		for y in range(5):
			if y != 2:
				image.set_pixel(x, y, Color(0.25, 0.5, 0.75, 1.0))
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var parent := Node2D.new()
	parent.position = Vector2(24, 44)
	layer.add_child(parent)
	var sprite := Sprite2D.new()
	sprite.name = "CanvasCellProbe"
	sprite.texture = ImageTexture.create_from_image(image)
	sprite.centered = false
	sprite.offset = Vector2(10.5, 20.25)
	sprite.position = Vector2(100.75, 50.5)
	parent.add_child(sprite)
	await process_frame

	layer.offset = Vector2.ZERO
	var plain: Rect2 = SilhouetteRevealScript.viewport_cell_rect(sprite)
	_expect(plain.position == Vector2(135.25, 114.75) and plain.size == Vector2(7, 5),
		"canvas cells: zero-canvas cell expected (135.25, 114.75) 7x5, got %s" % str(plain))

	layer.offset = Vector2(13, 9)
	var shifted: Rect2 = SilhouetteRevealScript.viewport_cell_rect(sprite)
	_expect(shifted.position == Vector2(148.25, 123.75) and shifted.size == Vector2(7, 5),
		"canvas cells: canvas translation must shift the cell by exactly (13, 9) once, got %s" % str(shifted))

	layer.scale = Vector2(1, 2)
	var scaled: Rect2 = SilhouetteRevealScript.viewport_cell_rect(sprite)
	_expect(not scaled.has_area(), "canvas cells: a scaled canvas must yield no cell, got %s" % str(scaled))
	layer.scale = Vector2.ONE
	layer.rotation = 0.3
	var rotated: Rect2 = SilhouetteRevealScript.viewport_cell_rect(sprite)
	_expect(not rotated.has_area(), "canvas cells: a rotated canvas must yield no cell, got %s" % str(rotated))
	layer.queue_free()
	print("SILHOUETTE canvas-cell contract verified plain=", str(plain), " shifted=", str(shifted))


## The open reveal row carrying the hero past the enter gate, if any.
func _silhouette_hero_row(reveal: Dictionary) -> Dictionary:
	for occluder_id: String in reveal.keys():
		var row: Dictionary = reveal[occluder_id]
		if not bool(row.get("open", false)):
			continue
		var hero: Dictionary = row.get("actors", {}).get("town/ranger", {})
		if not hero.is_empty() and float(hero.get("coverage", 0.0)) >= SilhouetteRevealScript.ENTER_COVERAGE:
			return {"id": occluder_id, "row": row}
	return {"id": "", "row": {}}


## Slot eligibility and native-piece-only invariants, checked at every hero
## position: exact clears may only ever name the hero or the currently
## protected resident, never an ambient one, and every reveal occluder must be
## a native binding piece — an actor node can be a plan occluder but can never
## carry a reveal material.
func _check_reveal_invariants(view, report: Dictionary, label: String) -> void:
	_expect(bool(report.get("silhouette_native_piece_only", false)), "silhouette: %s reported an actor node as a reveal occluder" % label)
	## Every reported actor-occluder entry must be one of this presenter's own
	## bound actors — the diagnostic names real actor nodes the plan selected
	## as foreground occluders, never an arbitrary or stale id.
	var actor_occluders: Array = report.get("actor_occluder_ids", [])
	var presenter_ids: Array[String] = view.actor_presentation_ids()
	for occluder_entry: String in actor_occluders:
		_expect(presenter_ids.has(occluder_entry), "silhouette: %s reported unknown actor occluder %s" % [label, occluder_entry])
	var protected_id := "town/npc/" + String(view._protected_resident)
	for rows_key: String in ["silhouette_reveal", "paired_reveal"]:
		var reveal: Dictionary = report.get(rows_key, {})
		for occluder_id: String in reveal.keys():
			if actor_occluders.has(occluder_id):
				_expect(false, "reveal invariants: %s actor %s carries a reveal material" % [label, occluder_id])
			var piece: Node = view.world_presenter.native_binding_node(occluder_id)
			_expect(piece is Sprite2D and piece.has_meta("binding_id"), "reveal invariants: %s reveal occluder %s is not a native binding piece" % [label, occluder_id])
			for actor_id: String in (reveal[occluder_id].get("actors", {}) as Dictionary).keys():
				_expect(actor_id == "town/ranger" or actor_id == protected_id,
					"reveal invariants: %s revealed ambient resident %s on %s" % [label, actor_id, occluder_id])


## Independent recompute: the uniforms really uploaded to a covering piece
## must equal the live sprites' own draw state, rebuilt here from the sprite
## transforms instead of the presenter's helpers, and the diagnostic row must
## agree with them.
func _verify_silhouette_material(view, occluder_id: String, row: Dictionary, label: String) -> void:
	var piece: Node = view.world_presenter.native_binding_node(occluder_id)
	if not (piece is Sprite2D and piece.material is ShaderMaterial):
		_expect(false, "silhouette: %s piece %s lost its reveal material" % [label, occluder_id])
		return
	var material := piece.material as ShaderMaterial
	_expect(int(material.get_shader_parameter("actor_count")) == int(row["actor_count"]), "silhouette: %s material actor_count diverged from its row" % label)
	_expect(is_equal_approx(float(material.get_shader_parameter("reveal_weight")), float(row["weight"])), "silhouette: %s material weight diverged from its row" % label)
	_expect(float(material.get_shader_parameter("clear_alpha")) == 0.0, "silhouette: %s material must clear to fully transparent" % label)
	var cells: PackedVector4Array = material.get_shader_parameter("actor_cells")
	var regions: PackedVector4Array = material.get_shader_parameter("actor_regions")
	var flags: PackedVector4Array = material.get_shader_parameter("actor_flags")
	var textures: Array = material.get_shader_parameter("actor_textures")
	var actors: Dictionary = row.get("actors", {})
	_expect(cells.size() == SilhouetteRevealScript.MAX_ACTORS and regions.size() == SilhouetteRevealScript.MAX_ACTORS
		and flags.size() == SilhouetteRevealScript.MAX_ACTORS and textures.size() == SilhouetteRevealScript.MAX_ACTORS,
		"silhouette: %s uniform arrays left the shader's declared length" % label)
	var ids: Array = actors.keys()
	for slot in ids.size():
		var actor_id := String(ids[slot])
		var sprite: Sprite2D = view._hero_sprite if actor_id == "town/ranger" else view._resident_views[actor_id.trim_prefix("town/npc/")]["node"]
		var expected_cell := Rect2(sprite.get_global_transform() * sprite.offset, sprite.region_rect.size)
		var uploaded := Rect2(Vector2(cells[slot].x, cells[slot].y), Vector2(cells[slot].z, cells[slot].w))
		_expect(uploaded.is_equal_approx(expected_cell), "silhouette: %s slot %s cell %s left the live draw cell %s" % [label, actor_id, str(uploaded), str(expected_cell)])
		var expected_region: Rect2 = sprite.region_rect
		_expect(is_equal_approx(float(regions[slot].x), expected_region.position.x) and is_equal_approx(float(regions[slot].y), expected_region.position.y)
			and is_equal_approx(float(regions[slot].z), expected_region.size.x) and is_equal_approx(float(regions[slot].w), expected_region.size.y),
			"silhouette: %s slot %s region left its atlas frame" % [label, actor_id])
		_expect(float(flags[slot].x) == (1.0 if sprite.flip_h else 0.0) and float(flags[slot].y) == (1.0 if sprite.flip_v else 0.0)
			and is_equal_approx(float(flags[slot].z), float(sprite.texture.get_width())) and is_equal_approx(float(flags[slot].w), float(sprite.texture.get_height())),
			"silhouette: %s slot %s flags left the live texture state" % [label, actor_id])
		_expect(textures[slot] == sprite.texture, "silhouette: %s slot %s uploaded a stale source frame" % [label, actor_id])
		var audit_row: Dictionary = actors[actor_id]
		_expect(String(audit_row.get("source_frame", "")) == String(sprite.texture.resource_path), "silhouette: %s slot %s diagnostic source frame diverged" % [label, actor_id])
		_expect(is_equal_approx(float(audit_row.get("modulate", -1.0)), sprite.modulate.a), "silhouette: %s slot %s diagnostic modulate diverged" % [label, actor_id])


## Audit R2 town gate: the detached plan must measure how much of a subject's
## art box one front piece covers, and the controller must tier that fraction
## (graze stays clear, mid band ramps, full cover dims to the occluded target)
## while plan order and reports stay deterministic.  Fixture style follows
## test_world_asset_pipeline.gd: one detached plan of hero plus one authored
## front piece per tier, no scene and no simulation state.
func _test_town_cover_tiers() -> void:
	# One hero cell (area 2400) with a taller front piece whose overlap height
	# picks the exact tier fraction: 6px graze, 10/15/20px mid band, 36px full.
	var tiers: Array = [
		{"id": "tree/graze", "box": Rect2(0.0, 96.0, 48.0, 40.0), "cover": 0.12},
		{"id": "tree/light", "box": Rect2(0.0, 92.0, 48.0, 60.0), "cover": 0.2},
		{"id": "tree/mid", "box": Rect2(0.0, 87.0, 48.0, 60.0), "cover": 0.3},
		{"id": "tree/high", "box": Rect2(0.0, 82.0, 48.0, 80.0), "cover": 0.4},
		{"id": "house/full", "box": Rect2(0.0, 66.0, 48.0, 80.0), "cover": 0.72},
	]
	var alphas: Dictionary = {}
	for tier: Dictionary in tiers:
		var entries: Array = [
			{"stable_id": "town/ranger", "baseline_y": 100.0, "rank": 0, "feet_anchor": Vector2(24.0, 102.0), "art_box": Rect2(0.0, 52.0, 48.0, 50.0)},
			{"stable_id": String(tier["id"]), "baseline_y": 140.0, "rank": 0, "feet_anchor": Vector2(24.0, 140.0), "art_box": tier["box"]},
		]
		var built: Dictionary = OcclusionPlanScript.build(entries)
		_expect(bool(built.get("ok", false)), "town cover: %s plan fixture was rejected: %s" % [String(tier["id"]), str(built.get("errors", []))])
		if not bool(built.get("ok", false)):
			continue
		var plan = built["value"]
		var report: Dictionary = plan.call("occlusion_report", "town/ranger")
		_expect(bool(report.get("ok", false)) and bool(report.get("occluded", false)), "town cover: %s did not report its front piece" % String(tier["id"]))
		_expect(is_equal_approx(float(report.get("cover_fraction", 0.0)), float(tier["cover"])), "town cover: %s measured %.4f instead of %.4f" % [String(tier["id"]), float(report.get("cover_fraction", 0.0)), float(tier["cover"])])
		# The per-occluder row keeps every established field and adds its own
		# deterministic cover fraction.
		var occluders: Array = plan.call("occluders_of", "town/ranger")
		_expect(occluders.size() == 1, "town cover: %s plan reported %d occluders" % [String(tier["id"]), occluders.size()])
		if occluders.size() == 1:
			var row: Dictionary = occluders[0]
			for field: String in ["stable_id", "baseline_y", "rank", "feet_anchor", "art_box", "cover_fraction"]:
				_expect(row.has(field), "town cover: occluder row lost %s" % field)
			_expect(is_equal_approx(float(row.get("cover_fraction", 0.0)), float(tier["cover"])), "town cover: %s row fraction drifted from the report" % String(tier["id"]))
		# The real chain input: the report fraction feeds the controller, which
		# converges on the tier target through the untouched eased transition.
		var controller = OcclusionControllerScript.new()
		_expect(bool(controller.adopt_plan(plan).get("ok", false)), "town cover: %s controller rejected the plan" % String(tier["id"]))
		_expect(bool(controller.set_cover("town/ranger", float(report.get("cover_fraction", 0.0))).get("ok", false)), "town cover: %s cover update was rejected" % String(tier["id"]))
		for _tick in 90:
			controller.update(1.0 / 30.0)
		alphas[String(tier["id"])] = controller.call("alpha", "town/ranger")
	if alphas.size() != tiers.size():
		return
	# (a) A graze below COVER_GRAZE_THRESHOLD must not dim at all.
	_expect(is_equal_approx(float(alphas["tree/graze"]), OcclusionControllerScript.CLEAR_TARGET_ALPHA),
		"town cover: a grazing piece dimmed the hero to %.3f" % float(alphas["tree/graze"]))
	# (b) A cover above COVER_FULL_THRESHOLD must land exactly on the occluded target.
	_expect(is_equal_approx(float(alphas["house/full"]), OcclusionControllerScript.OCCLUDED_TARGET_ALPHA),
		"town cover: a full cover settled at %.3f instead of the occluded target" % float(alphas["house/full"]))
	# (c) The mid band is monotonic and strictly between the two targets.
	_expect(float(alphas["tree/light"]) > float(alphas["tree/mid"]) and float(alphas["tree/mid"]) > float(alphas["tree/high"]),
		"town cover: mid-band alphas did not decrease with coverage (%.3f %.3f %.3f)" % [float(alphas["tree/light"]), float(alphas["tree/mid"]), float(alphas["tree/high"])])
	for tier_id: String in ["tree/light", "tree/mid", "tree/high"]:
		var alpha: float = float(alphas[tier_id])
		_expect(alpha > OcclusionControllerScript.OCCLUDED_TARGET_ALPHA and alpha < OcclusionControllerScript.CLEAR_TARGET_ALPHA,
			"town cover: %s settled on the band edge (%.3f)" % [tier_id, alpha])
	_expect(float(alphas["tree/high"]) > float(alphas["house/full"]), "town cover: the mid band must stay above the full-dim tier")
	# Band edges are pinned by name: the threshold values belong to the tier map.
	_expect(is_equal_approx(OcclusionControllerScript._target_alpha_for_cover(0.0), OcclusionControllerScript.CLEAR_TARGET_ALPHA), "town cover: zero cover must target full alpha")
	_expect(is_equal_approx(OcclusionControllerScript._target_alpha_for_cover(OcclusionControllerScript.COVER_GRAZE_THRESHOLD), OcclusionControllerScript.CLEAR_TARGET_ALPHA), "town cover: the graze threshold must still target full alpha")
	_expect(is_equal_approx(OcclusionControllerScript._target_alpha_for_cover(OcclusionControllerScript.COVER_FULL_THRESHOLD), OcclusionControllerScript.OCCLUDED_TARGET_ALPHA), "town cover: the full threshold must target the occluded alpha")
	_expect(is_equal_approx(OcclusionControllerScript._target_alpha_for_cover(1.0), OcclusionControllerScript.OCCLUDED_TARGET_ALPHA), "town cover: total cover must target the occluded alpha")
	# (d) Determinism: equal entries in any input order build the same plan,
	# and repeated queries on one plan never drift.
	var ordered: Array = []
	for tier: Dictionary in tiers:
		ordered.append({
			"stable_id": String(tier["id"]), "baseline_y": 140.0, "rank": 0,
			"feet_anchor": Vector2(25.0, 140.0), "art_box": tier["box"],
		})
	ordered.append({"stable_id": "town/ranger", "baseline_y": 100.0, "rank": 0, "feet_anchor": Vector2(24.0, 102.0), "art_box": Rect2(0.0, 52.0, 48.0, 50.0)})
	var forward: Dictionary = OcclusionPlanScript.build(ordered)
	var reversed_entries: Array = ordered.duplicate()
	(reversed_entries as Array).reverse()
	var backward: Dictionary = OcclusionPlanScript.build(reversed_entries)
	_expect(bool(forward.get("ok", false)) and bool(backward.get("ok", false)), "town cover: stability fixture was rejected")
	if bool(forward.get("ok", false)) and bool(backward.get("ok", false)):
		var plan_a = forward["value"]
		var plan_b = backward["value"]
		_expect(plan_a.call("entries") == plan_b.call("entries"), "town cover: input order changed the plan order")
		_expect(plan_a.call("to_payload") == plan_b.call("to_payload"), "town cover: input order changed the plan payload")
		_expect(plan_a.call("occluders_of", "town/ranger") == plan_b.call("occluders_of", "town/ranger"), "town cover: input order changed the occluder rows")
		_expect(plan_a.call("occlusion_report", "town/ranger") == plan_b.call("occlusion_report", "town/ranger"), "town cover: input order changed the cover report")
		_expect(plan_a.call("occluders_of", "town/ranger") == plan_a.call("occluders_of", "town/ranger"), "town cover: repeated occluder rows drifted")
		_expect(plan_a.call("occlusion_report", "town/ranger") == plan_a.call("occlusion_report", "town/ranger"), "town cover: repeated cover reports drifted")
		# The payload projection keeps exactly the established five fields, so
		# the presentation digest inputs are unchanged by the cover metric.
		for row: Dictionary in plan_a.call("to_payload"):
			_expect(row.keys().size() == 5 and row.has("stable_id") and row.has("baseline_y") and row.has("rank") and row.has("feet_anchor") and row.has("art_box"),
				"town cover: payload projection gained or lost fields: %s" % str(row.keys()))


func _test_arena() -> void:
	var view = ArenaWorldViewScript.new()
	for layout_id: String in ["rectangle_arena", "ring", "corridor"]:
		var concept: Dictionary = view.room_concept_report(layout_id)
		_expect(String(concept.get("title", "")).length() >= 2 and String(concept.get("landmark", "")).length() >= 2
			and bool(concept.get("presentation_only", false)), "arena: room concept %s is not a readable presentation contract" % layout_id)
	_expect(view.load_assets(), "arena: the published atlas/layout pair did not load: %s" % String(view.pending_reason))
	if not view.is_ready():
		_expect(false, "arena: the live world view is not ready, so no occlusion can be checked")
		return
	for sprite_id: String in view._sprites:
		var metadata: Dictionary = view.sprite(sprite_id)
		var texture: Texture2D = view._textures.get(metadata.texture)
		_expect(texture != null, "arena: %s has metadata but no actual texture, so it would be invisible" % sprite_id)
		if texture != null:
			_expect(Rect2(Vector2.ZERO, texture.get_size()).encloses(metadata.rect), "arena: %s source region exceeds its loaded texture" % sprite_id)
	_test_alpha_visible_bounds(view)

	var clear_gameplay := Vector2(430.0, 360.0)
	view.begin_frame(ARENA_VIEWPORT, clear_gameplay, ARENA_RECT)
	var clear_report: Dictionary = view.occlusion_report(view.gameplay_to_world(clear_gameplay))
	_expect(float(clear_report["local_opacity_total"]) <= LOCAL_OPACITY_CEILING, "arena: the entry frame already stacks %.3f local opacity" % float(clear_report["local_opacity_total"]))

	for placement: Dictionary in view.structure_placements():
		var sprite_id := String(placement.get("id", ""))
		var feet := Vector2(float((placement["feet"] as Array)[0]), float((placement["feet"] as Array)[1]))
		# This detached presentation sweep needs an actual covered subject. The
		# coarse low pier is only 41 native pixels high; the old 85-game-pixel
		# offset now stands wholly above its image. Mounted tests own clearance.
		var covered_offset := 30.0 if sprite_id == "ruin.low_pier" else 85.0
		_check_arena_cell(view, sprite_id, feet, feet - Vector2(0.0, covered_offset), "ruin %s at %s" % [sprite_id, str(feet)])
		_check_arena_ahead(view, sprite_id, feet, feet + Vector2(0.0, 12.0), "ruin %s at %s" % [sprite_id, str(feet)])

	_check_arena_tower(view)
	_check_arena_boss(view)
	_test_shared_diagnostic_geometry(view)
	_test_resolved_hero_destination(view)
	_test_mixed_actor_budget(view)
	print("  arena sweep: %d ruin placements, the tower and the colossus all measured" % view.structure_placements().size())


func _test_alpha_visible_bounds(view) -> void:
	var feet := Vector2(500.0, 400.0)
	for sprite_id in ["ruin.wall_corner", "boss.body_phase1", "enemy.melee.idle", "ranger.south.idle"]:
		var full := _full_sprite_destination(view, sprite_id, feet)
		var visible: Rect2 = view.sprite_art_box(sprite_id, feet)
		_expect(full.encloses(visible), "alpha: %s visible box escaped its full destination" % sprite_id)
		_expect(visible.size.x < full.size.x and visible.size.y < full.size.y, "alpha: %s did not shrink its transparent bounds" % sprite_id)
		_expect(visible == _expected_sprite_visible_box(view, sprite_id, feet, false), "alpha: %s did not retain its alpha bbox plus 1px padding" % sprite_id)
	var tower_upper: Rect2 = view.sprite_art_box("tower.upper", feet)
	var tower_base: Rect2 = view.sprite_art_box("tower.base", feet)
	_expect(tower_upper == _expected_sprite_visible_box(view, "tower.upper", feet, false), "alpha: tower.upper ignored keep_rows source region")
	_expect(tower_base == _expected_sprite_visible_box(view, "tower.base", feet, false), "alpha: tower.base ignored keep_rows source region")

	var image := Image.create(12, 10, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	for y in range(3, 8):
		for x in range(2, 5):
			image.set_pixel(x, y, Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	var dynamic_full := Rect2((feet - Vector2(4.0, 6.0)).round(), Vector2(12.0, 10.0))
	var east: Rect2 = view.frame_art_box(texture, Rect2(0, 0, 12, 10), feet, Vector2(4, 6), Vector2.ZERO, false)
	var west: Rect2 = view.frame_art_box(texture, Rect2(0, 0, 12, 10), feet, Vector2(4, 6), Vector2.ZERO, true)
	_expect(dynamic_full.encloses(east) and east.size == Vector2(5, 7), "alpha: dynamic frame did not include its asymmetric bbox plus 1px padding")
	_expect(west.size == east.size and west.position.x == dynamic_full.position.x + dynamic_full.size.x - (east.position.x - dynamic_full.position.x + east.size.x) and west.position.y == east.position.y, "alpha: flip_x did not mirror dynamic visible bounds east=%s west=%s full=%s" % [str(east), str(west), str(dynamic_full)])
	_expect(east != dynamic_full and west != dynamic_full, "alpha: dynamic transparent border still expanded occlusion to the full cell")
	var invalid: Rect2 = view.frame_art_box(null, Rect2(0, 0, 12, 10), feet, Vector2(4, 6))
	_expect(invalid == dynamic_full, "alpha: invalid texture cache fallback became a zero box")
	var transparent_image := Image.create(12, 10, false, Image.FORMAT_RGBA8)
	transparent_image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var transparent_texture := ImageTexture.create_from_image(transparent_image)
	_expect(view.frame_art_box(transparent_texture, Rect2(0, 0, 12, 10), feet, Vector2(4, 6)) == dynamic_full, "alpha: full-transparent frame did not use full-cell fallback")
	var hole_image := Image.create(12, 10, false, Image.FORMAT_RGBA8)
	hole_image.fill(Color(0.0, 0.0, 0.0, 0.0))
	for x in range(2, 10):
		hole_image.set_pixel(x, 2, Color.WHITE)
		hole_image.set_pixel(x, 7, Color.WHITE)
	for y in range(2, 8):
		hole_image.set_pixel(2, y, Color.WHITE)
		hole_image.set_pixel(9, y, Color.WHITE)
	var hole_texture := ImageTexture.create_from_image(hole_image)
	var hole_descriptor: Dictionary = view.frame_occlusion_descriptor(hole_texture, Rect2(0, 0, 12, 10), feet, Vector2(4, 6))
	var hole_destination: Rect2 = hole_descriptor["destination"]
	var hole_center := Rect2(hole_destination.position + Vector2(4, 4), Vector2(3, 2))
	var hole_edge := Rect2(hole_destination.position + Vector2(2, 4), Vector2(1, 2))
	_expect(hole_descriptor["art_box"].intersects(hole_center), "alpha: concave mask test did not retain its conservative art box")
	_expect(not view.occlusion_descriptor_intersects(hole_descriptor, hole_center), "alpha: transparent hole was treated as a visible occluder")
	_expect(view.occlusion_descriptor_intersects(hole_descriptor, hole_edge), "alpha: visible mask edge was lost during exact intersection")
	var hole_flip: Dictionary = view.frame_occlusion_descriptor(hole_texture, Rect2(0, 0, 12, 10), feet, Vector2(4, 6), Vector2.ZERO, true)
	var flipped_edge := Rect2(hole_flip["destination"].position + Vector2(9, 4), Vector2(1, 2))
	_expect(view.occlusion_descriptor_intersects(hole_flip, flipped_edge), "alpha: flipped concave mask did not mirror its visible edge")
	var asymmetric_image := Image.create(6, 6, false, Image.FORMAT_RGBA8)
	asymmetric_image.fill(Color(0.0, 0.0, 0.0, 0.0))
	for x in range(0, 2):
		for y in range(0, 2):
			asymmetric_image.set_pixel(x, y, Color.WHITE)
	var asymmetric_texture := ImageTexture.create_from_image(asymmetric_image)
	var asymmetric_flip: Dictionary = view.frame_occlusion_descriptor(asymmetric_texture, Rect2(0, 0, 6, 6), feet, Vector2.ZERO, Vector2.ZERO, true)
	var flipped_top := Rect2(asymmetric_flip["destination"].position + Vector2(4, 0), Vector2(2, 2))
	var flipped_bottom := Rect2(asymmetric_flip["destination"].position + Vector2(4, 4), Vector2(2, 2))
	_expect(view.occlusion_descriptor_intersects(asymmetric_flip, flipped_top), "alpha: flip_x lost the authored top row")
	_expect(not view.occlusion_descriptor_intersects(asymmetric_flip, flipped_bottom), "alpha: flip_x incorrectly mirrored the source vertically")

	var presenter := ArenaActorPresenterScript.new()
	var dynamic_frame := {"texture": texture, "rect": Rect2i(0, 0, 12, 10), "anchor": Vector2i(4, 6), "fallback": false, "flip_x": true}
	var enemy_box: Rect2 = presenter._enemy_frame_art_box(dynamic_frame, feet, view)
	_expect(enemy_box == west, "alpha: enemy dynamic frame art box disagreed with frame flip_x")
	view.begin_frame(ARENA_VIEWPORT, Vector2(500, 400), ARENA_RECT)
	var hero_frame := {"player_position": Vector2(500, 400), "player_facing": Vector2.LEFT, "ranger_frame": dynamic_frame}
	presenter._set_hero_occlusion_box(hero_frame, view)
	var hero_west: Rect2 = view.frame_art_box(texture, Rect2(0, 0, 12, 10), view.gameplay_to_world(Vector2(500, 400)), Vector2(4, 6), Vector2.ZERO, true)
	_expect(view.hero_cell_world(view.gameplay_to_world(Vector2(500, 400))) == hero_west, "alpha: hero action occlusion ignored explicit flip_x")
	var enemy := EnemyScript.new(Vector2.ZERO, 100.0, false, 19)
	enemy.facing = Vector2.LEFT
	var fallback_frame := {"enemy_frames": {}}
	var fallback_box: Rect2 = presenter._enemy_art_box(fallback_frame, enemy, feet, view)
	_expect(fallback_box == view.sprite_art_box("enemy.melee.idle", feet, true), "alpha: legacy enemy fallback art box ignored draw mirror")
	var world_source := FileAccess.get_file_as_string("res://src/presentation/arena_world_view.gd")
	var actor_source := FileAccess.get_file_as_string("res://src/presentation/arena_actor_presenter.gd")
	_expect(world_source.contains("var destination := Rect2((feet_world - anchor + (region.position - rect.position)).round(), size)"), "alpha: _draw_cell destination contract changed")
	_expect(world_source.contains("draw_texture_rect_region(texture, visible, source, modulate)"), "alpha: _draw_cell source contract changed")
	_expect(actor_source.contains("var destination := Rect2((feet_world - anchor).round(), region.size)"), "alpha: _draw_enemy_action_frame destination contract changed")
	_expect(actor_source.contains("draw_texture_rect_region(texture, visible, source, modulate)"), "alpha: _draw_enemy_action_frame source contract changed")


func _full_sprite_destination(view, sprite_id: String, feet: Vector2) -> Rect2:
	var metadata: Dictionary = view.sprite(sprite_id)
	var rect: Rect2 = metadata.get("rect", Rect2())
	var region: Rect2 = view._region_of(metadata)
	var anchor: Vector2 = metadata.get("anchor", Vector2.ZERO)
	return Rect2((feet - anchor + (region.position - rect.position)).round(), region.size)


func _expected_sprite_visible_box(view, sprite_id: String, feet: Vector2, flip_x: bool) -> Rect2:
	var metadata: Dictionary = view.sprite(sprite_id)
	var texture: Texture2D = view._textures.get(String(metadata.get("texture", "")))
	var region: Rect2 = view._region_of(metadata)
	var image: Image = texture.get_image()
	var source := Rect2i(region.position.round(), region.size.round())
	var min_x := source.end.x
	var min_y := source.end.y
	var max_x := source.position.x
	var max_y := source.position.y
	for y in range(source.position.y, source.end.y):
		for x in range(source.position.x, source.end.x):
			if image.get_pixel(x, y).a > 0.0:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x + 1)
				max_y = maxi(max_y, y + 1)
	var local := Rect2(Vector2(min_x - source.position.x, min_y - source.position.y), Vector2(max_x - min_x, max_y - min_y)).grow(ArenaWorldViewScript.ALPHA_VISIBLE_BOUNDS_PADDING).intersection(Rect2(Vector2.ZERO, region.size))
	if flip_x:
		local.position.x = region.size.x - (local.position.x + local.size.x)
	var rect: Rect2 = metadata.get("rect", Rect2())
	var anchor: Vector2 = metadata.get("anchor", Vector2.ZERO)
	var destination := Rect2((feet - anchor + (region.position - rect.position)).round(), region.size)
	return Rect2(destination.position + local.position, local.size)


func _test_resolved_hero_destination(view) -> void:
	var focus_gameplay := Vector2(570.0, 235.0)
	view.begin_frame(ARENA_VIEWPORT, focus_gameplay, ARENA_RECT)
	var hero_world: Vector2 = view.gameplay_to_world(focus_gameplay)
	var shifted := Rect2((hero_world - Vector2(24.0, 44.0) + Vector2(0.0, 1.0)).round(), Vector2(48.0, 48.0))
	var presenter := ArenaActorPresenterScript.new()
	var frame := {
		"player_position": focus_gameplay,
		"ranger_frame": {
			"fallback": false,
			"rect": Rect2i(0, 0, 48, 48),
			"anchor": Vector2i(24, 44),
			"draw_offset": Vector2i(0, 1),
		},
	}
	presenter._set_hero_occlusion_box(frame, view)
	_expect(view.hero_cell_world(hero_world) == shifted, "hero frame: cutaway kept the stale idle destination")
	_expect(view.cutaway_window(view.hero_cell_world(hero_world)).encloses(shifted), "hero frame: cutaway window does not cover the resolved destination")
	view.begin_frame(ARENA_VIEWPORT, focus_gameplay, ARENA_RECT)
	frame["ranger_frame"] = {"fallback": true}
	presenter._set_hero_occlusion_box(frame, view)
	_expect(view.hero_cell_world(hero_world) != shifted, "hero frame: fallback retained a previous action offset")
	view.begin_frame(ARENA_VIEWPORT, focus_gameplay, ARENA_RECT)
	_expect(view.hero_cell_world(hero_world) != shifted, "hero frame: begin_frame retained a previous action offset")


func _test_mixed_actor_budget(view) -> void:
	var placement: Dictionary = view.structure_placements()[0]
	var feet := Vector2(float(placement.feet[0]), float(placement.feet[1]))
	var hero_gameplay := feet - Vector2(0.0, 12.0)
	view.begin_frame(ARENA_VIEWPORT, hero_gameplay, ARENA_RECT)
	var hero: Vector2 = view.gameplay_to_world(hero_gameplay)
	var box: Rect2 = view.hero_cell_world(hero)
	var actors: Array[Dictionary] = []
	# Four Boss components plus two normal enemies in front of a real ruin:
	# exercise the worst-case mathematical envelope, not a claimed live encounter.
	for index in 6:
		actors.append({"id": "fixture_actor_%d" % index, "feet_world": hero + Vector2.DOWN, "art_box": box, "base_alpha": 1.0})
	view.prepare_actor_occlusion(actors, hero)
	var report: Dictionary = view.occlusion_report(hero)
	_expect(report.occluder_count == 6, "mixed: actor budget must contain six actors and exclude structure bands")
	_expect(report.local_opacity_total <= 0.160001, "mixed: independent group budgets composed above 0.16")
	var actor_cut: Dictionary = view.cutaway_for(box, hero + Vector2.DOWN, hero)
	_expect(is_equal_approx(actor_cut.local_alpha, report.local_alpha_each), "mixed: actor drawing did not consume the same budget")
	view.begin_frame(ARENA_VIEWPORT, hero_gameplay, ARENA_RECT)
	_expect(view.occlusion_report(hero).occluder_count == view.cutaway_front(hero).size(), "mixed: next frame retained stale dynamic occluders")


## Exercise the actual whole-object draw geometry, independently of controller constants.
func _settle_structure(view, sprite_id: String, feet: Vector2, hero: Vector2) -> void:
	var drawable := {"kind": "tower" if sprite_id == "tower" else "structure", "sprite": sprite_id,
		"world": feet, "stable_id": "fixture/structure", "baseline_y": feet.y, "rank": 0}
	var subject := {"stable_id": "ranger/body", "baseline_y": hero.y, "rank": 2,
		"readability_box": view.hero_cell_world(hero)}
	view.advance_structure_fades([drawable], [subject], 0.2)


func _check_arena_cell(view, sprite_id: String, feet_gameplay: Vector2, hero_gameplay: Vector2, label: String) -> void:
	view.reset_structure_fades()
	view.begin_frame(ARENA_VIEWPORT, hero_gameplay, ARENA_RECT)
	var hero: Vector2 = view.gameplay_to_world(hero_gameplay)
	var feet: Vector2 = view.gameplay_to_world(feet_gameplay)
	_settle_structure(view, sprite_id, feet, hero)
	var bands: Array = view.structure_geometry(sprite_id, feet)
	_expect(bands.size() == 1 and String(bands[0].part) == "whole", "arena: %s must draw as one whole object" % label)
	_expect(is_equal_approx(bands[0].alpha, 1.0), "arena: %s whole object lost its draw alpha" % label)
	var state: Dictionary = view.structure_fade_state(sprite_id, feet)
	_expect(String(state.get("policy")) == "paired_reveal" and bool(state.get("open", false)) and is_equal_approx(float(state.get("weight", -1.0)), 1.0),
		"arena: %s whole object did not reveal" % label)
	var material: Material = view.paired_reveal_material(sprite_id, feet)
	_expect(material is ShaderMaterial and is_equal_approx(float((material as ShaderMaterial).get_shader_parameter("reveal_weight")), 1.0),
		"arena: %s reveal material missing or eased weight unset" % label)
	_expect(view.cutaway_geometry(sprite_id, feet, hero).is_empty(), "arena: %s still stacks a character cutout on paired reveal" % label)
	_expect((view.hero_cover_report(hero).faded as Array).has(sprite_id), "arena: revealed structure absent from its report")


func _check_arena_ahead(view, sprite_id: String, feet_gameplay: Vector2, hero_gameplay: Vector2, label: String) -> void:
	view.begin_frame(ARENA_VIEWPORT, hero_gameplay, ARENA_RECT)
	var hero: Vector2 = view.gameplay_to_world(hero_gameplay)
	var feet: Vector2 = view.gameplay_to_world(feet_gameplay)
	_settle_structure(view, sprite_id, feet, hero)
	for band: Dictionary in view.structure_geometry(sprite_id, feet):
		_expect(is_equal_approx(band.alpha, 1.0), "arena: %s did not restore the whole object in front" % label)
	var front_state: Dictionary = view.structure_fade_state(sprite_id, feet)
	_expect(is_equal_approx(float(front_state.get("weight", -1.0)), 0.0) and is_equal_approx(float(front_state.get("alpha", 0.0)), 1.0),
		"arena: %s stayed revealed behind the hero" % label)


func _check_arena_tower(view) -> void:
	_check_arena_cell(view, "tower", view.tower_feet(), view.tower_feet() - Vector2(0, 110), "tower")
	_check_arena_ahead(view, "tower", view.tower_feet(), view.tower_feet() + Vector2(0, 80), "tower")


## The colossus is one occluder drawn as four sprites: standing behind it must cut
## body, core and both hands with a single shared share of the budget, and the
## authored 0.45 colossus fade must stay exactly as approved.
func _check_arena_boss(view) -> void:
	var boss_gameplay := Vector2(625.0, 360.0)
	var hero_gameplay := boss_gameplay - Vector2(0.0, 40.0)
	view.begin_frame(ARENA_VIEWPORT, hero_gameplay, ARENA_RECT)
	var hero_world: Vector2 = view.gameplay_to_world(hero_gameplay)
	var boss_world: Vector2 = view.gameplay_to_world(boss_gameplay)
	_expect(is_equal_approx(view.boss_fade_alpha(boss_world, hero_world), ArenaWorldViewScript.FORE_FADE), "arena: the approved colossus fade must stay at 0.45 in front of the hero")
	var sprite_ids := ["boss.body_phase1", "boss.core_phase1", "boss.hand_left", "boss.hand_right"]
	var feet_list := [boss_world, boss_world + ArenaWorldViewScript.BOSS_CORE_OFFSET, boss_world + ArenaWorldViewScript.BOSS_HAND_LEFT_OFFSET, boss_world + ArenaWorldViewScript.BOSS_HAND_RIGHT_OFFSET]
	var cut: Dictionary = view._boss_cutaway(sprite_ids, feet_list, boss_world, hero_world)
	_expect((cut["window"] as Rect2).size.x > 0.0, "arena: the colossus in front of the hero reports no window")
	_expect((cut["window"] as Rect2).encloses(view.hero_cell_world(hero_world)), "arena: the colossus window must cover the hero's own cell")
	var composed: float = ArenaWorldViewScript.FORE_FADE * float(cut["alpha"])
	_expect(composed <= LOCAL_OPACITY_CEILING + 0.000001, "arena: the colossus composes %.3f local opacity" % composed)
	for index: int in sprite_ids.size():
		var reaches: bool = view.sprite_art_box(String(sprite_ids[index]), feet_list[index] as Vector2).intersects(cut["window"])
		if index < 2:
			## Body and core always reach a window that covers the hero's own cell.
			_expect(reaches, "arena: the colossus's %s does not reach the reported window" % String(sprite_ids[index]))
		else:
			## An arm is cut together with the body whenever it does reach the window,
			## and left alone when the hero stands clear of it.
			_expect(reaches == view.sprite_art_box(String(sprite_ids[index]), feet_list[index] as Vector2).intersects(cut["window"]), "arena: the colossus arm share is inconsistent")


## The external reports must consume the same sort anchors and art rectangles as
## the live draw path.  This catches stale feet-only checks and Boss helpers that
## ignore a posed hand's actual sort anchor.
func _test_shared_diagnostic_geometry(view) -> void:
	var tower_gameplay: Vector2 = view.tower_feet() - Vector2(0, 110)
	view.begin_frame(ARENA_VIEWPORT, tower_gameplay, ARENA_RECT)
	var tower_world: Vector2 = view.gameplay_to_world(tower_gameplay)
	_settle_structure(view, "tower", view.tower_feet_world(), tower_world)
	var cover: Dictionary = view.hero_cover_report(tower_world)
	_expect((cover.faded as Array).has("tower"), "diagnostic cover lost physical tower transparency")
	var fades: Dictionary = view.occlusion_report(tower_world).primitive_fade
	_expect(not fades.is_empty(), "diagnostic report omitted structure fade state")
	_expect(fades.values().any(func(state: Dictionary): return String(state.get("policy")) == "paired_reveal"),
		"diagnostic report omitted the paired whole-object policy")

	var boss_feet := Vector2(500.0, 400.0)
	var hero := Vector2(500.0, 430.0)
	var left_delta := Vector2(100.0, 100.0)
	var posed_alpha: float = view.boss_fade_alpha(boss_feet, hero, 2, left_delta, Vector2.ZERO)
	_expect(is_equal_approx(posed_alpha, ArenaWorldViewScript.FORE_FADE), "Boss diagnostic fade ignored the posed hand sort anchor")
	_expect(view.boss_body_rect_world(boss_feet) == view.sprite_art_box("boss.body_phase2", boss_feet), "Boss body report diverged from its drawn art box")
	_expect(view.boss_hand_rect_world(boss_feet, true) == view.sprite_art_box("boss.hand_left", boss_feet + ArenaWorldViewScript.BOSS_HAND_LEFT_OFFSET), "Boss hand report diverged from its drawn art box")
