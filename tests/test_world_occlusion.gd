extends SceneTree
## Standalone occlusion regression for the two live world views: the cutaway that
## keeps a hero's own source pixels readable when a ruin, a stand or the colossus
## draws in front of it.
##
## Run it on its own, no GPU harness and no full suite:
##   godot --headless --path . --script res://tests/test_world_occlusion.gd
##
## It reads the published atlas/layout pairs of both views, never writes gameplay
## state and never re-renders: the numbers it checks are the numbers the draw calls
## consume, because both come from the same functions.

const HamletConceptViewScript = preload("res://src/presentation/hamlet_concept_view.gd")
const ArenaWorldViewScript = preload("res://src/presentation/arena_world_view.gd")
const BossActionPoseScript = preload("res://src/presentation/boss_action_pose.gd")

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
	_test_hamlet()
	await _test_town_scene()
	_test_arena()
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


## The local opacity budget is the whole point of the pass: whatever a frame stacks
## on top of the hero, the composed opacity of that stack may never exceed the
## ceiling, and a single foreground band must stay inside the approved band.
func _test_budget() -> void:
	_expect(is_equal_approx(HamletConceptViewScript.cutaway_alpha(0), 1.0), "budget: no occluder must leave the authored alpha alone")
	_expect(is_equal_approx(ArenaWorldViewScript.cutaway_alpha(0), 1.0), "budget: arena must leave the authored alpha alone without an occluder")
	for count in range(1, 7):
		var hamlet_share := HamletConceptViewScript.cutaway_alpha(count)
		var arena_share := ArenaWorldViewScript.cutaway_alpha(count)
		_expect(is_equal_approx(hamlet_share, arena_share), "budget: both views disagree on the share for %d occluder(s)" % count)
		var composed := 1.0 - pow(1.0 - hamlet_share, float(count))
		_expect(composed <= LOCAL_OPACITY_CEILING + 0.000001, "budget: %d occluder(s) compose %.3f, above the local ceiling" % [count, composed])
		_expect(composed >= 0.12, "budget: %d occluder(s) compose %.3f, below the approved local band" % [count, composed])
	_expect(is_equal_approx(HamletConceptViewScript.cutaway_alpha(1), 0.16), "budget: a single foreground band must sit at the approved 0.16 local opacity")


## The five pieces must tile the drawn cell exactly once: a cut may never double a
## band, leave a seam, or touch a pixel the authored alpha already covered.
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


func _test_hamlet() -> void:
	var view = HamletConceptViewScript.new()
	root.add_child(view)
	# Keep old configure fixtures explicit; the formal entry now uses the full town.
	var atlas: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(HamletConceptViewScript.DEFAULT_ATLAS_PATH))
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(HamletConceptViewScript.LEGACY_LAYOUT_PATH))
	view.configure(atlas, layout)
	if not view.is_ready():
		_expect(false, "hamlet: the live hub view is not ready, so no occlusion can be checked")
		return
	_expect(view._sprites.has("hamlet.fence"), "hamlet: the rack cell is missing from the union of the published atlases")

	for point: Vector2 in BASE_RACK_FAILURES:
		view.teleport_hero(point)
		view._process(0.016)
		var report: Dictionary = view.occlusion_report()
		_expect(int(report["occluder_count"]) >= 1, "hamlet: the rack at %s reports no foreground layer" % str(point))
		_expect((report["front_ids"] as Array).has("north_fence"), "hamlet: the rack is not reported as the layer in front at %s" % str(point))
		_expect(float(report["local_opacity_total"]) <= LOCAL_OPACITY_CEILING, "hamlet: %s composes %.3f local opacity" % [str(point), float(report["local_opacity_total"])])
		_expect((report["window_world"] as Rect2).encloses(report["hero_cell_world"]), "hamlet: the window must cover the hero's own cell at %s" % str(point))
		_check_hamlet_cut(view, "north_fence", 1.0, "rack at %s" % str(point))

	for point: Vector2 in BASE_HEARTH_FAILURES:
		view.teleport_hero(point)
		view._process(0.016)
		var report: Dictionary = view.occlusion_report()
		_expect(int(report["occluder_count"]) >= 1, "hamlet: the hearth at %s reports no foreground layer" % str(point))
		_expect(float(report["local_opacity_total"]) <= LOCAL_OPACITY_CEILING, "hamlet: the hearth at %s composes %.3f local opacity" % [str(point), float(report["local_opacity_total"])])
		_expect((report["window_world"] as Rect2).encloses(report["hero_cell_world"]), "hamlet: the window must cover the hero's own cell at %s" % str(point))
		_check_hamlet_cut(view, "hearth.upper", float(HamletConceptViewScript.SPLIT_FADE_ALPHA), "hearth at %s" % str(point))

	view.teleport_hero(BASE_IN_FRONT)
	view._process(0.016)
	var in_front: Dictionary = view.occlusion_report()
	_expect(not (in_front["front_ids"] as Array).has("north_fence"), "hamlet: the rack must not be cut when the hero's own feet are in front of it")
	var rack := view._sprite_nodes.get("north_fence", null) as Sprite2D
	_expect(rack != null and rack.visible, "hamlet: the rack must stay drawn when the hero is in front of it")
	_expect(rack != null and is_equal_approx(rack.modulate.a, 1.0), "hamlet: the rack's authored alpha must not change when the hero is in front of it")

	view.teleport_hero(BASE_CLEAR)
	view._process(0.016)
	_expect(rack != null and rack.visible, "hamlet: leaving the rack must restore the authored drawing in the same frame")
	for node: Sprite2D in _hamlet_pieces(view, "north_fence"):
		if node != null:
			_expect(not node.visible, "hamlet: a cut piece of the rack stayed on screen after the hero walked clear")

	_test_hamlet_sweep(view)
	# Movement updates the sprite immediately; its occlusion must be committed
	# in that same call, even before this view's next _process callback.
	view.teleport_hero(Vector2(570.0, 212.2))
	view.move_hero(Vector2.UP, 2.0 / 30.0)
	var crossing_rack := view._sprite_nodes.get("north_fence") as Sprite2D
	_expect(crossing_rack != null and not crossing_rack.visible, "hamlet: crossing behind rack left the opaque source visible for one frame")
	view.move_hero(Vector2.DOWN, 2.0 / 30.0)
	_expect(crossing_rack != null and crossing_rack.visible, "hamlet: leaving rack failed to restore it on the movement frame")
	root.remove_child(view)
	view.free()


## One foreground band: the window it draws must be the low-alpha piece, the rest
## of the band must keep the authored alpha, and the pieces must tile its cell.
func _check_hamlet_cut(view, placement_id: String, authored_alpha: float, label: String) -> void:
	var sprite := view._sprite_nodes.get(placement_id, null) as Sprite2D
	if sprite == null:
		_expect(false, "hamlet: %s has no drawn sprite" % label)
		return
	_expect(not sprite.visible, "hamlet: %s is still drawn as one whole cell under the hero" % label)
	var pieces := _hamlet_pieces(view, placement_id)
	_expect(pieces.size() == 5, "hamlet: %s has %d cut pieces instead of five" % [label, pieces.size()])
	var covered := 0.0
	var window_seen := false
	for index in pieces.size():
		var node := pieces[index] as Sprite2D
		if node == null or not node.visible:
			continue
		covered += node.region_rect.size.x * node.region_rect.size.y
		if index == HamletConceptViewScript.CUTAWAY_WINDOW_INDEX:
			window_seen = true
			_expect(node.modulate.a <= LOCAL_OPACITY_CEILING + 0.000001, "hamlet: %s draws its window at %.3f local opacity" % [label, node.modulate.a])
			_expect(node.modulate.a <= authored_alpha + 0.000001, "hamlet: %s draws its window brighter than the authored band" % label)
		else:
			_expect(is_equal_approx(node.modulate.a, authored_alpha), "hamlet: %s changed the authored alpha outside the window" % label)
	_expect(window_seen, "hamlet: %s drew no low-alpha window at all" % label)
	_expect(covered <= sprite.region_rect.size.x * sprite.region_rect.size.y + 0.5, "hamlet: %s draws more pixels than its own cell" % label)


func _hamlet_pieces(view, placement_id: String) -> Array:
	var sprite := view._sprite_nodes.get(placement_id, null) as Sprite2D
	if sprite == null:
		return []
	return view._cutaway_cache.get(int(sprite.get_instance_id()), []) as Array


## Sample the real layout on a 24px grid, reporting its deepest observed stack.
## This finite geometry sweep does not prove every possible subpixel position.
func _test_hamlet_sweep(view) -> void:
	var deepest := 0
	var worst := 0.0
	var worst_point := Vector2.ZERO
	var y := 24.0
	while y < view.world_size().y - 24.0:
		var x := 24.0
		while x < view.world_size().x - 24.0:
			view.teleport_hero(Vector2(x, y))
			view._process(0.001)
			var report: Dictionary = view.occlusion_report()
			deepest = maxi(deepest, int(report["occluder_count"]))
			var total := float(report["local_opacity_total"])
			if total > worst:
				worst = total
				worst_point = Vector2(x, y)
			x += 24.0
		y += 24.0
	_expect(worst <= LOCAL_OPACITY_CEILING + 0.000001, "hamlet: the sweep stacks %.3f local opacity at %s" % [worst, str(worst_point)])
	_expect(deepest >= 1, "hamlet: the sweep found no foreground overlap at all, so the cutaway was never exercised")
	print("  hamlet sweep: deepest stack %d layer(s), worst local opacity %.3f at %s" % [deepest, worst, str(worst_point)])


func _polygon_area(points: PackedVector2Array) -> float:
	var total := 0.0
	for index in points.size():
		total += points[index].cross(points[(index + 1) % points.size()])
	return absf(total) * 0.5


func _test_town_scene() -> void:
	var view = HamletConceptViewScript.new()
	root.add_child(view)
	_expect(view.load_default_assets(), "town: formal PNG/layout not ready")
	var audit: Dictionary = view.render_audit()
	_expect(audit.ground_source_path == "res://art/production/p1/hamlet_town/town.png", "town: formal background uses an old ground")
	for patch: Node2D in view._scene_patches:
		_expect(patch.get_parent() == view.actor_layer and patch.scene_texture == view._scene_texture,
			"town: foreground is not the same texture in the feet-sort layer")
		_expect(not Geometry2D.triangulate_polygon(patch.world_polygon).is_empty(), "town: invalid foreground " + String(patch.name))
	for id: String in ["contract", "loadout", "forge", "proxy", "tree_south", "commons_fire"]:
		var target: Node2D
		for patch: Node2D in view._scene_patches:
			if String(patch.get_meta("placement_id")) == id: target = patch
		_expect(target != null, "town: missing foreground " + id)
		if target == null: continue
		view.teleport_hero(target.position - Vector2(0, 18))
		# Let the actual CanvasItem draw consume its polygon UVs and cut bands.
		await process_frame
		await process_frame
		var report: Dictionary = view.occlusion_report()
		_expect(id in report.front_ids and report.local_opacity_total <= LOCAL_OPACITY_CEILING,
			"town: behind %s is not locally readable" % id)
		_expect(target.cut_alpha < 1.0 and target.cut_window == report.window_world, "town: draw window differs from occlusion report " + id)
		var covered := 0.0
		var found_window := false
		for fragment: Dictionary in target.fragments():
			var points: PackedVector2Array = fragment.points
			covered += _polygon_area(points)
			_expect(not Geometry2D.triangulate_polygon(points).is_empty(), "town: cut fragment cannot draw " + id)
			found_window = found_window or float(fragment.alpha) < 1.0
		_expect(found_window and absf(covered - _polygon_area(target.world_polygon)) < 0.1,
			"town: window fragments duplicate or lose foreground area " + id)
		view.teleport_hero(target.position + Vector2(0, 60))
		_expect(target.cut_alpha == 1.0 and id not in view.occlusion_report().front_ids,
			"town: in front of %s still fades" % id)
	# The open wood-barn bay must not repeat a floor polygon over its resident.
	var taren := view._sprite_nodes.get("taren") as Sprite2D
	for patch: Node2D in view._scene_patches:
		if String(patch.get_meta("placement_id")) == "loadout":
			_expect(not Geometry2D.is_point_in_polygon(taren.position, patch.world_polygon), "town: barn bay floor masks the worker")
	_test_hamlet_sweep(view)
	root.remove_child(view)
	view.free()


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
	_test_mixed_actor_budget(view)
	print("  arena sweep: %d ruin placements, the tower and the colossus all measured" % view.structure_placements().size())


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
