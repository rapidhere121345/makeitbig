extends SceneTree

const Definition := preload("res://src/runtime/world/environment_object_definition.gd")
const Placement := preload("res://src/runtime/world/environment_object_placement.gd")
const Baker := preload("res://src/runtime/world/environment_object_baker.gd")
const Town := preload("res://src/runtime/world/town_scene_root.gd")
const Spatial := preload("res://src/runtime/world/spatial_manifest.gd")
const PREFIX := "res://build/current/environment_object_test_"
var failures: Array[String] = []
var created_files: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_write_image("full", Vector2i(8, 8), Color.FOREST_GREEN)
	_write_image("variant", Vector2i(8, 8), Color.SADDLE_BROWN)
	_write_image("mask", Vector2i(8, 8), Color.WHITE)
	_write_image("ground", Vector2i(64, 48), Color.DARK_SLATE_GRAY)
	_write_image("bad_size", Vector2i(4, 8), Color.WHITE)
	_test_instances_and_order()
	_test_rejections()
	_test_modular_contract()
	_test_digest_partition()
	_test_paired_policy()
	for path: String in created_files:
		DirAccess.remove_absolute(path)
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("PASS test_environment_object.gd" if failures.is_empty() else "FAIL test_environment_object.gd")
	quit(0 if failures.is_empty() else 1)


func _definition() -> Definition:
	var definition := Definition.new()
	definition.asset_id = "environment/test-tree"
	definition.canvas_size = Vector2i(8, 8)
	definition.visual_parts = [
		{"part_id": "base", "full_path": _path("full"), "canvas_offset": Vector2(-3, -7), "sort_anchor": Vector2(1, 2), "sort_rank": 1},
		{"part_id": "crown", "full_path": _path("full"), "canvas_offset": Vector2(-3, -7), "sort_anchor": Vector2(1, 3), "sort_rank": 2,
			"revealed_path": _path("variant"), "mask_path": _path("mask")},
	]
	definition.ground_parts = [
		{"part_id": "shadow", "full_path": _path("full"), "canvas_offset": Vector2(-4, -2), "layer": "GroundEffects"},
	]
	definition.footprints = [{"part_id": "contact", "type": "circle", "center": Vector2(1, 2), "radius": 1.0}]
	definition.movement_envelopes = [
		{"part_id": "blocker", "type": "circle", "center": Vector2(1, 2), "radius": 2.0},
		{"part_id": "wall", "type": "polygon", "points": PackedVector2Array([Vector2(-2, 0), Vector2(2, 0), Vector2(2, 3), Vector2(-2, 3)])},
	]
	definition.sockets = [{"part_id": "approach", "position": Vector2(0, 5), "kind": "spawn", "id": "tree-approach"}]
	return definition


func _town(definition: Definition = null, reverse := false) -> Town:
	var town := Town.new()
	town.name = "FixtureTown"
	town.world_size = Vector2(64, 48)
	town.modular_environment_objects = true
	town.modular_underplate_path = _path("ground")
	for path: String in ["Ground", "GroundEffects", "SortRoot", "Foreground", "GeometrySources", "GeometrySources/MovementBoundary", "GeometrySources/Static", "GeometrySources/Routes", "Sockets", "EnvironmentObjects"]:
		var node := Node2D.new()
		node.name = path.get_file()
		var parent := town if path.get_base_dir().is_empty() else town.get_node(path.get_base_dir())
		parent.add_child(node)
	town.get_node("SortRoot").y_sort_enabled = true
	town.get_node("GeometrySources/MovementBoundary").set_meta("rect", Rect2(0, 0, 64, 48))
	var surface := Sprite2D.new()
	surface.name = "Surface"
	surface.centered = false
	surface.set_meta("binding_id", "town/ground")
	surface.set_meta("texture_path", _path("ground"))
	surface.set_meta("reveal_policy", "none")
	town.get_node("Ground").add_child(surface)
	if definition != null:
		for id: String in (["east", "west"] if reverse else ["west", "east"]):
			var placement := Placement.new()
			placement.name = id
			placement.placement_id = id
			placement.definition = definition
			placement.position = Vector2(40, 25) if id == "east" else Vector2(15, 20)
			town.get_node("EnvironmentObjects").add_child(placement)
	return town


func _test_instances_and_order() -> void:
	var definition := _definition()
	var before := var_to_str([definition.visual_parts, definition.ground_parts, definition.footprints, definition.movement_envelopes, definition.sockets])
	var town := _town(definition)
	var report := Baker.expand(town)
	_expect(report.ok, "valid two-instance expansion rejected: " + str(report.errors))
	var crown := _binding(town, "west/crown") as Sprite2D
	var base := _binding(town, "west/base") as Sprite2D
	var circle := _binding(town, "west/blocker") as Polygon2D
	var polygon := _binding(town, "west/wall") as Polygon2D
	var socket := _binding(town, "west/approach") as Marker2D
	_expect(crown != null and base != null and circle != null and polygon != null and socket != null, "missing flattened leaves")
	if crown != null:
		_expect(crown.position == Vector2(16, 23) and crown.offset == Vector2(-4, -10), "anchor/offset translated more than once")
		_expect(crown.position + crown.offset == Vector2(12, 13), "visual canvas placement incorrect")
		_expect(crown.get_meta("sort_rank") == 2 and crown.get_meta("sort_stable_id") == "west/crown", "sort keys differ from binding")
		_expect(crown.get_meta("reveal_full_path") == _path("full") and crown.get_meta("reveal_variant_path") == _path("variant") and crown.get_meta("reveal_mask_path") == _path("mask"), "variant references missing")
		_expect(crown.get_meta("texture_path") == _path("full") and crown.texture.get_image().get_pixel(0, 0).g > 0.4, "full-state geometry texture replaced")
	if base != null:
		_expect(base.get_meta("reveal_policy") == "none" and not base.has_meta("reveal_variant_path"), "common base enters legacy reveal")
	if circle != null:
		_expect(circle.position == Vector2(16, 22) and circle.get_meta("radius") == 2.0, "circle translation or hidden inflation")
	if polygon != null:
		_expect(polygon.position == Vector2(15, 20) and polygon.polygon[0] == Vector2(-2, 0), "polygon translation duplicated")
	if socket != null:
		_expect(socket.position == Vector2(15, 25), "socket translation duplicated")
	_expect(town.get_node("SortRoot").get_child_count() == 4, "full/revealed generated duplicate sorted parts")
	_expect(town.get_node("GeometrySources/Static").get_child_count() == 4, "footprints accidentally became blockers")
	var count := town.get_node("SortRoot").get_child_count()
	_expect(Baker.expand(town).ok and town.get_node("SortRoot").get_child_count() == count, "repeat expansion is not idempotent")
	var other := _town(definition, true)
	_expect(Baker.expand(other).ok, "reverse order rejected")
	_expect(town.derive_spatial_manifest() == other.derive_spatial_manifest(), "insertion order changed derivative")
	_expect(_flatten_snapshot(town) == _flatten_snapshot(other), "insertion order changed leaf names/metadata")
	_expect(before == var_to_str([definition.visual_parts, definition.ground_parts, definition.footprints, definition.movement_envelopes, definition.sockets]), "shared author resource mutated")
	town.free()
	other.free()


func _test_rejections() -> void:
	for mutation: String in ["rotation", "scale", "reflection", "skew", "nonfinite", "top_level", "duplicate_placement", "duplicate_part", "bad_part_id", "missing_full", "missing_variant", "missing_mask", "missing_variant_art", "missing_mask_art", "bad_variant_size", "bad_mask_size", "bad_polygon", "bad_radius", "bad_offset", "bad_rank", "negative_rank", "container_transform", "binding_collision"]:
		var definition := _definition()
		var town := _town(definition)
		var placement := town.get_node("EnvironmentObjects/west") as Placement
		match mutation:
			"rotation": placement.rotation = 0.1
			"scale": placement.scale = Vector2(2, 1)
			"reflection": placement.scale = Vector2(-1, 1)
			"skew": placement.skew = 0.1
			"nonfinite": placement.position = Vector2(NAN, 0)
			"top_level": placement.set_as_top_level(true)
			"duplicate_placement": placement.placement_id = "east"
			"duplicate_part": definition.visual_parts[1].part_id = "base"
			"bad_part_id": definition.visual_parts[1].part_id = 42
			"missing_full": definition.visual_parts[1].full_path = _path("missing")
			"missing_variant": definition.visual_parts[1].erase("revealed_path")
			"missing_mask": definition.visual_parts[1].erase("mask_path")
			"missing_variant_art": definition.visual_parts[1].revealed_path = _path("missing")
			"missing_mask_art": definition.visual_parts[1].mask_path = _path("missing")
			"bad_variant_size": definition.visual_parts[1].revealed_path = _path("bad_size")
			"bad_mask_size": definition.visual_parts[1].mask_path = _path("bad_size")
			"bad_polygon": definition.movement_envelopes[1].points = PackedVector2Array([Vector2.ZERO, Vector2.ONE])
			"bad_radius": definition.movement_envelopes[0].radius = INF
			"bad_offset": definition.visual_parts[0].canvas_offset = Vector2.INF
			"bad_rank": definition.visual_parts[0].sort_rank = 1.5
			"negative_rank": definition.visual_parts[0].sort_rank = -1
			"container_transform": town.get_node("EnvironmentObjects").position.x = 2
			"binding_collision": town.get_node("Ground/Surface").set_meta("binding_id", "west/base")
		var report := Baker.expand(town)
		_expect(not report.ok and not report.errors.is_empty(), "accepted invalid source: " + mutation)
		_expect(town.get_node("SortRoot").get_child_count() == 0 and town.get_node("GeometrySources/Static").get_child_count() == 0, "failed preflight partially expanded: " + mutation)
		town.free()
	var town := _town(_definition())
	_expect(Baker.expand(town).ok, "source-change fixture rejected")
	var circle := _binding(town, "west/blocker") as Node2D
	circle.position.x += 1
	_expect(not Baker.expand(town).ok, "silently replaced edited authority")
	town.free()
	town = _town(_definition())
	_expect(Baker.expand(town).ok, "source-change fixture rejected")
	town.get_node("EnvironmentObjects/west").position.x += 1
	_expect(not Baker.expand(town).ok, "silently rebuilt changed source")
	town.free()
	town = _town(_definition())
	root.add_child(town)
	_expect(not Baker.expand(town).ok, "live runtime accepted author expansion")
	root.remove_child(town)
	town.free()


func _test_modular_contract() -> void:
	var town := _town(_definition())
	var report := town.validate_contract()
	_expect(report.ok, "modular contract rejected: " + str(report.errors))
	if report.ok:
		_expect(report.value.unknown_underplate == "opaque" and not report.value.supports_fade, "modular path reused legacy layer claims")
		_expect(Spatial.new(report.value.spatial_manifest).is_valid(), "modular derivative invalid")
	town.free()
	town = _town(_definition())
	town.modular_underplate_path = ""
	_expect(not town.validate_contract().ok, "missing lower layer accepted")
	town.free()
	_write_image("hole", Vector2i(64, 48), Color.TRANSPARENT)
	town = _town(_definition())
	town.modular_underplate_path = _path("hole")
	town.get_node("Ground/Surface").set_meta("texture_path", _path("hole"))
	_expect(not town.validate_contract().ok, "transparent lower layer accepted")
	town.free()
	town = _town(_definition())
	town.get_node("Ground/Surface").position.x = 1
	_expect(not town.validate_contract().ok, "shifted lower layer accepted")
	town.free()
	town = _town(_definition())
	town.get_node("Ground/Surface").set_meta("reveal_policy", "authored_variant")
	_expect(not town.validate_contract().ok, "revealable underplate accepted")
	town.free()
	for flip: String in ["flip_h", "flip_v"]:
		town = _town(_definition())
		_expect(Baker.expand(town).ok, "flip fixture failed to expand")
		_binding(town, "west/crown").set(flip, true)
		_expect(not town.validate_contract().ok, "flipped full mask accepted: " + flip)
		town.free()
	for override: String in ["z_index", "modulate", "visible"]:
		town = _town(_definition())
		_expect(Baker.expand(town).ok, "override fixture failed to expand")
		var visual := _binding(town, "west/crown") as Sprite2D
		match override:
			"z_index": visual.z_index = 20
			"modulate": visual.modulate = Color(0.5, 0.5, 0.5)
			"visible": visual.visible = false
		_expect(not town.validate_contract().ok, "unfingerprinted visual override accepted: " + override)
		town.free()


## Whole-object generated policy: one part carries the opaque/transparent
## pair and ONE local-canvas detection rect (occupied AABB grown by 8),
## translated to world space at bake time like the primitive volumes.
func _paired_definition() -> Definition:
	var definition := Definition.new()
	definition.asset_id = "environment/test-paired"
	definition.canvas_size = Vector2i(8, 8)
	definition.visual_parts = [
		{"part_id": "whole", "full_path": _path("full"), "canvas_offset": Vector2(-3, -7), "sort_anchor": Vector2(1, 2), "sort_rank": 0,
			"reveal_policy": "paired_reveal", "revealed_path": _path("variant"), "occlusion_rect": Rect2(-8, -8, 24, 24)},
	]
	definition.footprints = [{"part_id": "contact", "type": "circle", "center": Vector2(1, 2), "radius": 1.0}]
	return definition


func _test_paired_policy() -> void:
	var definition := _paired_definition()
	_expect(definition.validate().is_empty(), "paired: valid whole-pair definition rejected: " + str(definition.validate()))
	var town := _town(definition)
	_expect(Baker.expand(town).ok, "paired: bake failed")
	var whole := _binding(town, "west/whole")
	_expect(whole != null and String(whole.get_meta("reveal_policy")) == "paired_reveal", "paired: policy meta missing")
	_expect(String(whole.get_meta("reveal_full_path")) == _path("full") and String(whole.get_meta("reveal_variant_path")) == _path("variant"),
		"paired: pair paths lost at bake")
	_expect(not whole.has_meta("reveal_mask_path") and not whole.has_meta("occlusion_volumes"), "paired: foreign metas leaked")
	## Local rect (-8,-8,24,24) at the west placement (15,20) -> world (7,12,24,24).
	_expect(whole.get_meta("occlusion_rect") == Rect2(7, 12, 24, 24), "paired: detection rect not placement-translated")
	var report := town.validate_contract()
	_expect(report.ok, "paired: contract rejected: " + str(report.errors))
	if report.ok:
		var bindings: Array = report.value.paired_reveal_bindings
		_expect(bindings.has("west/whole") and bindings.has("east/whole"), "paired: bindings missing from contract")
		_expect(Spatial.new(report.value.spatial_manifest).is_valid(), "paired: manifest invalid")
	town.free()
	## Fail-closed authoring rejections.
	for variant_case: Dictionary in [
		{"drop": "revealed_path", "label": "missing variant"},
		{"set": {"mask_path": _path("mask")}, "label": "mask conflict"},
		{"set": {"occlusion_volumes": []}, "label": "volumes conflict"},
		{"drop": "occlusion_rect", "label": "missing rect"},
		{"set": {"occlusion_rect": Rect2(0, 0, 8, 8)}, "label": "rect smaller than occupied.grow(8)"},
		{"set": {"occlusion_rect": "not-a-rect"}, "label": "non-rect detection"},
	]:
		var bad := _paired_definition()
		var part: Dictionary = bad.visual_parts[0]
		if variant_case.has("drop"):
			part.erase(String(variant_case["drop"]))
		if variant_case.has("set"):
			for key: String in variant_case["set"]:
				part[key] = variant_case["set"][key]
		_expect(not bad.validate().is_empty(), "paired: " + String(variant_case.label) + " accepted")
	## Variant pixels belong to the presentation digest.
	var town2 := _town(_paired_definition())
	var baseline := Spatial.new(town2.derive_spatial_manifest())
	_expect(baseline.is_valid(), "paired digest fixture invalid")
	town2.free()
	_write_image("variant", Vector2i(8, 8), Color.CORNFLOWER_BLUE)
	town2 = _town(_paired_definition())
	var changed := Spatial.new(town2.derive_spatial_manifest())
	_expect(changed.presentation_digest_sha256() != baseline.presentation_digest_sha256(), "paired: variant pixels did not change presentation digest")
	_expect(changed.gameplay_digest_sha256() == baseline.gameplay_digest_sha256(), "paired: variant pixels changed gameplay digest")
	town2.free()
	_write_image("variant", Vector2i(8, 8), Color.SADDLE_BROWN)


func _test_digest_partition() -> void:
	var town := _town(_definition())
	var baseline := Spatial.new(town.derive_spatial_manifest())
	_expect(baseline.is_valid(), "digest fixture invalid")
	town.free()
	for role: String in ["variant", "mask", "full", "ground"]:
		var size := Vector2i(64, 48) if role == "ground" else Vector2i(8, 8)
		var original := Image.new()
		original.load(_path(role))
		# Rewrite the same reference: the digest must include actual pixels.
		_write_image(role, size, Color.CORNFLOWER_BLUE)
		town = _town(_definition())
		var changed := Spatial.new(town.derive_spatial_manifest())
		_expect(changed.is_valid(), "changed " + role + " fixture invalid")
		_expect(changed.presentation_digest_sha256() != baseline.presentation_digest_sha256(), role + " bytes did not change presentation digest")
		_expect(changed.gameplay_digest_sha256() == baseline.gameplay_digest_sha256(), role + " changed gameplay digest")
		town.free()
		original.save_png(_path(role))
	var definition := _definition()
	definition.movement_envelopes[0].center += Vector2(1, 0)
	town = _town(definition)
	var moved := Spatial.new(town.derive_spatial_manifest())
	_expect(moved.gameplay_digest_sha256() != baseline.gameplay_digest_sha256(), "moving blocker did not change gameplay digest")
	_expect(moved.presentation_digest_sha256() == baseline.presentation_digest_sha256(), "moving blocker changed presentation digest")
	town.free()
	town = _town(_definition())
	var derived := town.derive_spatial_manifest()
	for binding: Dictionary in derived.stable_bindings:
		if binding.get("kind", "") == "native_visual":
			_expect(String(binding.get("source", "")).begins_with("town.modular.visual.v1:"), "visual lacks presentation resource fingerprint")
			if binding.binding_id == "town/ground":
				_expect(not binding.channels.occlusion, "ground falsely became an occluder")
	town.free()


func _flatten_snapshot(town: Node) -> Array:
	var result: Array = []
	for group: String in Baker.TARGETS:
		for node: Node in town.get_node(group).get_children():
			if node.has_meta("_environment_entry"):
				result.append([String(node.name), node.get_meta("_environment_entry")])
	return result


func _binding(node: Node, id: String) -> Node:
	if node.get_meta("binding_id", "") == id:
		return node
	for child: Node in node.get_children():
		var found := _binding(child, id)
		if found != null:
			return found
	return null


func _write_image(id: String, size: Vector2i, color: Color) -> void:
	var path := _path(id)
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(color)
	_expect(image.save_png(path) == OK, "synthetic image write failed: " + path)
	if path not in created_files:
		created_files.append(path)


func _path(id: String) -> String:
	return PREFIX + str(OS.get_process_id()) + "_" + id + ".png"


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
