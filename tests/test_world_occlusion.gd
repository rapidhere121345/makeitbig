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
const ArenaWorldViewScript = preload("res://src/presentation/arena_world_view.gd")
const ArenaActorPresenterScript = preload("res://src/presentation/arena_actor_presenter.gd")
const BossActionPoseScript = preload("res://src/presentation/boss_action_pose.gd")
const FrameBuilderScript = preload("res://src/presentation/combat_presentation_frame_builder.gd")
const ArenaGeometryScript = preload("res://src/runtime/geometry/arena_geometry.gd")
const EnemyScript = preload("res://src/runtime/world/combat_enemy_state.gd")
const OcclusionPlanScript = preload("res://src/presentation/occlusion/occlusion_plan.gd")
const OcclusionControllerScript = preload("res://src/presentation/occlusion/occlusion_controller.gd")

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
	_test_town_cover_tiers()
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


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


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
	var view = ArenaWorldViewScript.new()
	view.begin_frame(ARENA_VIEWPORT, Vector2(430.0, 360.0), ARENA_RECT)
	var gameplay_bounds := Rect2(Vector2(56.0, 204.0), Vector2(1168.0, 460.0))
	var geometry := {
		"bounds": gameplay_bounds,
		"center": gameplay_bounds.get_center(),
		"corridor_half_height": 72.0,
		"inner_radius": 97.6,
		"outer_radius": 209.84,
	}
	var world_bounds: Rect2 = view._concept_bounds_world(geometry)
	_expect(world_bounds == Rect2(view.gameplay_to_world(gameplay_bounds.position), gameplay_bounds.size * ArenaWorldViewScript.GAMEPLAY_TO_WORLD), "concept: room landmarks did not use gameplay bounds")
	_expect(view._concept_center_world(geometry, world_bounds) == view.gameplay_to_world(gameplay_bounds.get_center()), "concept: room landmarks did not use gameplay center")
	_expect(is_equal_approx(view._concept_radius_world(geometry, "corridor_half_height", 62.0), 72.0 * ArenaWorldViewScript.GAMEPLAY_TO_WORLD), "concept: corridor landmark used a stale visual half-height")
	_expect(is_equal_approx(view._concept_radius_world(geometry, "outer_radius", 152.0), 209.84 * ArenaWorldViewScript.GAMEPLAY_TO_WORLD), "concept: ring landmark used a stale visual radius")
	var corridor_edge := view._concept_corridor_edge_world(geometry, world_bounds, 1.0)
	_expect(is_equal_approx(corridor_edge, view._concept_center_world(geometry, world_bounds).y + 72.0 * ArenaWorldViewScript.GAMEPLAY_TO_WORLD), "concept: corridor edge did not follow the authoritative half-height")
	var trace_radius := view._concept_ring_trace_radius_world(view._concept_radius_world(geometry, "inner_radius", 70.0), view._concept_radius_world(geometry, "outer_radius", 152.0))
	_expect(trace_radius > view._concept_radius_world(geometry, "inner_radius", 70.0) and trace_radius < view._concept_radius_world(geometry, "outer_radius", 152.0), "concept: ring trace escaped the authoritative radius band")


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
	var audit := view.render_audit()
	_expect(audit.ground_source_path == "res://content/rooms/town/layers/ground.png" and audit.runtime_background_patches == 0, "town: legacy background patch path survived")
	_expect(audit.unknown_underplate == "transparent" and audit.supports_cutaway and audit.supports_fade, "town: authored opacity capabilities were hidden")
	var shared: Node2D = view.world_presenter.sort_root
	_expect(shared.y_sort_enabled and view._hero_sprite.get_parent() == shared, "town: hero has a parallel sort domain")
	var native_count := 0
	for id: String in ["contract", "loadout", "forge", "proxy", "tree_south", "commons_fire"]:
		var sprite: Node = view.world_presenter.native_binding_node("town/native/" + id)
		_expect(sprite is Sprite2D and sprite.get_parent() == shared, "town: native building left shared sort root: " + id)
	for node: Node in shared.get_children():
		if not node.has_meta("texture_path"): continue
		native_count += 1
		_expect(node is Sprite2D and not (node as Sprite2D).region_enabled and String(node.get_meta("texture_path")).begins_with("res://content/rooms/town/layers/"), "town: visual was cropped from background at runtime")
		_expect((node as CanvasItem).visible and is_equal_approx((node as CanvasItem).modulate.a, 1.0), "town: transparent underplate enabled fade or hiding")
	var before: int = shared.get_child_count()
	for target: Vector2 in town.route_points("contract"):
		town.place_hero(target)
		await process_frame
		_expect(shared.get_child_count() == before, "town: movement created cutaway fragments")
		for node: Node in shared.get_children():
			if node.has_meta("texture_path"):
				_expect((node as CanvasItem).visible and (node as CanvasItem).modulate.a == 1.0, "town: movement hid native art")
	_expect(native_count == 35, "town: offline native ownership is incomplete")
	hub.free()


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
		_check_arena_cell(view, sprite_id, feet, feet - Vector2(0.0, 12.0), "ruin %s at %s" % [sprite_id, str(feet)])
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
	_expect(report.occluder_count >= 7, "mixed: real ruin and all six actor cells must share the plan")
	_expect(report.local_opacity_total <= 0.160001, "mixed: independent group budgets composed above 0.16")
	var sprite_id := String(placement.id)
	for piece: Dictionary in view.cutaway_geometry(sprite_id, view.gameplay_to_world(feet), hero):
		if piece.window:
			_expect(is_equal_approx(piece.alpha, report.local_alpha_each), "mixed: static drawing did not consume the shared prepass budget")
	var actor_cut: Dictionary = view.cutaway_for(box, hero + Vector2.DOWN, hero)
	_expect(is_equal_approx(actor_cut.local_alpha, report.local_alpha_each), "mixed: actor drawing did not consume the same budget")
	view.begin_frame(ARENA_VIEWPORT, hero_gameplay, ARENA_RECT)
	_expect(view.occlusion_report(hero).occluder_count == view.cutaway_front(hero).size(), "mixed: next frame retained stale dynamic occluders")


## Standing behind a ruin: it must be reported in front, cut with a window that
## covers the hero's own cell, and the pieces the draw calls use must read the same
## source pixels the authored cell does.
func _check_arena_cell(view, sprite_id: String, feet_gameplay: Vector2, hero_gameplay: Vector2, label: String) -> void:
	view.begin_frame(ARENA_VIEWPORT, hero_gameplay, ARENA_RECT)
	var hero_world: Vector2 = view.gameplay_to_world(hero_gameplay)
	var report: Dictionary = view.occlusion_report(hero_world)
	_expect(int(report["occluder_count"]) >= 1, "arena: %s reports no foreground cell" % label)
	_expect((report["front_ids"] as Array).has(sprite_id), "arena: %s is not reported as the cell in front" % label)
	_expect(float(report["local_opacity_total"]) <= LOCAL_OPACITY_CEILING, "arena: %s composes %.3f local opacity" % [label, float(report["local_opacity_total"])])
	_expect((report["window_world"] as Rect2).encloses(report["hero_cell_world"]), "arena: the window must cover the hero's own cell for %s" % label)

	var feet: Vector2 = view.gameplay_to_world(feet_gameplay)
	var authored: float = view.structure_fade(sprite_id, feet, hero_world)
	_expect(is_equal_approx(view.structure_draw_alpha(sprite_id, feet, hero_world), 1.0), "arena: %s globally faded the whole ruin instead of using the local cutaway window" % label)
	var drawn: Array[Dictionary] = view.cutaway_geometry(sprite_id, feet, hero_world, authored)
	_expect(not drawn.is_empty(), "arena: %s keeps its single-rectangle draw while covering the hero" % label)
	var window_seen := false
	for piece: Dictionary in drawn:
		_expect(ARENA_VIEWPORT.encloses(piece["dest"]), "arena: %s draws outside the visible frame" % label)
		if bool(piece["window"]):
			window_seen = true
			_expect(float(piece["alpha"]) <= LOCAL_OPACITY_CEILING + 0.000001, "arena: %s draws its window at %.3f local opacity" % [label, float(piece["alpha"])])
		else:
			_expect(is_equal_approx(float(piece["alpha"]), authored), "arena: %s changed the authored alpha outside the window" % label)
	_expect(window_seen, "arena: %s drew no low-alpha window at all" % label)


## Standing in front of the ruin: no cutaway may touch it, and the historical
## headless cover report must still agree.
func _check_arena_ahead(view, sprite_id: String, feet_gameplay: Vector2, hero_gameplay: Vector2, label: String) -> void:
	view.begin_frame(ARENA_VIEWPORT, hero_gameplay, ARENA_RECT)
	var hero_world: Vector2 = view.gameplay_to_world(hero_gameplay)
	var report: Dictionary = view.occlusion_report(hero_world)
	var feet: Vector2 = view.gameplay_to_world(feet_gameplay)
	_expect(is_equal_approx(view.structure_fade(sprite_id, feet, hero_world), 1.0), "arena: %s must keep its authored alpha while the hero stands in front of it" % label)
	## Another placement of the same ruin id may legitimately still stand in front
	## somewhere else in the arena, so this instance is checked on its own geometry:
	## the cutaway belongs to the placed cell, never to the ruin id.
	for occluder: Dictionary in report["occluders"]:
		_expect(not (occluder["feet_world"] as Vector2).is_equal_approx(feet), "arena: %s is reported in front while the hero stands in front of it" % label)
	_expect(view.cutaway_geometry(sprite_id, feet, hero_world).is_empty(), "arena: %s was cut while the hero stands in front of it" % label)


func _check_arena_tower(view) -> void:
	var tower_gameplay: Vector2 = view.tower_feet()
	var hero_gameplay: Vector2 = tower_gameplay - Vector2(0.0, 12.0)
	view.begin_frame(ARENA_VIEWPORT, hero_gameplay, ARENA_RECT)
	var hero_world: Vector2 = view.gameplay_to_world(hero_gameplay)
	var report: Dictionary = view.occlusion_report(hero_world)
	_expect((report["front_ids"] as Array).has("tower"), "arena: the tower is not reported as the cell in front while the hero stands behind it")
	_expect(float(report["local_opacity_total"]) <= LOCAL_OPACITY_CEILING, "arena: the tower composes %.3f local opacity" % float(report["local_opacity_total"]))
	var feet: Vector2 = view.tower_feet_world()
	for sprite_id in ["tower.base", "tower.upper"]:
		var drawn: Array[Dictionary] = view.cutaway_geometry(sprite_id, feet, hero_world, view.structure_fade(sprite_id, feet, hero_world))
		_expect(not drawn.is_empty(), "arena: the tower's %s band keeps its single-rectangle draw while covering the hero" % sprite_id)
		for piece: Dictionary in drawn:
			if bool(piece["window"]):
				_expect(float(piece["alpha"]) <= LOCAL_OPACITY_CEILING + 0.000001, "arena: the tower's %s window draws at %.3f local opacity" % [sprite_id, float(piece["alpha"])])


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
	var tower_gameplay: Vector2 = view.tower_feet() - Vector2(0.0, 12.0)
	view.begin_frame(ARENA_VIEWPORT, tower_gameplay, ARENA_RECT)
	var tower_world: Vector2 = view.gameplay_to_world(tower_gameplay)
	var cover: Dictionary = view.hero_cover_report(tower_world)
	var live: Dictionary = view.occlusion_report(tower_world)
	_expect((cover["in_front"] as Array).has("tower.upper"), "diagnostic cover report disagreed with the live tower occluder")
	_expect((cover["faded"] as Array).has("tower.upper"), "diagnostic cover report lost the tower fade decision")
	_expect((live["front_ids"] as Array).has("tower"), "live tower report lost its shared static entry")
	var placement: Dictionary = view.structure_placements()[0]
	var ruin_id := String(placement["id"])
	var ruin_feet_gameplay := Vector2(float((placement["feet"] as Array)[0]), float((placement["feet"] as Array)[1]))
	view.begin_frame(ARENA_VIEWPORT, ruin_feet_gameplay - Vector2(0.0, 12.0), ARENA_RECT)
	var ruin_cover: Dictionary = view.hero_cover_report(view.gameplay_to_world(ruin_feet_gameplay - Vector2(0.0, 12.0)))
	_expect((ruin_cover["faded"] as Array).has(ruin_id), "diagnostic cover report treated a foreground ruin cutaway as opaque")

	var boss_feet := Vector2(500.0, 400.0)
	var hero := Vector2(500.0, 430.0)
	var left_delta := Vector2(100.0, 100.0)
	var posed_alpha: float = view.boss_fade_alpha(boss_feet, hero, 2, left_delta, Vector2.ZERO)
	_expect(is_equal_approx(posed_alpha, ArenaWorldViewScript.FORE_FADE), "Boss diagnostic fade ignored the posed hand sort anchor")
	_expect(view.boss_body_rect_world(boss_feet) == view.sprite_art_box("boss.body_phase2", boss_feet), "Boss body report diverged from its drawn art box")
	_expect(view.boss_hand_rect_world(boss_feet, true) == view.sprite_art_box("boss.hand_left", boss_feet + ArenaWorldViewScript.BOSS_HAND_LEFT_OFFSET), "Boss hand report diverged from its drawn art box")
