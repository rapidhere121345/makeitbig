extends SceneTree
## Reproducible technical integration preview, NOT hometown art acceptance.
## Run on a rendering display:
## GODOT --path . --script res://tools/modular_town_preview.gd
## Output must be fresh; override with -- --output=res://build/current/another-round
## Optional candidate mount: -- --definition=res://.../town_loadout_v01.tres swaps
## only the building placement for the production sample. Both sample policies
## are accepted: the legacy authored_variant mount (implicit reveal pair) and
## the primitive_fade mount (validated occlusion volumes, no variant art, a
## solid common base). The greybox default run is unchanged; every original
## check still runs; a definition that is missing, not an
## EnvironmentObjectDefinition, fails validate(), or misses the sample reveal
## contract rejects with exit 2 before any output is written.
## Optional pine mount: -- --tree-definition=res://.../pine.tres replaces both
## greybox trees with that production definition at the same placements and
## binding ids, and may be combined with --definition. Ground, gate and fence
## stay greybox. The same strict reject-with-exit-2-before-output rules apply.

const Definition := preload("res://src/runtime/world/environment_object_definition.gd")
const Placement := preload("res://src/runtime/world/environment_object_placement.gd")
const Baker := preload("res://src/runtime/world/environment_object_baker.gd")
const TownRoot := preload("res://src/runtime/world/town_scene_root.gd")
const TownControllerScript := preload("res://src/runtime/world/town_controller.gd")
const TownView := preload("res://src/presentation/town_presenter.gd")
const PrimitiveFade := preload("res://src/presentation/occlusion/primitive_fade_controller.gd")

var output := "res://build/current/modular-town-preview-r2"
var definition_path := ""
var candidate_definition: Definition = null
const CANDIDATE_PLACEMENT := Vector2(148, 148)
var tree_definition_path := ""
var tree_definition: Definition = null
const TREE_PLACEMENTS: Array[Vector2] = [Vector2(480, 210), Vector2(650, 300)]
const TREE_PLACEMENT_IDS: Array[String] = ["tree-west", "tree-east"]
const TREE_ANCHOR := Vector2(48, 128)
## Active reveal policy per mount, resolved from each loaded definition's
## upper part (absent means the historical implicit authored_variant, exactly
## as the baker resolves it). The greybox defaults keep every legacy path.
var building_policy := "authored_variant"
var tree_policy := "authored_variant"
## Idle settle window longer than the fade transition so every open/exit
## assertion measures the settled end state, not a mid-transition value.
const FADE_SETTLE_SECONDS := 0.4
var errors: Array[String] = []
var frames: Array[Dictionary] = []
var checks: Array[Dictionary] = []
var controller
var view
var caption: Label


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var definition_requested := false
	var tree_requested := false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
		elif argument == "--definition" or argument.begins_with("--definition="):
			# Flag presence is tracked separately from its value: an explicitly
			# requested candidate mount must reject, never fall back to greybox.
			definition_requested = true
			if argument.begins_with("--definition="):
				definition_path = argument.trim_prefix("--definition=")
		elif argument == "--tree-definition" or argument.begins_with("--tree-definition="):
			tree_requested = true
			if argument.begins_with("--tree-definition="):
				tree_definition_path = argument.trim_prefix("--tree-definition=")
	if definition_requested:
		candidate_definition = _load_candidate_definition(definition_path)
		if candidate_definition == null:
			quit(2)
			return
	if tree_requested:
		tree_definition = _load_tree_definition(tree_definition_path)
		if tree_definition == null:
			quit(2)
			return
	if candidate_definition != null:
		building_policy = _definition_upper_policy(candidate_definition)
	if tree_definition != null:
		tree_policy = _definition_upper_policy(tree_definition)
	if DisplayServer.get_name().to_lower().contains("headless"):
		printerr("GPU SKIP: modular town preview requires a rendering display")
		quit(2)
		return
	if not output.begins_with("res://build/") or ".." in output or DirAccess.dir_exists_absolute(output):
		printerr("PREVIEW REJECTED: fresh res://build/ output required")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		printerr("PREVIEW REJECTED: cannot create output")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	if not _author_scene():
		_finish()
		return
	view = TownView.new()
	root.add_child(view)
	view.set_process(false)
	controller = TownControllerScript.new()
	root.add_child(controller)
	var mounted: Dictionary = controller.mount(view.world_viewport, output.path_join("preview.tscn"), output.path_join("preview.spatial.json"))
	_check(bool(mounted.get("ok", false)), "production_mount", mounted)
	if not errors.is_empty():
		_finish()
		return
	var loaded: Dictionary = view.load_character_assets()
	_check(bool(loaded.get("ok", false)), "real_character_assets", loaded)
	var attached: Dictionary = view.attach(controller.scene_runtime.presenter, controller.town.snapshot(), controller.scene_runtime)
	_check(bool(attached.get("ok", false)), "production_presenter_attach", attached)
	if not errors.is_empty():
		_finish()
		return
	view.set_world_scale(2, Vector2(1280, 720))
	caption = Label.new()
	caption.position = Vector2(16, 8)
	caption.add_theme_font_size_override("font_size", 18)
	caption.add_theme_color_override("font_color", Color("fff4c2"))
	caption.add_theme_color_override("font_shadow_color", Color.BLACK)
	caption.add_theme_constant_override("shadow_offset_x", 2)
	caption.add_theme_constant_override("shadow_offset_y", 2)
	root.add_child(caption)
	await _walkthrough()
	if candidate_definition != null:
		await _candidate_checks()
	if tree_definition != null:
		_tree_checks()
	if building_policy == PrimitiveFade.POLICY or tree_policy == PrimitiveFade.POLICY:
		await _fade_checks()
	_finish()


## Strict candidate mount. The sample preview accepts only a project resource of
## the exact definition type that passes validate() and matches the loadout
## sample contract (256x224 canvas, common+upper parts, a revealable upper —
## the historical authored pair or primitive fade with a solid common base);
## anything else rejects before the output directory exists.
func _load_candidate_definition(path: String) -> Definition:
	if path.is_empty():
		printerr("PREVIEW REJECTED: --definition requires a res:// resource path value")
		return null
	if not path.begins_with("res://"):
		printerr("PREVIEW REJECTED: --definition needs a res:// project path: ", path)
		return null
	if not ResourceLoader.exists(path):
		printerr("PREVIEW REJECTED: definition resource not found: ", path)
		return null
	var resource := load(path)
	if resource == null or not resource is Definition:
		printerr("PREVIEW REJECTED: not an EnvironmentObjectDefinition resource: ", path)
		return null
	var definition := resource as Definition
	var invalid: Array[String] = definition.validate()
	if not invalid.is_empty():
		printerr("PREVIEW REJECTED: definition validate() failed: ", path, " ", invalid)
		return null
	var part_ids := []
	var upper: Dictionary = {}
	var common: Dictionary = {}
	for part: Dictionary in definition.visual_parts:
		part_ids.append(String(part.part_id))
		if String(part.part_id) == "upper":
			upper = part
		elif String(part.part_id) == "common":
			common = part
	if definition.canvas_size != Vector2i(256, 224) or part_ids.size() != 2 or not (part_ids.has("common") and part_ids.has("upper")):
		printerr("PREVIEW REJECTED: sample contract expects canvas 256x224 with parts common+upper: ", path)
		return null
	if not _sample_reveal_contract(upper, common, "", path):
		return null
	return definition


## Strict production pine mount. Both tree placements accept only a project
## resource of the exact definition type that passes validate() and matches
## the pine sample contract: canvas 96x144, visual parts common+upper both
## anchored at (48,128), a revealable upper — an authored reveal pair (an
## empty revealed bitmap is intentional; only the paths must exist, which
## validate() checks) or primitive fade with validated volumes and a solid
## common base — one footprint circle (48,128) r10 and one movement envelope
## circle (48,128) r14 carrying part_id "envelope" (the baked and mounted
## checks address that binding). Anything else rejects before the output
## directory exists; there is never a silent greybox fallback.
func _load_tree_definition(path: String) -> Definition:
	if path.is_empty():
		printerr("PREVIEW REJECTED: --tree-definition requires a res:// resource path value")
		return null
	if not path.begins_with("res://"):
		printerr("PREVIEW REJECTED: --tree-definition needs a res:// project path: ", path)
		return null
	if not ResourceLoader.exists(path):
		printerr("PREVIEW REJECTED: tree definition resource not found: ", path)
		return null
	var resource := load(path)
	if resource == null or not resource is Definition:
		printerr("PREVIEW REJECTED: not an EnvironmentObjectDefinition resource: ", path)
		return null
	var definition := resource as Definition
	var invalid: Array[String] = definition.validate()
	if not invalid.is_empty():
		printerr("PREVIEW REJECTED: tree definition validate() failed: ", path, " ", invalid)
		return null
	var part_ids := []
	var common: Dictionary = {}
	var upper: Dictionary = {}
	for part: Dictionary in definition.visual_parts:
		part_ids.append(String(part.part_id))
		if String(part.part_id) == "common":
			common = part
		elif String(part.part_id) == "upper":
			upper = part
	if definition.canvas_size != Vector2i(96, 144) or part_ids.size() != 2 or not (part_ids.has("common") and part_ids.has("upper")):
		printerr("PREVIEW REJECTED: pine contract expects canvas 96x144 with parts common+upper: ", path)
		return null
	if Vector2(common.get("sort_anchor", Vector2.ZERO)) != TREE_ANCHOR or Vector2(upper.get("sort_anchor", Vector2.ZERO)) != TREE_ANCHOR:
		printerr("PREVIEW REJECTED: pine contract anchors both parts at ", TREE_ANCHOR, ": ", path)
		return null
	if not _sample_reveal_contract(upper, common, "pine ", path):
		return null
	if not _single_pine_circle(definition.footprints, 10.0) or not _single_pine_circle(definition.movement_envelopes, 14.0) or String(definition.movement_envelopes[0].get("part_id", "")) != "envelope":
		printerr("PREVIEW REJECTED: pine contract expects one footprint circle r10 and one envelope circle r14 at ", TREE_ANCHOR, " with envelope part_id 'envelope': ", path)
		return null
	return definition


func _single_pine_circle(shapes: Array, expected_radius: float) -> bool:
	if shapes.size() != 1:
		return false
	var shape: Dictionary = shapes[0]
	return String(shape.get("type", "")) == "circle" and Vector2(shape.get("center", Vector2.INF)) == TREE_ANCHOR and float(shape.get("radius", -1.0)) == expected_radius


## Sample reveal-contract gate shared by both mounts. The definition's own
## validate() has already failed closed on unknown policies, variant-policy
## conflicts, and missing, malformed, non-finite or degenerate volumes; this
## layer only fixes the sample shape: the upper part must actually reveal —
## the historical authored pair or primitive fade — and a fade sample keeps
## common a solid base. Fade volumes are re-checked with the controller's own
## registration validator (the exact check the presenter applies), never a
## third shape validator. Legacy mounts keep their original requirement and
## message byte-for-byte.
func _sample_reveal_contract(upper: Dictionary, common: Dictionary, label: String, path: String) -> bool:
	var policy := String(upper.get("reveal_policy", ""))
	if policy == "none":
		printerr("PREVIEW REJECTED: ", label, "sample upper part must reveal, explicit policy 'none' does not: ", path)
		return false
	if policy == PrimitiveFade.POLICY:
		if upper.has("revealed_path") or upper.has("mask_path"):
			printerr("PREVIEW REJECTED: ", label, "primitive_fade upper part must not carry variant art: ", path)
			return false
		var volumes: Variant = upper.get("occlusion_volumes", [])
		if not volumes is Array or (volumes as Array).is_empty():
			printerr("PREVIEW REJECTED: ", label, "primitive_fade upper part needs occlusion volumes: ", path)
			return false
		for index in (volumes as Array).size():
			var invalid: String = PrimitiveFade._validate_volume((volumes as Array)[index])
			if not invalid.is_empty():
				printerr("PREVIEW REJECTED: ", label, "primitive_fade upper volume ", index, " fails registration validation (", invalid, "): ", path)
				return false
		var common_policy := String(common.get("reveal_policy", ""))
		if common_policy == PrimitiveFade.POLICY or common_policy == "authored_variant" or common.has("revealed_path") or common.has("mask_path"):
			printerr("PREVIEW REJECTED: ", label, "primitive_fade sample keeps common a solid base: policy none or unset, no variant art: ", path)
			return false
	elif String(upper.get("revealed_path", "")).is_empty() or String(upper.get("mask_path", "")).is_empty():
		printerr("PREVIEW REJECTED: ", label, "upper part needs an authored revealed variant and mask: ", path)
		return false
	return true


## Active reveal policy of a mounted definition's upper part; anything but an
## explicit primitive_fade is the historical authored_variant path.
func _definition_upper_policy(definition: Definition) -> String:
	for part: Dictionary in definition.visual_parts:
		if String(part.part_id) == "upper":
			var policy := String(part.get("reveal_policy", ""))
			return policy if policy == PrimitiveFade.POLICY else "authored_variant"
	return "authored_variant"


func _author_scene() -> bool:
	var ground := _blank(Vector2i(960, 640), Color("666d66"))
	for y in range(0, 640, 32):
		ground.fill_rect(Rect2i(0, y, 960, 1), Color("747b70"))
	for x in range(0, 960, 32):
		ground.fill_rect(Rect2i(x, 0, 1, 640), Color("747b70"))
	ground.fill_rect(Rect2i(12, 352, 936, 88), Color("938977"))
	ground.fill_rect(Rect2i(568, 12, 64, 616), Color("938977"))
	_outline(ground, Rect2i(206, 276, 140, 56), Color("e4bb67"))
	_outline(ground, Rect2i(212, 282, 128, 44), Color("aa6657"))
	for center: Vector2 in [Vector2(528, 338), Vector2(698, 428)]:
		_disc(ground, center, 21, Color("e4bb67"))
		_disc(ground, center, 14, Color("aa6657"))
	for box: Rect2i in [Rect2i(400, 478, 160, 20), Rect2i(640, 478, 160, 20)]:
		_outline(ground, box, Color("e4bb67"))
	var ground_path := _texture("ground", ground)
	# Candidate mode mounts the production sample in place of the greybox
	# building; the (148,148) placement compensates its +32,+32 canvas padding
	# so every world-space value stays identical (loadout sample spec parity).
	# Tree mode swaps the shared tree definition for the production pine at the
	# same two placements, so every binding id stays exactly as authored.
	var building: Resource = candidate_definition if candidate_definition != null else _building()
	var tree: Resource = tree_definition if tree_definition != null else _tree()
	var fence := _fence()
	var source := TownRoot.new()
	source.name = "GreyboxTown"
	source.world_size = Vector2(960, 640)
	source.modular_environment_objects = true
	source.modular_underplate_path = ground_path
	source.gameplay_source = "preview.spatial.json"
	for group: String in ["Ground", "GroundEffects", "SortRoot", "Foreground", "GeometrySources", "Sockets", "EnvironmentObjects"]:
		_add_node(source, group)
	source.get_node("SortRoot").y_sort_enabled = true
	for group: String in ["Static", "Routes", "MovementBoundary"]:
		_add_node(source.get_node("GeometrySources"), group)
	source.get_node("GeometrySources/MovementBoundary").set_meta("rect", Rect2(12, 12, 936, 616))
	source.get_node("GeometrySources/MovementBoundary").set_meta("binding_id", "town/movement-boundary")
	var lower := Definition.new()
	lower.asset_id = "greybox.continuous-ground"
	lower.canvas_size = Vector2i(960, 640)
	lower.ground_parts = [{"part_id": "underplate", "full_path": ground_path, "canvas_offset": Vector2.ZERO, "layer": "Ground"}]
	_place(source, "ground", lower, Vector2.ZERO)
	_place(source, "building", building, CANDIDATE_PLACEMENT if candidate_definition != null else Vector2(180, 180))
	_place(source, "tree-west", tree, Vector2(480, 210))
	_place(source, "tree-east", tree, Vector2(650, 300))
	_place(source, "gate-fence", fence, Vector2(400, 460))
	_socket(source, "Spawn", "spawn", "town/spawn", "spawn", Vector2(260, 180))
	_socket(source, "Contract", "interaction", "greybox/contract", "contract", Vector2(600, 540))
	var expanded := Baker.expand(source)
	_check(expanded.ok, "environment_baker_expand", expanded)
	if candidate_definition != null:
		_check_candidate_bake(source)
	if tree_definition != null:
		_check_tree_bake(source)
	if building_policy == PrimitiveFade.POLICY:
		_check_fade_bake(source, "building")
	if tree_policy == PrimitiveFade.POLICY:
		for index: int in TREE_PLACEMENT_IDS.size():
			_check_fade_bake(source, TREE_PLACEMENT_IDS[index])
	var contract := source.validate_contract()
	_check(contract.ok, "native_author_contract", {"errors": contract.errors})
	if errors.is_empty():
		_own_children(source, source)
		var packed := PackedScene.new()
		_check(packed.pack(source) == OK, "pack_owned_native_scene")
		_check(ResourceSaver.save(packed, output.path_join("preview.tscn")) == OK, "save_native_scene")
		var manifest := source.derive_spatial_manifest()
		var file := FileAccess.open(output.path_join("preview.spatial.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(manifest, "\t"))
	source.free()
	return errors.is_empty()


## Measure the baker's actual derived world data for the candidate building:
## anchor sprite positions in SortRoot, the baked envelope polygons in
## GeometrySources/Static, and the authored footprint composed with the
## placement exactly as the baker composes envelope and socket coordinates.
## Footprints have no baked node or manifest channel; see the schema note in
## the run report. Every check asserts exact expected structure (node counts
## and full world point sets), never a bounding extent, so missing, extra or
## reshaped parts fail instead of being skipped. Expectations come from the
## loadout sample spec parity table.
func _check_candidate_bake(source: Node) -> void:
	var common_count := 0
	var upper_count := 0
	var common_position := Vector2.ZERO
	var upper_position := Vector2.ZERO
	for node: Node2D in source.get_node("SortRoot").get_children():
		var binding := String(node.get_meta("binding_id", ""))
		if binding == "building/common":
			common_count += 1
			common_position = node.position
		elif binding == "building/upper":
			upper_count += 1
			upper_position = node.position
	_check(common_count == 1 and common_position == Vector2(276, 326),
		"candidate_anchor_common_world", {"count": common_count, "position": _pair(common_position)})
	_check(upper_count == 1 and upper_position == Vector2(276, 290),
		"candidate_anchor_upper_world", {"count": upper_count, "position": _pair(upper_position)})
	var envelope_parts := 0
	var envelope_points: Array = []
	for shape: Node in source.get_node("GeometrySources/Static").get_children():
		var polygon := shape as Polygon2D
		if polygon == null or not String(polygon.get_meta("binding_id", "")).begins_with("building/"):
			continue
		envelope_parts += 1
		for point: Vector2 in polygon.polygon:
			envelope_points.append(polygon.position + point)
	var envelope_expected := _point_keys([Vector2(206, 276), Vector2(346, 276), Vector2(346, 332), Vector2(206, 332)])
	_check(envelope_parts == 1 and _point_keys(envelope_points) == envelope_expected,
		"candidate_envelope_world_polygon", {"parts": envelope_parts, "points": envelope_points})
	var footprint_parts := 0
	var footprint_points: Array = []
	for shape: Dictionary in candidate_definition.footprints:
		footprint_parts += 1
		if String(shape.get("type", "")) != "polygon":
			continue
		for point: Vector2 in (shape.get("points", PackedVector2Array()) as PackedVector2Array):
			footprint_points.append(CANDIDATE_PLACEMENT + point)
	var footprint_expected := _point_keys([Vector2(212, 282), Vector2(340, 282), Vector2(340, 326), Vector2(212, 326)])
	_check(footprint_parts == 1 and _point_keys(footprint_points) == footprint_expected,
		"candidate_footprint_world_polygon", {"parts": footprint_parts, "points": footprint_points})


## Measure the baker's actual derived world data for both production pine
## instances: each part's anchor sprite in SortRoot, the baked envelope circle
## (an invisible Polygon2D carrying a radius meta) in GeometrySources/Static,
## and the authored footprint circle composed with each placement exactly as
## the baker composes envelope and socket coordinates. Footprints have no
## baked node or manifest channel, so the footprint check is honestly
## definition-composed, never presented as derived (schema note in the run
## report). Expectations come from the pine contract and the unchanged
## placements, with the composed world circles also cross-checked literally.
func _check_tree_bake(source: Node) -> void:
	for index: int in TREE_PLACEMENT_IDS.size():
		var placement_id := TREE_PLACEMENT_IDS[index]
		var anchor_world: Vector2 = TREE_PLACEMENTS[index] + TREE_ANCHOR
		for part_id: String in ["common", "upper"]:
			var count := 0
			var position := Vector2.ZERO
			for node: Node2D in source.get_node("SortRoot").get_children():
				if String(node.get_meta("binding_id", "")) == placement_id + "/" + part_id:
					count += 1
					position = node.position
			_check(count == 1 and position == anchor_world,
				"tree_anchor_%s_%s_world" % [placement_id, part_id], {"count": count, "position": _pair(position)})
		var circle_count := 0
		var circle_position := Vector2.ZERO
		var circle_radius := -1.0
		for shape: Node in source.get_node("GeometrySources/Static").get_children():
			var polygon := shape as Polygon2D
			if polygon == null or not polygon.has_meta("radius") or String(polygon.get_meta("binding_id", "")) != placement_id + "/envelope":
				continue
			circle_count += 1
			circle_position = polygon.position
			circle_radius = float(polygon.get_meta("radius"))
		_check(circle_count == 1 and circle_position == anchor_world and circle_radius == 14.0,
			"tree_envelope_%s_world_circle" % placement_id,
			{"count": circle_count, "center": _pair(circle_position), "radius": circle_radius})
	var footprint_shapes: Array = tree_definition.footprints
	var footprint_ok: bool = _single_pine_circle(footprint_shapes, 10.0)
	var composed_centers: Array = []
	if footprint_ok:
		for placement: Vector2 in TREE_PLACEMENTS:
			composed_centers.append(_pair(placement + Vector2(footprint_shapes[0].get("center", Vector2.ZERO))))
	_check(footprint_ok and composed_centers == [[528.0, 338.0], [698.0, 428.0]],
		"tree_footprint_composed_circles", {"shapes": footprint_shapes.size(), "world_centers": composed_centers})


## Bake-time ground truth for a primitive_fade mount, read from the baked node
## tree before the presenter touches anything: the upper sprite carries the
## fade policy and the definition's volumes translated to world space exactly
## as the baker composes them (placement.position added to every polygon
## point and circle center), no variant reveal metas, no material and
## untouched alpha; common stays a solid base with no volumes.
func _check_fade_bake(source: Node, placement_id: String) -> void:
	var upper: Sprite2D = null
	var common: Sprite2D = null
	for node: Node in source.get_node("SortRoot").get_children():
		if not node is Sprite2D:
			continue
		var binding := String(node.get_meta("binding_id", ""))
		if binding == placement_id + "/upper":
			upper = node
		elif binding == placement_id + "/common":
			common = node
	var definition: Definition = candidate_definition if placement_id == "building" else tree_definition
	var placement := CANDIDATE_PLACEMENT if placement_id == "building" else TREE_PLACEMENTS[TREE_PLACEMENT_IDS.find(placement_id)]
	var local_volumes: Variant = []
	for part: Dictionary in definition.visual_parts:
		if String(part.part_id) == "upper":
			local_volumes = part.get("occlusion_volumes", [])
	var world_volumes: Array = []
	for volume: Dictionary in local_volumes:
		var translated: Dictionary = volume.duplicate()
		if translated.get("type") == "polygon":
			var points := PackedVector2Array()
			for point: Vector2 in translated.get("points", PackedVector2Array()):
				points.append(point + placement)
			translated["points"] = points
		elif translated.get("type") == "circle":
			translated["center"] = Vector2(translated.get("center", Vector2.ZERO)) + placement
		world_volumes.append(translated)
	_check(upper != null and String(upper.get_meta("reveal_policy", "")) == PrimitiveFade.POLICY,
		"fade_bake_policy_meta_%s" % placement_id,
		{"policy": String(upper.get_meta("reveal_policy", "")) if upper != null else "missing"})
	_check(upper != null and upper.get_meta("occlusion_volumes", []) == world_volumes,
		"fade_bake_volumes_meta_%s" % placement_id,
		{"expected": world_volumes, "baked": upper.get_meta("occlusion_volumes", []) if upper != null else null})
	var literal: Array = []
	match placement_id:
		"building":
			literal = [{"type": "polygon", "points": PackedVector2Array([Vector2(185, 193), Vector2(369, 193), Vector2(369, 283), Vector2(185, 283)])}]
		"tree-west":
			literal = [{"type": "polygon", "points": PackedVector2Array([Vector2(485, 214), Vector2(575, 214), Vector2(575, 311), Vector2(485, 311)])}]
		"tree-east":
			literal = [{"type": "polygon", "points": PackedVector2Array([Vector2(655, 304), Vector2(745, 304), Vector2(745, 401), Vector2(655, 401)])}]
	_check(not literal.is_empty() and upper != null and upper.get_meta("occlusion_volumes", []) == literal,
		"fade_bake_volumes_literals_%s" % placement_id,
		{"literal": literal, "baked": upper.get_meta("occlusion_volumes", []) if upper != null else null})
	_check(upper != null and not upper.has_meta("reveal_variant_path") and not upper.has_meta("reveal_mask_path")
		and upper.material == null and upper.modulate.a == 1.0,
		"fade_bake_upper_clean_%s" % placement_id,
		{"variant_meta": upper != null and (upper.has_meta("reveal_variant_path") or upper.has_meta("reveal_mask_path")),
			"material": str(upper.material) if upper != null else "missing",
			"alpha": upper.modulate.a if upper != null else -1.0})
	_check(common != null and String(common.get_meta("reveal_policy", "")) == "none"
		and not common.has_meta("occlusion_volumes") and common.modulate.a == 1.0,
		"fade_bake_common_solid_%s" % placement_id,
		{"policy": String(common.get_meta("reveal_policy", "")) if common != null else "missing",
			"alpha": common.modulate.a if common != null else -1.0})


func _building() -> Resource:
	var definition := Definition.new()
	definition.asset_id = "greybox.building"
	definition.canvas_size = Vector2i(192, 160)
	var common := _blank(definition.canvas_size)
	common.fill_rect(Rect2i(32, 98, 128, 48), Color("b7ad91"))
	common.fill_rect(Rect2i(40, 108, 28, 20), Color("5f777d"))
	common.fill_rect(Rect2i(124, 108, 28, 20), Color("5f777d"))
	common.fill_rect(Rect2i(83, 110, 26, 36), Color("574b43"))
	var full := _blank(definition.canvas_size)
	var polygon := PackedVector2Array([Vector2(8, 96), Vector2(44, 16), Vector2(148, 16), Vector2(184, 96)])
	for y in range(16, 97):
		for x in range(8, 185):
			if Geometry2D.is_point_in_polygon(Vector2(x, y), polygon):
				full.set_pixel(x, y, Color("81584e") if y % 12 > 1 else Color("a0775d"))
	var revealed := _blank(definition.canvas_size)
	# Low structural stubs join the unchanged wall. A retained high beam
	# crossed the hero's torso in the preceding visual review.
	revealed.fill_rect(Rect2i(32, 84, 6, 14), Color("887052"))
	revealed.fill_rect(Rect2i(154, 84, 6, 14), Color("887052"))
	revealed.fill_rect(Rect2i(30, 82, 10, 4), Color("a0775d"))
	revealed.fill_rect(Rect2i(152, 82, 10, 4), Color("a0775d"))
	definition.visual_parts = [
		_visual("common", _texture("building_common", common), Vector2(96, 146)),
		_visual("upper", _texture("building_upper", full), Vector2(96, 110), _texture("building_revealed", revealed), _texture("building_mask", full)),
	]
	definition.footprints = [_polygon_shape("contact", Rect2(32, 102, 128, 44))]
	definition.movement_envelopes = [_polygon_shape("envelope", Rect2(26, 96, 140, 56))]
	return definition


func _tree() -> Resource:
	var definition := Definition.new()
	definition.asset_id = "greybox.tree-shared-definition"
	definition.canvas_size = Vector2i(96, 144)
	var trunk := _blank(definition.canvas_size)
	trunk.fill_rect(Rect2i(43, 52, 10, 85), Color("887052"))
	trunk.fill_rect(Rect2i(30, 66, 36, 6), Color("887052"))
	trunk.fill_rect(Rect2i(38, 132, 20, 6), Color("887052"))
	var canopy := _blank(definition.canvas_size)
	_disc(canopy, Vector2(48, 48), 43, Color("344e49"))
	_disc(canopy, Vector2(40, 40), 30, Color("4f6e5a"))
	canopy.fill_rect(Rect2i(44, 10, 8, 22), Color.TRANSPARENT)
	var revealed := _blank(definition.canvas_size)
	# Revealing only the complete common trunk avoids isolated leaf strips.
	definition.visual_parts = [
		_visual("common", _texture("tree_common", trunk), Vector2(48, 128)),
		_visual("upper", _texture("tree_upper", canopy), Vector2(48, 128), _texture("tree_revealed", revealed), _texture("tree_mask", canopy)),
	]
	definition.footprints = [{"part_id": "contact", "type": "circle", "center": Vector2(48, 128), "radius": 10.0}]
	definition.movement_envelopes = [{"part_id": "envelope", "type": "circle", "center": Vector2(48, 128), "radius": 14.0}]
	return definition


func _fence() -> Resource:
	var definition := Definition.new()
	definition.asset_id = "greybox.open-gate"
	definition.canvas_size = Vector2i(400, 64)
	var image := _blank(definition.canvas_size)
	for x: int in [0, 240]:
		image.fill_rect(Rect2i(x, 22, 160, 5), Color("c2b18a"))
		image.fill_rect(Rect2i(x, 8, 160, 5), Color("c2b18a"))
		for post in range(x, x + 160, 20):
			image.fill_rect(Rect2i(post, 2, 6, 36), Color("9c8463"))
	definition.visual_parts = [_visual("rails", _texture("gate_fence", image), Vector2(200, 36))]
	definition.footprints = [_polygon_shape("contact-left", Rect2(0, 24, 160, 8)), _polygon_shape("contact-right", Rect2(240, 24, 160, 8))]
	definition.movement_envelopes = [_polygon_shape("envelope-left", Rect2(0, 18, 160, 20)), _polygon_shape("envelope-right", Rect2(240, 18, 160, 20))]
	return definition


func _walkthrough() -> void:
	_advance(Vector2.ZERO, 1.0 / 30.0)
	await _capture("01_full")
	for index in range(30):
		_advance(Vector2.DOWN, 1.0 / 30.0)
		if _reveal_intermediate():
			await _capture("02_mid")
			break
		await process_frame
	_check(_reveal_intermediate(), "mounted_intermediate_reveal")
	await _move(Vector2.DOWN, 0.4, 60)
	_check(_reveal_open(), "mounted_building_open", view.occlusion_report())
	await _capture("03_open")
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		_advance(Vector2.ZERO, 1.0 / 60.0)
		if not _reveal_open():
			_check(false, "mounted_hold_lost_reveal", view.occlusion_report())
			break
		await process_frame
	await _capture("04_held")
	await _move(Vector2.RIGHT, 2.0, 60)
	await _move(Vector2.ZERO, 0.3, 60)
	_check(_reveal_closed(), "mounted_building_closed")
	await _capture("05_closed_pan")
	_place_hero(Vector2(260, 370))
	await _move(Vector2.UP, 1.0, 60)
	var blocked: Vector2 = controller.town.hero_world_position()
	_check(blocked.y >= 337.9 and blocked.y < 350, "building_movement_envelope_stops_actor", {"feet": _pair(blocked)})
	await _capture("06_near_blocker")
	_place_hero(Vector2(562, 305))
	await _move(Vector2.ZERO, 0.3, 60)
	await _capture("07_tree_behind_baseline")
	await _move(Vector2.DOWN, 0.5, 60)
	_check(controller.town.hero_world_position().y > 338, "tree_baseline_crossed_with_ticks")
	await _capture("08_tree_front_baseline")
	await _move(Vector2.RIGHT, 1.4, 60)
	_check(view.camera_world_offset().x > 300, "production_camera_pan", {"camera": _pair(view.camera_world_offset())})
	await _capture("09_second_tree_camera_pan")
	_place_hero(Vector2(520, 440))
	await _move(Vector2.DOWN, 0.8, 60)
	_check(controller.town.hero_world_position().y < 473, "fence_blocks_outside_gate")
	await _capture("10_fence_blocker")
	var endpoints: Array[Vector2] = []
	for fps: int in [30, 120]:
		_place_hero(Vector2(600, 440))
		var initial_tick: int = controller.town.snapshot().tick
		await _move(Vector2.DOWN, 1.0, fps)
		var through: Vector2 = controller.town.hero_world_position()
		_check(through.y > 530, "gate_passage_%dfps" % fps, {"feet": _pair(through)})
		await _capture("11_gate_passage_%dfps" % fps)
		await _move(Vector2.UP, 1.0, fps)
		var reversed: Vector2 = controller.town.hero_world_position()
		endpoints.append(reversed)
		_check(reversed.distance_to(Vector2(600, 440)) < 0.02, "gate_reversal_%dfps" % fps, {"feet": _pair(reversed)})
		_check(controller.town.snapshot().tick - initial_tick == 60, "fixed_tick_trace_%dfps" % fps)
		await _capture("12_gate_reversal_%dfps" % fps)
	_check(endpoints[0].distance_to(endpoints[1]) < 0.02, "30_120fps_endpoint_equivalence")


## Candidate-mode verification of what the runtime actually mounted: read back
## preview.spatial.json (authored definition -> baker -> derive_spatial_manifest,
## the file controller.mount consumed), check its derived world records, then
## walk the hero to the loadout door and confirm the stopped approach stays
## inside the derived interaction radius.
func _candidate_checks() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output.path_join("preview.spatial.json"))) as Dictionary
	_check(not manifest.is_empty(), "candidate_manifest_readable", {})
	if manifest.is_empty():
		return
	var metadata: Dictionary = manifest.get("gameplay_spatial_metadata", {}) as Dictionary
	# Exact full-shape comparison: the union of every world-space vertex the
	# mounted manifest carries for the building's static geometry must be
	# exactly the expected rectangle corners. Bounding extents are not enough.
	var envelope_points: Array = []
	for triangle: Dictionary in metadata.get("static_geometry", []) as Array:
		if not String(triangle.get("id", "")).begins_with("building/"):
			continue
		for point: Array in triangle.get("points", []) as Array:
			envelope_points.append(Vector2(point[0], point[1]))
	var envelope_expected := _point_keys([Vector2(206, 276), Vector2(346, 276), Vector2(346, 332), Vector2(206, 332)])
	_check(_point_keys(envelope_points) == envelope_expected,
		"candidate_envelope_mounted_polygon", {"points": envelope_points})
	var socket_world := Vector2.ZERO
	var socket_kind := ""
	for socket: Dictionary in manifest.get("spawn_interaction_exit_sockets", []) as Array:
		if String(socket.get("socket_id", "")) != "building/door.service":
			continue
		var position: Array = socket.get("position", [])
		socket_world = Vector2(position[0], position[1])
		socket_kind = String(socket.get("kind", ""))
	_check(socket_kind == "interaction" and socket_world == Vector2(276, 344),
		"candidate_loadout_socket_world", {"kind": socket_kind, "position": _pair(socket_world)})
	var facility := {}
	for entry: Dictionary in metadata.get("facilities", []) as Array:
		if String(entry.get("id", "")) == "loadout":
			facility = entry
	var facility_position: Array = facility.get("position", [0.0, 0.0])
	_check(not facility.is_empty() and Vector2(facility_position[0], facility_position[1]) == socket_world
		and float(facility.get("radius", 0.0)) == 48.0,
		"candidate_loadout_facility_record", {"facility": facility})
	var placed: Dictionary = controller.town.place_hero(Vector2(276, 400))
	_check(bool(placed.get("ok", false)), "candidate_place_door_approach", {"result": placed})
	_advance(Vector2.ZERO, 1.0 / 30.0)
	await _move(Vector2.UP, 2.5, 60)
	var approach: Vector2 = controller.town.hero_world_position()
	_check(approach.distance_to(socket_world) <= float(facility.get("radius", 0.0)),
		"candidate_loadout_door_reachable", {"feet": _pair(approach), "socket": _pair(socket_world),
			"radius": float(facility.get("radius", 0.0))})
	await _capture("13_loadout_door_approach")


## Tree-mode verification of what the runtime actually mounted: read back
## preview.spatial.json and require both instances' envelope circles in
## static_geometry exactly once, as authored circles at the composed world
## centers. Footprints have no manifest channel; their world circles are
## covered by the definition-composed bake check above.
func _tree_checks() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output.path_join("preview.spatial.json"))) as Dictionary
	_check(not manifest.is_empty(), "tree_manifest_readable", {})
	if manifest.is_empty():
		return
	var metadata: Dictionary = manifest.get("gameplay_spatial_metadata", {}) as Dictionary
	for index: int in TREE_PLACEMENT_IDS.size():
		var placement_id := TREE_PLACEMENT_IDS[index]
		var matches: Array = []
		for record: Dictionary in metadata.get("static_geometry", []) as Array:
			if String(record.get("id", "")) == placement_id + "/envelope":
				matches.append(record)
		_check(matches.size() == 1, "tree_envelope_%s_mounted_once" % placement_id, {"matches": matches})
		if matches.size() == 1:
			var record: Dictionary = matches[0]
			var center: Array = record.get("center", [])
			_check(String(record.get("kind", "")) == "circle" and center.size() == 2
				and Vector2(float(center[0]), float(center[1])) == TREE_PLACEMENTS[index] + TREE_ANCHOR
				and float(record.get("radius", -1.0)) == 14.0,
				"tree_envelope_%s_mounted_world_circle" % placement_id, {"record": record})


## Policy dispatch for the walkthrough building checks. Legacy mounts keep the
## exact historical weight semantics; fade mounts read the controller's own
## primitive_fade rows instead. Fade evidence is never aliased into
## authored_reveal — each accessor reads only its own report key.
func _reveal_intermediate() -> bool:
	if building_policy == PrimitiveFade.POLICY:
		var row := _fade_row("building/upper")
		var alpha := float(row.get("piece_alpha", -1.0))
		return bool(row.get("open", false)) and alpha > PrimitiveFade.FADED_ALPHA and alpha < 1.0
	var weight := _weight("building/upper")
	return weight > 0.0 and weight < 1.0


func _reveal_open() -> bool:
	if building_policy == PrimitiveFade.POLICY:
		var row := _fade_row("building/upper")
		return bool(row.get("open", false)) and float(row.get("piece_alpha", -1.0)) == PrimitiveFade.FADED_ALPHA
	return _weight("building/upper") == 1.0


func _reveal_closed() -> bool:
	if building_policy == PrimitiveFade.POLICY:
		var row := _fade_row("building/upper")
		return not bool(row.get("open", true)) and float(row.get("piece_alpha", -1.0)) == 1.0
	return _weight("building/upper") == 0.0


func _fade_row(id: String) -> Dictionary:
	var rows: Dictionary = view.occlusion_report().get("primitive_fade", {}) as Dictionary
	return rows.get(id, {}) as Dictionary


func _mounted_piece(binding: String) -> Sprite2D:
	if view.world_presenter == null:
		return null
	for node: Node in view.world_presenter.sort_root.get_children():
		if node is Sprite2D and String(node.get_meta("binding_id", "")) == binding:
			return node
	return null


## Live scene ground truth for a fade target: the real sprite alpha and the
## absence of any attached material (the silhouette fallback attaches one),
## asserted alongside the report rows rather than trusting report copies.
func _check_live_piece(binding: String, alpha: float, check_name: String) -> void:
	var piece := _mounted_piece(binding)
	_check(piece != null and piece.modulate.a == alpha and piece.material == null,
		check_name, {"alpha": piece.modulate.a if piece != null else -1.0,
			"material": str(piece.material) if piece != null else "missing"})


## Actors must stay fully opaque at every dedicated fade pose, not only at
## phase entry (d19 review): rechecked at each open, held and exit state.
func _check_actors_solid(state: String) -> void:
	for actor_id: String in view.actor_presentation_ids():
		_check(view.actor_alpha(actor_id) == 1.0, "fade_actor_live_alpha_" + state + "_" + actor_id.replace("/", "_"),
			{"actor": actor_id, "alpha": view.actor_alpha(actor_id), "state": state})


## Policy-specific primitive-fade evidence. Report rows are cross-checked
## against live sprites and real actor modulates; every hero placement goes
## through _place_hero so one real zero-input authority tick lands before any
## presentation settle is measured.
func _fade_checks() -> void:
	_check(PrimitiveFade.FADED_ALPHA == 0.25 and PrimitiveFade.TRANSITION_SECONDS == 0.18,
		"fade_independent_opacity_contract", {"alpha": PrimitiveFade.FADED_ALPHA, "seconds": PrimitiveFade.TRANSITION_SECONDS})
	var fade_audit: Dictionary = view.render_audit().get("primitive_fade", {}) as Dictionary
	_check(float(fade_audit.get("faded_alpha", -1.0)) == PrimitiveFade.FADED_ALPHA
		and float(fade_audit.get("transition_seconds", -1.0)) == PrimitiveFade.TRANSITION_SECONDS,
		"fade_contract_constants", fade_audit)
	for actor_id: String in view.actor_presentation_ids():
		_check(view.actor_alpha(actor_id) == 1.0, "fade_actor_live_alpha_" + actor_id.replace("/", "_"),
			{"actor": actor_id, "alpha": view.actor_alpha(actor_id)})
	if building_policy == PrimitiveFade.POLICY:
		await _fade_building_checks()
	if tree_policy == PrimitiveFade.POLICY:
		await _fade_tree_checks()


## Roof fade evidence with the ordering pair: (366,250) sits behind the upper
## baseline (290) with readability-box overlap and must settle at the
## quarter alpha; (366,300) still overlaps the broad box in front of the
## baseline and must stay fully solid with zero subject coverage, proving the
## sort gate — not geometry — decides. Both positions are outside the movement
## envelope (x>346), and the roof volume is placement-translated exactly.
func _fade_building_checks() -> void:
	var binding := "building/upper"
	var report: Dictionary = view.occlusion_report()
	_check(not report.get("authored_reveal", {}).has(binding),
		"fade_roof_not_aliased_into_authored_reveal", {"keys": report.get("authored_reveal", {}).keys()})
	_check(not report.get("silhouette_reveal", {}).has(binding),
		"fade_roof_no_silhouette_fallback", {"keys": report.get("silhouette_reveal", {}).keys()})
	_check(not report.get("primitive_fade", {}).has("building/common"),
		"fade_roof_common_not_faded", {"keys": report.get("primitive_fade", {}).keys()})
	_check(_fade_row(binding).get("volumes", []) == [{"type": "polygon",
			"points": [[185.0, 193.0], [369.0, 193.0], [369.0, 283.0], [185.0, 283.0]]}],
		"fade_roof_world_volumes_translated", {"volumes": _fade_row(binding).get("volumes", [])})
	_place_hero(Vector2(366, 250))
	await _move(Vector2.ZERO, FADE_SETTLE_SECONDS, 60)
	var behind := _fade_row(binding)
	_check(bool(behind.get("open", false)) and float(behind.get("piece_alpha", -1.0)) == PrimitiveFade.FADED_ALPHA,
		"fade_roof_behind_open_quarter", behind)
	_check_live_piece(binding, PrimitiveFade.FADED_ALPHA, "fade_roof_behind_live_alpha_material")
	_check(not (behind.get("actors", {}) as Dictionary).is_empty(), "fade_roof_behind_actor_covered", behind.get("actors", {}))
	_check_live_piece("building/common", 1.0, "fade_roof_behind_common_live_alpha")
	_check_actors_solid("roof_behind")
	await _capture("f1_roof_behind_faded")
	_place_hero(Vector2(366, 300))
	await _move(Vector2.ZERO, FADE_SETTLE_SECONDS, 60)
	var front := _fade_row(binding)
	_check(not bool(front.get("open", true)) and float(front.get("piece_alpha", -1.0)) == 1.0
		and float(front.get("coverage", -1.0)) == 0.0,
		"fade_roof_front_same_overlap_solid", front)
	_check((front.get("actors", {}) as Dictionary).is_empty(), "fade_roof_front_no_actor_coverage", front.get("actors", {}))
	_check_live_piece(binding, 1.0, "fade_roof_front_live_alpha_material")
	_check_live_piece("building/common", 1.0, "fade_roof_exit_common_live_alpha")
	_check_actors_solid("roof_exit")
	await _capture("f2_roof_front_solid")


## Both translated pine instances: the west pine opens at the quarter alpha
## behind its canopy, holds it, and restores full alpha on exit; the east pine
## proves the same lifecycle on the second instance independently. Positions
## are outside every movement envelope (circles r14, distances 38, 22 and 32).
func _fade_tree_checks() -> void:
	var report: Dictionary = view.occlusion_report()
	var world_volumes: Dictionary = {
		"tree-west/upper": [{"type": "polygon", "points": [[485.0, 214.0], [575.0, 214.0], [575.0, 311.0], [485.0, 311.0]]}],
		"tree-east/upper": [{"type": "polygon", "points": [[655.0, 304.0], [745.0, 304.0], [745.0, 401.0], [655.0, 401.0]]}]}
	for binding: String in world_volumes:
		var tag := binding.replace("/", "_")
		_check(not report.get("authored_reveal", {}).has(binding), "fade_pine_not_aliased_" + tag,
			{"keys": report.get("authored_reveal", {}).keys()})
		_check(not report.get("silhouette_reveal", {}).has(binding), "fade_pine_no_silhouette_" + tag,
			{"keys": report.get("silhouette_reveal", {}).keys()})
		_check(_fade_row(binding).get("volumes", []) == world_volumes[binding], "fade_pine_world_volumes_" + tag,
			{"volumes": _fade_row(binding).get("volumes", [])})
	# Enter the visible outer boughs from a closed state. The former triangle
	# missed this legal stand even though canopy pixels covered the hero.
	_place_hero(Vector2(528, 380))
	await _move(Vector2.ZERO, FADE_SETTLE_SECONDS, 60)
	_check(not bool(_fade_row("tree-west/upper").get("open", true)), "fade_pine_outer_bough_closed_start", _fade_row("tree-west/upper"))
	_place_hero(Vector2(505, 268))
	await _move(Vector2.ZERO, FADE_SETTLE_SECONDS, 60)
	_check(bool(_fade_row("tree-west/upper").get("open", false))
		and float(_fade_row("tree-west/upper").get("piece_alpha", -1.0)) == 0.25,
		"fade_pine_outer_bough_open_quarter", _fade_row("tree-west/upper"))
	_check_live_piece("tree-west/upper", 0.25, "fade_pine_outer_bough_live_alpha_material")
	_check_live_piece("tree-west/common", 1.0, "fade_pine_outer_bough_common_live_alpha")
	_check_actors_solid("pine_outer_bough")
	await _capture("f0_pine_outer_bough_faded")
	_place_hero(Vector2(528, 300))
	await _move(Vector2.ZERO, FADE_SETTLE_SECONDS, 60)
	var west := _fade_row("tree-west/upper")
	_check(bool(west.get("open", false)) and float(west.get("piece_alpha", -1.0)) == PrimitiveFade.FADED_ALPHA,
		"fade_pine_west_behind_open_quarter", west)
	_check_live_piece("tree-west/upper", PrimitiveFade.FADED_ALPHA, "fade_pine_west_live_alpha_material")
	_check(not (west.get("actors", {}) as Dictionary).is_empty(), "fade_pine_west_actor_covered", west.get("actors", {}))
	_check_live_piece("tree-west/common", 1.0, "fade_pine_west_common_live_alpha")
	_check_actors_solid("pine_west_open")
	await _capture("f3_pine_west_behind_faded")
	var hold_deadline := Time.get_ticks_msec() + 500
	while Time.get_ticks_msec() < hold_deadline:
		_advance(Vector2.ZERO, 1.0 / 60.0)
		if float(_fade_row("tree-west/upper").get("piece_alpha", -1.0)) != PrimitiveFade.FADED_ALPHA:
			_check(false, "fade_pine_west_hold_lost_quarter", _fade_row("tree-west/upper"))
			break
		await process_frame
	_check(float(_fade_row("tree-west/upper").get("piece_alpha", -1.0)) == PrimitiveFade.FADED_ALPHA,
		"fade_pine_west_hold_quarter", _fade_row("tree-west/upper"))
	_check_actors_solid("pine_west_hold")
	_place_hero(Vector2(528, 360))
	await _move(Vector2.ZERO, FADE_SETTLE_SECONDS, 60)
	var west_exit := _fade_row("tree-west/upper")
	_check(not bool(west_exit.get("open", true)) and float(west_exit.get("piece_alpha", -1.0)) == 1.0,
		"fade_pine_west_exit_restored", west_exit)
	_check_live_piece("tree-west/upper", 1.0, "fade_pine_west_exit_live_alpha_material")
	_check_live_piece("tree-west/common", 1.0, "fade_pine_west_exit_common_live_alpha")
	_check_actors_solid("pine_west_exit")
	await _capture("f4_pine_west_front_solid")
	_place_hero(Vector2(698, 390))
	await _move(Vector2.ZERO, FADE_SETTLE_SECONDS, 60)
	var east := _fade_row("tree-east/upper")
	_check(bool(east.get("open", false)) and float(east.get("piece_alpha", -1.0)) == PrimitiveFade.FADED_ALPHA,
		"fade_pine_east_behind_open_quarter", east)
	_check_live_piece("tree-east/upper", PrimitiveFade.FADED_ALPHA, "fade_pine_east_live_alpha_material")
	_check_live_piece("tree-east/common", 1.0, "fade_pine_east_common_live_alpha")
	_check_actors_solid("pine_east_open")
	await _capture("f5_pine_east_behind_faded")
	_place_hero(Vector2(698, 460))
	await _move(Vector2.ZERO, FADE_SETTLE_SECONDS, 60)
	var east_exit := _fade_row("tree-east/upper")
	_check(not bool(east_exit.get("open", true)) and float(east_exit.get("piece_alpha", -1.0)) == 1.0,
		"fade_pine_east_exit_restored", east_exit)
	_check_live_piece("tree-east/upper", 1.0, "fade_pine_east_exit_live_alpha_material")
	_check_live_piece("tree-east/common", 1.0, "fade_pine_east_exit_common_live_alpha")
	_check_actors_solid("pine_east_exit")
	if building_policy == PrimitiveFade.POLICY:
		_check(not bool(_fade_row("building/upper").get("open", true)),
			"fade_roof_untouched_during_pine_checks", _fade_row("building/upper"))


func _advance(direction: Vector2, delta: float) -> void:
	var result: Dictionary = controller.advance_frame(direction, delta)
	if not bool(result.get("ok", false)):
		errors.append("authoritative_move_failed:" + str(result))
	view.consume(controller.town.snapshot())
	view._process(delta)


func _move(direction: Vector2, seconds: float, fps: int) -> void:
	for frame in range(roundi(seconds * fps)):
		_advance(direction, 1.0 / fps)
		await process_frame


func _place_hero(point: Vector2) -> void:
	var placed: Dictionary = controller.town.place_hero(point)
	_check(bool(placed.get("ok", false)), "place_valid_trace_start", {"feet": _pair(point), "result": placed})
	_advance(Vector2.ZERO, 1.0 / 30.0)


func _weight(id: String) -> float:
	return float(view.occlusion_report().get("authored_reveal", {}).get(id, {}).get("weight", -1.0))


func _caption_text(name: String) -> String:
	var building_label := "PRODUCTION BUILDING"
	if building_policy == PrimitiveFade.POLICY:
		building_label = "PRODUCTION BUILDING PRIMITIVE FADE"
	var tree_label := "PRODUCTION PINES"
	if tree_policy == PrimitiveFade.POLICY:
		tree_label = "PRODUCTION PINES PRIMITIVE FADE"
	if candidate_definition != null and tree_definition != null:
		return "MIXED SAMPLE / " + building_label + " + " + tree_label + " ON GREYBOX GROUND AND FENCE / NOT TOWN ACCEPTANCE / " + name + " / 2x pixels"
	if candidate_definition != null:
		return "MIXED SAMPLE / " + building_label + " ON GREYBOX SURROUNDINGS / NOT TOWN ACCEPTANCE / " + name + " / 2x pixels"
	if tree_definition != null:
		return "MIXED SAMPLE / " + tree_label + " ON GREYBOX SURROUNDINGS / NOT TOWN ACCEPTANCE / " + name + " / 2x pixels"
	return "GREYBOX / RENDERER INTEGRATION ONLY / " + name + " / 2x pixels"


func _capture(name: String) -> void:
	caption.text = _caption_text(name)
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := output.path_join(name + ".png")
	_check(image != null and not image.is_empty() and image.save_png(path) == OK, "capture_" + name)
	var frame := {"name": name, "feet": _pair(controller.town.hero_world_position()),
		"camera": _pair(view.camera_world_offset()), "tick": controller.town.snapshot().tick,
		"occlusion": view.occlusion_report(), "sha256": FileAccess.get_sha256(path)}
	frames.append(frame)
	print("GREYBOX_FRAME ", JSON.stringify(frame))


func _check(ok: bool, name: String, detail: Dictionary = {}) -> void:
	checks.append({"check": name, "ok": ok, "detail": detail})
	if not ok:
		errors.append(name + ": " + JSON.stringify(detail))
		printerr("GREYBOX_FAIL ", name, " ", detail)


func _finish() -> void:
	var building_label := "one production loadout building"
	if building_policy == PrimitiveFade.POLICY:
		building_label += " (primitive_fade)"
	var tree_label := "two production pine instances"
	if tree_policy == PrimitiveFade.POLICY:
		tree_label += " (primitive_fade)"
	var classification := "GREYBOX TECHNICAL PREVIEW ONLY - NOT production-art acceptance"
	if candidate_definition != null and tree_definition != null:
		classification = "MIXED SAMPLE PREVIEW - " + building_label + " and " + tree_label + " over greybox ground and fence - NOT a complete town, NOT production-art acceptance"
	elif candidate_definition != null:
		classification = "MIXED SAMPLE PREVIEW - " + building_label + " over greybox ground, tree and fence - NOT a complete town, NOT production-art acceptance"
	elif tree_definition != null:
		classification = "MIXED SAMPLE PREVIEW - " + tree_label + " over greybox ground, building and fence - NOT a complete town, NOT production-art acceptance"
	var report := {"status": "pass" if errors.is_empty() else "fail",
		"classification": classification,
		"display": OS.get_environment("DISPLAY"), "audio": "Dummy (launch contract)",
		"renderer": RenderingServer.get_video_adapter_name(),
		"godot": Engine.get_version_info().string, "exit_code": 0 if errors.is_empty() else 1,
		"source_scene": output.path_join("preview.tscn"), "source_manifest": output.path_join("preview.spatial.json"),
		"checks": checks, "errors": errors, "frames": frames}
	if candidate_definition != null:
		report["candidate_definition"] = {"path": definition_path,
			"sha256": FileAccess.get_sha256(definition_path),
			"placement": [CANDIDATE_PLACEMENT.x, CANDIDATE_PLACEMENT.y],
			"reveal_policy": building_policy,
			"schema_note": "footprints have no baked node or manifest channel; the world footprint check composes the loaded definition's authored points with the placement"}
	if tree_definition != null:
		report["tree_definition"] = {"path": tree_definition_path,
			"sha256": FileAccess.get_sha256(tree_definition_path),
			"placements": [[TREE_PLACEMENTS[0].x, TREE_PLACEMENTS[0].y], [TREE_PLACEMENTS[1].x, TREE_PLACEMENTS[1].y]],
			"placement_ids": TREE_PLACEMENT_IDS,
			"reveal_policy": tree_policy,
			"schema_note": "footprints have no baked node or manifest channel; the world footprint circles are composed from the loaded definition with both placements"}
	var file := FileAccess.open(output.path_join("REPORT.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	var note := FileAccess.open(output.path_join("VISUAL_REPORT.txt"), FileAccess.WRITE)
	var fade_note := ""
	if building_policy == PrimitiveFade.POLICY or tree_policy == PrimitiveFade.POLICY:
		fade_note = ("Primitive fade evidence: fade targets settle at alpha " + str(PrimitiveFade.FADED_ALPHA)
			+ " behind the actor, common bases and actors stay fully opaque, and full alpha\n"
			+ "restores on exit; live sprite alpha and material ground truth is in REPORT.json.\n")
	if candidate_definition != null and tree_definition == null:
		note.store_string("MIXED SAMPLE preview, not a complete town and not production-art acceptance.\n"
			+ "One production loadout building (" + definition_path + ", reveal policy " + building_policy
			+ ", sha256 " + FileAccess.get_sha256(definition_path) + ") mounted at " + str(CANDIDATE_PLACEMENT)
			+ " replaces only the greybox building; ground, trees, gate, fence and every\n"
			+ "walkthrough assertion are unchanged greybox, and passing them on production\n"
			+ "art is the parity proof. Screenshots require human inspection; numeric checks\n"
			+ "alone do not establish visual quality.\n" + fade_note
			+ "Result: " + report.status + "\nErrors: " + str(errors) + "\n")
	elif tree_definition != null:
		note.store_string("MIXED SAMPLE preview, not a complete town and not production-art acceptance.\n"
			+ ("One production loadout building (" + definition_path + ", reveal policy " + building_policy
			+ ", sha256 " + FileAccess.get_sha256(definition_path) + ") mounted at " + str(CANDIDATE_PLACEMENT)
			+ " replaces the greybox building.\n" if candidate_definition != null else "")
			+ "Two production pine instances (" + tree_definition_path + ", reveal policy " + tree_policy
			+ ", sha256 " + FileAccess.get_sha256(tree_definition_path) + ") at " + str(TREE_PLACEMENTS[0]) + " and "
			+ str(TREE_PLACEMENTS[1]) + " replace both greybox trees, binding ids preserved.\n"
			+ "Ground, gate and fence" + (", and the building" if candidate_definition == null else "")
			+ " remain unchanged greybox; every\nwalkthrough assertion is unchanged, and passing it on production art is the\n"
			+ "parity proof. Screenshots require human inspection; numeric checks alone do\n"
			+ "not establish visual quality.\n" + fade_note
			+ "Result: " + report.status + "\nErrors: " + str(errors) + "\n")
	else:
		note.store_string("GREYBOX technical renderer preview, not hometown art acceptance.\n"
			+ "Generated continuous opaque ground; building common/upper/revealed parts;\n"
			+ "two translated instances of one tree definition; open gate and fence.\n"
			+ "Yellow ground markings show movement margins, rust marks show contact.\n"
			+ "Uses native SceneRuntime, projector, TownPresenter, real ranger, and fixed ticks.\n"
			+ "Screenshots require human inspection; numeric checks alone do not establish visual quality.\n"
			+ "Result: " + report.status + "\nErrors: " + str(errors) + "\n")
	note.close()
	print("MODULAR_TOWN_PREVIEW ", report.status, " output=", output)
	quit(report.exit_code)


func _texture(name: String, image: Image) -> String:
	var path := output.path_join(name + ".res")
	_check(ResourceSaver.save(ImageTexture.create_from_image(image), path) == OK, "save_texture_" + name)
	_check(image.save_png(output.path_join(name + "_source.png")) == OK, "save_source_" + name)
	return path


func _blank(size: Vector2i, color := Color.TRANSPARENT) -> Image:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return image


func _outline(image: Image, rect: Rect2i, color: Color) -> void:
	image.fill_rect(Rect2i(rect.position, Vector2i(rect.size.x, 2)), color)
	image.fill_rect(Rect2i(rect.position.x, rect.end.y - 2, rect.size.x, 2), color)
	image.fill_rect(Rect2i(rect.position, Vector2i(2, rect.size.y)), color)
	image.fill_rect(Rect2i(rect.end.x - 2, rect.position.y, 2, rect.size.y), color)


func _disc(image: Image, center: Vector2, radius: float, color: Color) -> void:
	for y in range(maxi(0, int(center.y - radius)), mini(image.get_height(), int(center.y + radius + 1))):
		for x in range(maxi(0, int(center.x - radius)), mini(image.get_width(), int(center.x + radius + 1))):
			if Vector2(x, y).distance_to(center) <= radius:
				image.set_pixel(x, y, color)


func _visual(id: String, path: String, anchor: Vector2, variant := "", mask := "") -> Dictionary:
	var part := {"part_id": id, "full_path": path, "canvas_offset": Vector2.ZERO, "sort_anchor": anchor, "sort_rank": 0}
	if not variant.is_empty():
		part.merge({"revealed_path": variant, "mask_path": mask})
	return part


func _polygon_shape(id: String, rect: Rect2) -> Dictionary:
	return {"part_id": id, "type": "polygon", "points": PackedVector2Array([
		rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])}


func _add_node(parent: Node, name: String) -> Node2D:
	var node := Node2D.new()
	node.name = name
	parent.add_child(node)
	return node


func _place(source: Node, id: String, definition: Resource, position: Vector2) -> void:
	var placement := Placement.new()
	placement.name = id
	placement.placement_id = id
	placement.definition = definition
	placement.position = position
	source.get_node("EnvironmentObjects").add_child(placement)


func _socket(source: Node, name: String, kind: String, binding: String, id: String, position: Vector2) -> void:
	var socket := Marker2D.new()
	socket.name = name
	socket.position = position
	for key: String in ["kind", "binding_id", "id", "label", "radius"]:
		socket.set_meta(key, {"kind": kind, "binding_id": binding, "id": id, "label": "GREYBOX contract", "radius": 32.0}[key])
	source.get_node("Sockets").add_child(socket)


func _own_children(parent: Node, owner_root: Node) -> void:
	for child: Node in parent.get_children():
		child.owner = owner_root
		_own_children(child, owner_root)


func _pair(point: Vector2) -> Array:
	return [point.x, point.y]


## Canonical comparable form for exact-polygon checks: unique formatted world
## points, sorted, so expected corner sets compare independently of winding,
## duplicate triangulation vertices or part naming.
func _point_keys(points: Array) -> Array:
	var unique := {}
	for point: Vector2 in points:
		unique["%.6f,%.6f" % [point.x, point.y]] = true
	var keys := unique.keys()
	keys.sort()
	return keys
