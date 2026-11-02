extends SceneTree

const Catalog := preload("res://src/runtime/world/room_catalog.gd")
const Presentation := preload("res://src/presentation/battlefield_scene.gd")
const WorldView := preload("res://src/presentation/arena_world_view.gd")
const Bake := preload("res://tools/world_manifest/bake_core.gd")
const Runtime := preload("res://src/runtime/world/scene_runtime.gd")
const Definition := preload("res://src/runtime/world/room_definition.gd")
const Asset := preload("res://src/runtime/world/world_asset.gd")
const Registry := preload("res://src/content/early_campaign_registry.gd")
const Assert := preload("res://tests/helpers/assert.gd")
const IDS := ["snowbound_road", "river_crossing", "ruined_village", "quarry_pass", "colossus_approach"]
const ROTATIONS := {
	"mainline_01_first_hunt": ["snowbound_road", "ruined_village"],
	"mainline_02_priority_under_pressure": ["river_crossing", "quarry_pass"],
	"mainline_03_first_elite": ["snowbound_road", "ruined_village"],
	"mainline_04_hazard_and_forge": ["quarry_pass", "river_crossing"],
	"mainline_05_growth_gate": ["ruined_village", "quarry_pass"],
	"threshold_colossus": ["snowbound_road", "ruined_village", "colossus_approach"],
	"auto_certification": ["river_crossing", "ruined_village"],
}
var failures: Array[String] = []

class MismatchedCatalog extends RoomCatalog:
	func resolve(room: Variant) -> Dictionary:
		var entry := super.resolve(room)
		if entry.get("ok", false) and room.get("layout_id", "") == "river_crossing":
			entry.world_scene_path = "res://content/rooms/combat/snowbound_road.tscn"
		return entry

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var catalog = Catalog.new()
	_expect(catalog.load_errors.is_empty(), "battlefield catalog invalid: %s" % str(catalog.load_errors))
	for id: String in IDS:
		_test_bake(catalog, id)
	_test_presentation(catalog)
	_test_failed_reload(catalog)
	_test_camera_projection()
	_test_camera_edges()
	_test_campaign()
	_test_river(catalog)
	for failure: String in failures:
		printerr("- %s" % failure)
	print("PASS test_battlefields.gd" if failures.is_empty() else "FAIL test_battlefields.gd")
	quit(0 if failures.is_empty() else 1)

func _test_failed_reload(catalog: RoomCatalog) -> void:
	var presentation := Presentation.new()
	_expect(presentation.load_assets(catalog), "reload fixture failed to load")
	_expect(not presentation.load_assets(MismatchedCatalog.new()), "mismatched native layout was accepted")
	_expect(presentation.pending_reason.contains("invalid native scene river_crossing"), "mismatched scene lacks diagnostic")
	for id: String in IDS:
		_expect(not presentation.has_layout(id), "failed reload retained layout " + id)
		_expect(presentation.floor_texture(id) == null and presentation.extension_texture(id) == null, "failed reload retained textures " + id)
	_expect(presentation.load_assets(catalog), "valid reload did not recover after failure")
	_expect(presentation.pending_reason.is_empty(), "successful reload retained failure diagnostic")
	_expect(not presentation.load_assets(null), "missing catalog was accepted")
	_expect(presentation.floor_texture(IDS[0]) == null, "missing catalog retained textures")

func _test_bake(catalog: RefCounted, id: String) -> void:
	var entry: Dictionary = catalog.resolve({"layout_id": id})
	_expect(bool(entry.get("ok", false)), "%s: missing catalog entry" % id)
	if not bool(entry.get("ok", false)):
		return
	var bake: Dictionary = Bake.bake_scene(entry.world_scene_path, entry.manifest_path)
	_expect(bool(bake.get("ok", false)), "%s: bake failed %s" % [id, str(bake.get("errors", []))])
	if not bool(bake.get("ok", false)):
		return
	var stored: Variant = JSON.parse_string(FileAccess.get_file_as_string(entry.manifest_path))
	_expect(bake.manifest == stored, "%s: committed manifest differs from native bake" % id)
	_expect(bake.world_asset.gameplay_digest == entry.gameplay_digest and bake.world_asset.presentation_digest == entry.presentation_digest, "%s: catalog digest differs from native bake" % id)
	var boundary: Dictionary = {}
	var terrain := 0
	for binding: Dictionary in bake.manifest.stable_bindings:
		var name := String(binding.binding_id)
		if name == "combat/movement-boundary":
			boundary = binding.geometry
		if name.begins_with("combat/terrain/"):
			terrain += 1
			_expect(String(binding.geometry.type) == "polygon" and bool(binding.channels.movement), "%s: terrain lacks solid polygon" % name)
	_expect(boundary.get("type", "") == "rect" and boundary.get("rect", []) == [-71.125, 25.5625, 1422.25, 888.875], "%s: battlefield extent is not the full rectangle" % id)
	_expect(terrain > 0, "%s: no terrain blockers" % id)

func _test_presentation(catalog: RefCounted) -> void:
	var presentation = Presentation.new()
	_expect(presentation.load_assets(catalog), "battlefield presentation failed: %s" % presentation.pending_reason)
	for id: String in IDS:
		if not presentation.has_layout(id):
			_expect(false, "%s: presentation missing" % id)
			continue
		var report: Dictionary = presentation.report(id)
		var floor_texture: Texture2D = presentation.floor_texture(id)
		var extension: Texture2D = presentation.extension_texture(id)
		_expect(extension != null and extension.get_size() == Vector2(1536, 1024), "%s: painted camera expansion missing" % id)
		_expect(floor_texture != null and floor_texture.get_size() == Vector2(1024, 640), "%s: production floor missing or wrong size" % id)
		if floor_texture != null:
			_expect(floor_texture.resource_path == "res://art/production/p1/battlefields_v01/%s.png" % id, "%s: production floor fell back to a placeholder" % id)
		_expect(report.bounds == Rect2(-71.125, 25.5625, 1422.25, 888.875), "%s: presentation extent differs" % id)
		var entry: Dictionary = catalog.resolve({"layout_id": id})
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(entry.manifest_path))
		var bindings := {}
		for binding: Dictionary in manifest.stable_bindings:
			bindings[binding.binding_id] = binding
		for terrain: Dictionary in report.terrain:
			var binding: Dictionary = bindings.get(terrain.binding_id, {})
			_expect(not binding.is_empty(), "%s: terrain source lacks collision" % terrain.binding_id)
			if binding.is_empty():
				continue
			var points: Array = binding.geometry.points
			_expect(points.size() == terrain.points.size(), "%s: terrain source polygon size differs" % terrain.binding_id)
			for i in mini(points.size(), terrain.points.size()):
				_expect(terrain.points[i].is_equal_approx(Vector2(points[i][0], points[i][1])), "%s: source and collision polygons differ" % terrain.binding_id)
		_expect(not (report.structures as Array).is_empty(), "%s: structure art is missing" % id)

func _test_camera_edges() -> void:
	var view = WorldView.new()
	_expect(view.load_assets(), "battlefield camera: production art failed to load")
	view.set_layout_id("snowbound_road")
	var bounds := Rect2(-71.125, 25.5625, 1422.25, 888.875)
	for size in [Vector2(1280, 720), Vector2(1600, 900)]:
		var clip := Rect2(Vector2.ZERO, size)
		for point in [bounds.position + Vector2(14, 14), bounds.end - Vector2(14, 14), Vector2(bounds.end.x - 14, bounds.position.y + 14), Vector2(bounds.position.x + 14, bounds.end.y - 14)]:
			view.begin_frame(clip, point, bounds)
			var feet: Vector2 = view.gameplay_to_screen(point)
			var silhouette := Rect2(feet - Vector2(40, 112), Vector2(80, 128))
			_expect(clip.encloses(silhouette), "battlefield camera clips hero at %s, %s: %s" % [point, size, silhouette])
			_expect(view.screen_to_gameplay(feet).is_equal_approx(point), "battlefield camera inverse changed at overscan")

func _test_camera_projection() -> void:
	var rendered := WorldView.new()
	var input := WorldView.new()
	_expect(rendered.load_assets(), "camera: rendered assets failed to load")
	var bounds := Rect2(-71.125, 25.5625, 1422.25, 888.875)
	var viewport := Rect2(Vector2.ZERO, Vector2(1280, 720))
	for id: String in IDS:
		rendered.set_layout_id(id)
		input.set_layout_id(id)
		for focus: Vector2 in [bounds.position + Vector2(30, 30), bounds.get_center(), bounds.end - Vector2(30, 30)]:
			rendered.begin_frame(viewport, focus, bounds)
			input.begin_frame(viewport, focus, bounds)
			var world_point := focus + Vector2(60, -22)
			var screen: Vector2 = rendered.gameplay_to_screen(world_point)
			_expect(input.gameplay_to_screen(world_point).is_equal_approx(screen), "%s: unloaded input camera differs from rendered camera at %s" % [id, str(focus)])
			_expect(input.screen_to_gameplay(screen).is_equal_approx(world_point), "%s: pointer inverse differs at %s" % [id, str(focus)])

func _test_campaign() -> void:
	var registry = Registry.new()
	_expect(registry.load_campaign().is_empty(), "battlefield campaign invalid")
	var campaign: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/early_campaign.json"))
	var used := {}
	for node: Dictionary in campaign.fixed_nodes:
		var rooms: Array = node.room_sequence
		if node.kind == "tutorial":
			_expect(rooms.size() == 1 and rooms[0].layout_id == "rectangle_arena", "tutorial fixture changed")
			continue
		_expect(rooms.size() >= 2, "%s: task has fewer than two stages" % node.id)
		var rotation: Array = []
		for room: Dictionary in rooms:
			rotation.append(room.layout_id)
		_expect(rotation == ROTATIONS.get(node.id, []), "%s: authored stage rotation changed: %s" % [node.id, str(rotation)])
		for room: Dictionary in rooms:
			_expect(room.layout_id in IDS, "%s: campaign uses a legacy fixture" % room.id)
			used[room.layout_id] = true
	_expect(used.size() == IDS.size(), "campaign does not use all five battlefields")
	for template: Dictionary in campaign.repeatable_templates:
		_expect((template.room_template.layout_ids as Array).size() == IDS.size(), "%s: missing battlefield choices" % template.id)
		for seed in range(30):
			var built: Dictionary = registry.instantiate_branch(template.id, seed)
			_expect(bool(built.get("ok", false)), "%s: seed %d failed" % [template.id, seed])
			if not bool(built.get("ok", false)):
				continue
			var rooms: Array = built.plan.rooms
			_expect(rooms.size() == 3, "%s: side task must have three stages" % template.id)
			for i in range(1, rooms.size()):
				_expect(rooms[i].layout_id != rooms[i - 1].layout_id, "%s: adjacent stages repeat at seed %d" % [template.id, seed])

func _test_river(catalog: RefCounted) -> void:
	var entry: Dictionary = catalog.resolve({"layout_id": "river_crossing"})
	if not bool(entry.get("ok", false)):
		return
	var runtime = Runtime.new()
	root.add_child(runtime)
	var definition = Definition.new({"room_id": "battlefield.test", "world_asset_id": "combat/river_crossing", "encounter_id": "encounter.none", "ruleset_id": "rules.default", "tags": ["test"]})
	var asset = Asset.new(entry.world_scene_path, entry.manifest_path, entry.gameplay_digest, entry.presentation_digest, 1)
	var mounted: Dictionary = runtime.mount(definition, asset, null, null, 0, 30)
	_expect(bool(mounted.get("ok", false)), "river: mount failed %s" % str(mounted))
	if bool(mounted.get("ok", false)):
		_expect(not runtime.is_position_clear(Vector2(600, 315.5625), 14.0), "river: water does not block movement")
		_expect(bool(runtime.register_actor("water", Vector2(400, 315.5625), 14.0).get("ok", false)), "river: water test start blocked")
		var blocked: Dictionary = runtime.move_actor("water", Vector2(300, 0), 1)
		_expect(bool(blocked.get("ok", false)) and bool(blocked.get("blocked", false)) and (blocked.get("position", Vector2.ZERO) as Vector2).x < 600.0, "river: movement passed through water: %s" % str(blocked))
		_expect(bool(runtime.register_actor("crossing", Vector2(400, 475.5625), 14.0).get("ok", false)), "river: crossing start blocked")
		# The legacy ring was centered at (640, 434), with a 97.6-pixel hole.
		# Move into that former hole, then continue to the opposite bank.
		var center_step: Dictionary = runtime.move_actor("crossing", Vector2(240, 0), 1)
		var center_position: Vector2 = center_step.get("position", Vector2.ZERO)
		_expect(bool(center_step.get("ok", false)) and center_position.distance_to(Vector2(640, 434)) < 97.6, "river: former ring center is not traversable: %s" % str(center_step))
		var crossed: Dictionary = runtime.move_actor("crossing", Vector2(160, 0), 2)
		_expect(bool(crossed.get("ok", false)) and (crossed.get("position", Vector2.ZERO) as Vector2).x > 790.0, "river: bridge crossing blocked: %s" % str(crossed))
		_expect(bool(runtime.register_actor("far", Vector2(200, 475.5625), 14.0).get("ok", false)), "river: space outside old circular limit is blocked")
		var moved: Dictionary = runtime.move_actor("far", Vector2(100, 0), 1)
		_expect(bool(moved.get("ok", false)) and (moved.get("position", Vector2.ZERO) as Vector2).x > 290.0, "river: movement outside former circle failed")
	runtime.unmount()
	root.remove_child(runtime)
	runtime.free()

func _expect(ok: bool, message: String) -> void:
	Assert.expect(ok, message, failures)
