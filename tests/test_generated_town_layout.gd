extends SceneTree
## Production acceptance for a freshly composed whole-object town. The source
## scene remains authoritative; its detached spatial derivative must agree.
const NativeScene := preload("res://content/rooms/town/hearthside.tscn")
const TownControllerScript := preload("res://src/runtime/world/town_controller.gd")
const Spatial := preload("res://src/runtime/world/spatial_manifest.gd")
const ART_ROOT := "res://art/production/p1/generated_world_v02/"
const RECIPE_PATH := "res://docs/art-production/generated-world-v02/ground_footprints.json"
const ASSETS_PATH := "res://art/production/p1/generated_world_v02/assets.json"
const FACILITIES: Array[String] = ["contract", "loadout", "forge", "training", "proxy"]
const EXPANSION_ROOT := "res://art/production/p1/world_expansion_v01/"
const LAYOUT_PATH := "res://docs/art-production/world-expansion-20261025/town_layout.json"
const OWNER := "world_expansion_v01"
var failures: Array[String] = []


## Every expansion-owned visual and collider must equal the reviewed recipe:
## packed canvas/anchor/occlusion metadata, recipe floor footprints (never the
## full art), bridges flat in Ground, and terrain kinds present.
func _check_expansion(source: Node) -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	var packed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(EXPANSION_ROOT + "assets.json")).assets
	var old_packed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ASSETS_PATH)).assets
	var old_recipe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RECIPE_PATH))
	_expect(layout.status == "ready", "expansion recipe is not ready")
	var expected_ground := 1
	var owned_static := 0
	for item: Dictionary in layout.placements:
		var family := String(item.family)
		var old_family := family.begins_with("generated_world_v02/")
		var record: Dictionary = old_packed[family.trim_prefix("generated_world_v02/")] if old_family else packed.get(family, {})
		if family.contains("/") and not old_family:
			record = JSON.parse_string(FileAccess.get_file_as_string("res://" + String(layout.packs[family.get_slice("/", 0)]))).assets[family.get_slice("/", 1)]
		var group := "Ground" if record.get("reveal", true) == false else "SortRoot"
		if group == "Ground":
			expected_ground += 1
		var sprite := source.get_node_or_null(group + "/" + String(item.name)) as Sprite2D
		_expect(sprite != null and sprite.has_meta("expansion_owner"), "expansion placement missing from %s: %s" % [group, item.name])
		if sprite == null:
			continue
		var feet := Vector2(float(item.feet[0]), float(item.feet[1]))
		var anchor := Vector2(float(record.anchor[0]), float(record.anchor[1]))
		var path := String(record.get("path", record.get("opaque_path", "")))
		_expect(sprite.position == feet and sprite.offset == -anchor and not sprite.centered, "expansion sprite transform differs from recipe: " + String(item.name))
		_expect(String(sprite.get_meta("texture_path", "")) == path and sprite.texture != null and sprite.texture.get_size() == Vector2(float(record.canvas[0]), float(record.canvas[1])), "expansion texture/canvas mismatch: " + String(item.name))
		if group == "Ground":
			_expect(String(sprite.get_meta("binding_id", "")).contains("bridge") and sprite.get_meta("reveal_policy", "") == "none", "bridge deck must be flat ground art: " + String(item.name))
		else:
			_expect(sprite.get_meta("reveal_policy", "") == "paired_reveal" and String(sprite.get_meta("reveal_variant_path", "")) == String(record.transparent_path) and String(sprite.get_meta("reveal_full_path", "")) == path, "expansion pair metadata mismatch: " + String(item.name))
			var local: Array = record.occlusion_rect
			_expect(sprite.get_meta("occlusion_rect", Rect2()) == Rect2(feet - anchor + Vector2(float(local[0]), float(local[1])), Vector2(float(local[2]), float(local[3]))), "expansion detection rect mismatch: " + String(item.name))
		var shapes: Array = []
		var pad := float(old_recipe.padding_native_px) if old_family else float(layout.padding_native_px)
		var footprint: Dictionary = {"rects": [old_recipe.town[family.trim_prefix("generated_world_v02/")].rect]} if old_family else layout.footprints[family]
		for rect: Array in footprint.get("rects", []):
			var x := float(rect[0]) - pad
			var y := float(rect[1]) - pad
			var w := float(rect[2]) + 2.0 * pad
			var h := float(rect[3]) + 2.0 * pad
			shapes.append([Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)])
		for poly: Array in footprint.get("polygons", []):
			var points: Array = []
			for pair: Array in poly:
				points.append(Vector2(float(pair[0]), float(pair[1])))
			shapes.append(_outset(points, pad))
		_expect(group == "Ground" or not shapes.is_empty(), "sortable expansion object has no floor footprint: " + String(item.name))
		var occupied: Array = record.occupied_rect
		for index: int in shapes.size():
			var shape := source.get_node_or_null("GeometrySources/Static/%s_footprint_%d" % [item.name, index]) as Polygon2D
			_expect(shape != null, "expansion footprint missing: %s/%d" % [item.name, index])
			if shape == null:
				continue
			owned_static += 1
			var points: Array = shapes[index]
			var ok: bool = shape.polygon.size() == points.size()
			var box := Rect2(shape.polygon[0], Vector2.ZERO)
			for p: int in mini(points.size(), shape.polygon.size()):
				ok = ok and shape.polygon[p].distance_to(feet - anchor + (points[p] as Vector2)) < 0.001
				box = box.expand(shape.polygon[p])
			_expect(ok, "expansion footprint differs from recipe: %s/%d" % [item.name, index])
			_expect(box.size.y < float(occupied[3]), "footprint reverts to full projected art height: " + String(item.name))
	var kinds := {}
	for shape: Node in source.get_node("GeometrySources/Static").get_children():
		if shape.has_meta("expansion_owner") and String(shape.get_meta("collision_kind", "")) != "footprint":
			owned_static += 1
			kinds[String(shape.get_meta("collision_kind", ""))] = int(kinds.get(String(shape.get_meta("collision_kind", "")), 0)) + 1
		elif shape.has_meta("expansion_owner") and not String(shape.name).contains("_footprint_"):
			_expect(false, "unexpected expansion collider: " + String(shape.name))
	var all_owned := 0
	for shape: Node in source.get_node("GeometrySources/Static").get_children():
		all_owned += 1 if shape.has_meta("expansion_owner") else 0
	_expect(owned_static == all_owned, "stale or unlisted expansion colliders: %d/%d" % [owned_static, all_owned])
	_expect(int(kinds.get("water", 0)) == 1 + layout.placements.filter(func(p: Dictionary) -> bool: return (layout.footprints.get(p.family, {}) as Dictionary).has("deck")).size() and int(kinds.get("cliff", 0)) == layout.trace.cliffs.size(), "terrain collision kinds incomplete: " + str(kinds))
	_expect(source.get_node("Ground").get_child_count() == expected_ground, "unexpected ground patches in live town")
	var exit := source.get_node_or_null("Sockets/expedition") as Marker2D
	_expect(exit != null and exit.get_meta("kind", "") == "exit" and exit.get_meta("binding_id", "") == "town/exit/expedition" and float(exit.get_meta("radius", 0)) == 48.0 and exit.get_meta("gateway_action", "") == "contract", "expedition gate socket contract")


## An original native re-oriented by the reviewed town_order_v01 art keeps its
## node, feet, binding and interaction; art, detection rect and floor footprint
## must equal the new pack and recipe exactly.
func _check_override(source: Node, sprite: Sprite2D) -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	var name := String(sprite.name)
	var entry: Dictionary = layout.facility_overrides.get(name, {})
	_expect(not entry.is_empty() and String(sprite.get_meta("expansion_override", "")) == String(entry.get("family", "")), "unlisted facility override: " + name)
	if entry.is_empty():
		return
	var family := String(entry.family)
	var pack := family.get_slice("/", 0)
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://" + String(layout.packs[pack]))).assets[family.get_slice("/", 1)]
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ASSETS_PATH)).assets[String(entry.original)]
	_expect(record.status == "packed" and record.canvas == original.canvas and record.anchor == original.anchor, "override canvas/anchor differs from original: " + name)
	var anchor := Vector2(float(record.anchor[0]), float(record.anchor[1]))
	_expect(sprite.offset == -anchor and String(sprite.get_meta("binding_id", "")) == "town/native/" + name and String(sprite.get_meta("interaction", "")) == name, "override lost native binding: " + name)
	_expect(String(sprite.get_meta("environment_asset_id", "")) == family and String(sprite.get_meta("texture_path", "")) == String(record.path) and String(sprite.get_meta("reveal_full_path", "")) == String(record.path) and String(sprite.get_meta("reveal_variant_path", "")) == String(record.transparent_path), "override pair paths differ from pack: " + name)
	_expect(sprite.texture != null and sprite.texture.get_size() == Vector2(float(record.canvas[0]), float(record.canvas[1])), "override texture not loaded: " + name)
	var local: Array = record.occlusion_rect
	_expect(sprite.get_meta("occlusion_rect", Rect2()) == Rect2(sprite.position - anchor + Vector2(float(local[0]), float(local[1])), Vector2(float(local[2]), float(local[3]))), "override detection rect differs: " + name)
	var shape := source.get_node_or_null("GeometrySources/Static/%s_envelope" % name) as Polygon2D
	_expect(shape != null and String(shape.get_meta("expansion_override", "")) == family, "override envelope missing: " + name)
	if shape == null:
		return
	var raw: Array = []
	for pair: Array in layout.footprints[family].polygons[0]:
		raw.append(Vector2(float(pair[0]), float(pair[1])))
	var expected := _outset(raw, float(layout.padding_native_px))
	var ok := shape.polygon.size() == expected.size()
	for index: int in mini(expected.size(), shape.polygon.size()):
		ok = ok and shape.polygon[index].distance_to(sprite.position - anchor + (expected[index] as Vector2)) < 0.001
	_expect(ok, "override envelope differs from measured footprint: " + name)
	var box := Rect2(shape.polygon[0], Vector2.ZERO)
	for point: Vector2 in shape.polygon:
		box = box.expand(point)
	_expect((sprite.get_meta("occlusion_rect", Rect2()) as Rect2).encloses(box) and box.size.y < float(record.occupied_rect[3]), "override footprint reverts to projected art: " + name)


## Independent miter outset of a convex raw plinth outline by the shared pad.
func _outset(points: Array, pad: float) -> Array:
	var area := 0.0
	for i: int in points.size():
		area += (points[i] as Vector2).cross(points[(i + 1) % points.size()])
	var sign := 1.0 if area > 0.0 else -1.0
	var lines: Array = []
	for i: int in points.size():
		var a: Vector2 = points[i]
		var d: Vector2 = (points[(i + 1) % points.size()] as Vector2) - a
		lines.append([a + Vector2(d.y, -d.x).normalized() * sign * pad, d])
	var result: Array = []
	for i: int in points.size():
		var p: Vector2 = lines[i - 1][0]
		var d: Vector2 = lines[i - 1][1]
		var q: Vector2 = lines[i][0]
		var e: Vector2 = lines[i][1]
		result.append(p + d * ((q - p).cross(e) / d.cross(e)))
	return result


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var source := NativeScene.instantiate()
	var checked: Dictionary = source.validate_contract()
	_expect(bool(checked.get("ok", false)), "fresh author scene rejected: " + str(checked.get("errors", [])))
	if bool(checked.get("ok", false)):
		var contract: Dictionary = checked.value
		_expect(contract.unknown_underplate == "opaque", "ground under every object must be opaque")
		_expect(String(contract.ground_source_path) == EXPANSION_ROOT + "town_ground.png", "town ground is not the approved winding-river plate")
		_check_expansion(source)
		_expect(source.get_node("GroundEffects").get_child_count() == 0, "partial object shadows remain in live town")
		var surface := source.get_node("Ground/Surface") as Sprite2D
		var image := surface.texture.get_image()
		if image.is_compressed():
			image.decompress()
		image.convert(Image.FORMAT_RGBA8)
		_expect(image.get_size() == Vector2i(1536, 960), "ground crop changed world proportions")
		var bytes := image.get_data()
		var holes := 0
		for index: int in range(3, bytes.size(), 4):
			if bytes[index] != 255:
				holes += 1
		_expect(holes == 0, "new ground contains %d transparent pixels" % holes)
		var counts := {}
		var recipe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RECIPE_PATH))
		var recipe_pad := float(recipe.get("padding_native_px", 0.0))
		var town_recipe: Dictionary = recipe.get("town", {})
		var packed_assets: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ASSETS_PATH)).get("assets", {})
		var sort_root := source.get_node("SortRoot")
		var original := 0
		for child: Node in sort_root.get_children():
			_expect(child is Sprite2D, "object is not one complete sprite: " + String(child.name))
			if not child is Sprite2D or child.has_meta("expansion_owner"):
				continue
			original += 1
			var sprite := child as Sprite2D
			if sprite.has_meta("expansion_override"):
				_check_override(source, sprite)
				counts[String(sprite.get_meta("interaction", ""))] = int(counts.get(String(sprite.get_meta("interaction", "")), 0)) + 1
				continue
			var full := String(sprite.get_meta("texture_path", ""))
			var variant := String(sprite.get_meta("reveal_variant_path", ""))
			_expect(full.begins_with(ART_ROOT) and variant.begins_with(ART_ROOT), "old environment texture remains: " + String(sprite.name))
			_expect(sprite.get_meta("reveal_policy", "") == "paired_reveal", "object does not switch as a whole: " + String(sprite.name))
			_expect(sprite.get_meta("sort_rank", -1) == 0, "split object rank remains: " + String(sprite.name))
			_expect(not sprite.has_meta("occlusion_volumes") and not sprite.has_meta("reveal_mask_path"), "partial reveal data remains: " + String(sprite.name))
			var occupied := sprite.texture.get_image().get_used_rect()
			var family := String(sprite.get_meta("environment_asset_id", "")).trim_prefix("generated_world_v02/")
			var recipe_entry: Dictionary = town_recipe.get(family, {})
			_expect(not recipe_entry.is_empty(), "family has no reviewed ground footprint: " + family)
			var anchor := Vector2.ZERO
			if (packed_assets.get(family, {}) as Dictionary).has("anchor"):
				var pair: Array = packed_assets[family]["anchor"]
				anchor = Vector2(float(pair[0]), float(pair[1]))
			var footprint: Array = recipe_entry.get("rect", [])
			_expect(footprint.size() == 4, "footprint recipe is not one rect: " + family)
			var expected_box := Rect2(
				sprite.position - anchor + Vector2(float(footprint[0]) - recipe_pad, float(footprint[1]) - recipe_pad),
				Vector2(float(footprint[2]) + 2.0 * recipe_pad, float(footprint[3]) + 2.0 * recipe_pad))
			var shape := source.get_node_or_null("GeometrySources/Static/" + String(sprite.name) + "_envelope") as Polygon2D
			_expect(shape != null, "ground footprint collider missing: " + String(sprite.name))
			if shape != null:
				_expect(shape.polygon.size() == 4 and not shape.has_meta("radius"), "object retains a non-rect footprint body: " + String(sprite.name))
				var actual_box := Rect2(shape.position + shape.polygon[0], Vector2.ZERO)
				for point: Vector2 in shape.polygon:
					actual_box = actual_box.expand(shape.position + point)
				_expect(actual_box.is_equal_approx(expected_box), "collider must equal the recipe ground footprint plus pad: " + String(sprite.name))
				## Detection and collision are independent authorities: the
				## footprint must sit strictly inside the sprite's whole-object
				## detection rect and must not span the projected visual height.
				var detection: Rect2 = sprite.get_meta("occlusion_rect", Rect2())
				_expect(detection.encloses(actual_box), "footprint escapes the whole-object detection rect: " + String(sprite.name))
				_expect(actual_box.size.y < float(occupied.size.y), "footprint reverts to full projected height: " + String(sprite.name))
				_expect(is_equal_approx(actual_box.end.y, sprite.position.y + recipe_pad), "footprint loses ground contact at the feet: " + String(sprite.name))
			var interaction := String(sprite.get_meta("interaction", ""))
			if not interaction.is_empty():
				counts[interaction] = int(counts.get(interaction, 0)) + 1
		var original_shapes := 0
		for shape: Node in source.get_node("GeometrySources/Static").get_children():
			if not shape.has_meta("expansion_owner"):
				original_shapes += 1
		_expect(original > 0 and original == original_shapes, "each original whole object needs exactly one ground-footprint collider: %d/%d" % [original, original_shapes])
		for facility: String in FACILITIES:
			_expect(int(counts.get(facility, 0)) > 0, "facility has no visible clickable object: " + facility)
		var baked := Spatial.new(JSON.parse_string(FileAccess.get_file_as_string("res://content/rooms/town/hearthside.spatial.json")))
		_expect(Spatial.new(source.derive_spatial_manifest()).digest_input() == baked.digest_input(), "offline spatial derivative is stale")
	source.free()
	var controller := TownControllerScript.new()
	root.add_child(controller)
	var mounted: Dictionary = controller.mount(controller)
	_expect(bool(mounted.get("ok", false)), "generated town production mount failed: " + str(mounted))
	if bool(mounted.get("ok", false)):
		var town = controller.town
		for facility: String in FACILITIES:
			var entry: Dictionary = town.entry_for(facility)
			_expect(is_equal_approx(float(entry.radius), 48.0), "interaction reach changed: " + facility)
			_expect(town.place_hero(entry.feet).ok and town.nearby_feature_id() == facility, "facility approach is inaccessible: " + facility)
		for resident: Dictionary in town._content.residents:
			var actor = town.registry.actor("town/npc/" + String(resident.id))
			_expect(actor != null and town.registry.is_position_clear(actor.feet_position, Rect2(), actor.footprint_radius), "enlarged blockers overlap resident: " + String(resident.id))
		for id: String in town._content.routes:
			var points: Array[Vector2] = town.route_points(id)
			for index: int in range(1, points.size()):
				var start := points[index-1]
				var finish := points[index]
				var samples := maxi(1, ceili(start.distance_to(finish) / 2.0))
				for step: int in range(samples+1):
					_expect(town.hero_position_is_clear(start.lerp(finish, float(step)/samples)), "authored route crosses blocker: " + id)
	if controller.scene_runtime != null and controller.scene_runtime.simulation != null and controller.scene_runtime.simulation.kernel != null:
		controller.scene_runtime.simulation.kernel.shutdown()
	controller.free()
	for failure: String in failures:
		printerr(failure)
	print("GENERATED_TOWN_LAYOUT ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
