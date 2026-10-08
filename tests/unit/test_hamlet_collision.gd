extends SceneTree
## Standalone base walking geometry checks; never starts combat or writes saves.
const CollisionScript = preload("res://src/presentation/hamlet_collision.gd")
const ViewScript = preload("res://src/presentation/hamlet_concept_view.gd")
const BOUNDS := Rect2(20, 20, 984, 600)
var failures: Array[String] = []


func _initialize() -> void:
	_test_sweep_and_slide()
	_test_narrow_passages()
	_test_legacy_and_reconfigure()
	_test_live_layout()
	_test_live_view()
	if failures.is_empty():
		print("PASS  test_hamlet_collision.gd")
		quit(0)
	else:
		for failure: String in failures:
			printerr("- " + failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _geometry(shapes: Array) -> RefCounted:
	var collision = CollisionScript.new()
	collision.configure({"collision": {"hero_radius": 6, "world": shapes}})
	return collision


func _test_sweep_and_slide() -> void:
	var collision = _geometry([{"id": "wall", "kind": "rect", "rect": [200,100,40,220]}])
	var stopped: Vector2 = collision.move(Vector2(100,200), Vector2(800,0), BOUNDS)
	_expect(absf(stopped.x - 194) < 0.01 and stopped.y == 200, "sweep: long step crossed a building")
	var slide: Vector2 = collision.move(Vector2(180,150), Vector2(60,100), BOUNDS)
	_expect(absf(slide.x - 194) < 0.01 and absf(slide.y - 250) < 0.01 and not collision.is_blocked(slide), "slide: diagonal movement did not preserve tangent distance")
	var reverse: Vector2 = collision.move(Vector2(180,250), Vector2(60,-100), BOUNDS)
	_expect(absf(reverse.x - 194) < 0.01 and absf(reverse.y - 150) < 0.01, "slide: north/south wall response is asymmetric")
	for hz in [30,60,144]:
		var position := Vector2(180,150)
		for frame in hz:
			position = collision.move(position, Vector2(60,100) / float(hz), BOUNDS)
		_expect(position.distance_to(slide) < 0.02, "slide: continuous movement changed at %s Hz: %s vs %s" % [hz, position, slide])
	var corner = _geometry([
		{"kind": "rect", "rect": [200,100,40,220]},
		{"kind": "rect", "rect": [100,280,100,40]},
	])
	var wedged: Vector2 = corner.move(Vector2(160,200), Vector2(800,800), BOUNDS)
	_expect(wedged.x < 194.01 and wedged.y < 274.01 and not corner.is_blocked(wedged), "slide: inside corner allowed penetration")
	var disc = _geometry([{"kind": "circle", "center": [300,200], "radius": 7}])
	_expect(absf(disc.move(Vector2(200,200), Vector2(700,0), BOUNDS).x - 287) < 0.01, "sweep: long step crossed resident feet")
	var glanced: Vector2 = disc.move(Vector2(270,180), Vector2(50,30), BOUNDS)
	_expect(not disc.is_blocked(glanced) and glanced.x > 280 and glanced.y < 210, "slide: circle did not deflect diagonal movement")
	var boundary_slide: Vector2 = collision.move(Vector2(40,400), Vector2(-60,100), BOUNDS)
	_expect(boundary_slide.is_equal_approx(Vector2(20,500)), "bounds: diagonal movement lost its tangent component")


func _test_narrow_passages() -> void:
	var collision = _geometry([
		{"kind": "rect", "rect": [200,100,40,100]},
		{"kind": "rect", "rect": [200,214,40,100]},
	])
	_expect(collision.move(Vector2(100,207), Vector2(300,0), BOUNDS).distance_to(Vector2(400,207)) < 0.01, "passage: 14px gap closed around a 12px foot disc")
	var solid = _geometry([
		{"kind": "rect", "rect": [200,100,40,100]},
		{"kind": "rect", "rect": [200,210,40,100]},
	])
	var narrow_stop: Vector2 = solid.move(Vector2(100,205), Vector2(300,0), BOUNDS)
	_expect(narrow_stop.x < 200 and not solid.is_blocked(narrow_stop), "passage: 10px gap admitted a 12px foot disc at %s" % narrow_stop)
	# Rounded footprint corners must leave diagonally adjacent open ground usable.
	_expect(not collision.is_blocked(Vector2(195,95)), "passage: rectangle corners use a square invisible expansion")


func _test_legacy_and_reconfigure() -> void:
	var collision = _geometry([{"kind": "circle", "center": [300,200], "radius": 20}])
	collision.configure({"placements": [{"id": "building", "feet": [300,200]}]})
	_expect(collision.footprints().is_empty(), "legacy: reconfigure retained old obstacles")
	_expect(collision.move(Vector2(100,200), Vector2(300,0), BOUNDS) == Vector2(400,200), "legacy: absent collision fields changed walking")
	_expect(collision.move(Vector2(100,200), Vector2(-10000,0), BOUNDS) == Vector2(20,200), "legacy: exact world clamping changed")
	collision.configure({"placements": [{"id": "trunk", "feet": [300,200]}], "collision": {"placements": {"trunk": [{"kind": "circle", "center": [4,-5], "radius": 7}]}}})
	_expect(collision.is_blocked(Vector2(304,195)), "placement: footprint did not follow native feet")
	collision.configure({"placements": [{"id": "trunk", "feet": [400,250]}], "collision": {"placements": {"trunk": [{"kind": "circle", "center": [4,-5], "radius": 7}]}}})
	_expect(collision.is_blocked(Vector2(404,245)) and not collision.is_blocked(Vector2(304,195)), "placement: old feet leaked after a layout update")


func _live_collision() -> RefCounted:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ViewScript.DEFAULT_LAYOUT_PATH))
	var collision = CollisionScript.new()
	collision.configure(layout)
	return collision


func _point_uv(pair: Array) -> Vector2:
	return Vector2(float(pair[0]), float(pair[1])) * Vector2(1024, 640)


func _test_live_layout() -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ViewScript.DEFAULT_LAYOUT_PATH))
	var collision = _live_collision()
	var spawn := _point_uv(layout.hero_start_uv)
	_expect(not collision.is_blocked(spawn), "town: initial player is trapped")
	for direction: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		_expect(collision.move(spawn, direction * 4.0, BOUNDS).distance_to(spawn + direction * 4.0) < 0.01,
			"town: spawn cannot move in every direction")
	for shape: Dictionary in collision.footprints():
		var point: Vector2
		if shape.kind == "polygon":
			var points: PackedVector2Array = shape.points
			var triangles := Geometry2D.triangulate_polygon(points)
			_expect(not triangles.is_empty(), "town: invalid footprint " + String(shape.id))
			if triangles.is_empty(): continue
			point = (points[triangles[0]] + points[triangles[1]] + points[triangles[2]]) / 3.0
		else:
			point = shape.center
		_expect(collision.is_blocked(point), "town: visible solid has no collision " + String(shape.id))
	for id: String in layout.routes_uv:
		var position := spawn
		for pair: Array in layout.routes_uv[id]:
			var target := _point_uv(pair)
			_expect(not collision.is_blocked(target), "town route %s: waypoint blocked %s by %s" % [id, target, _blocked_ids(collision, target)])
			var finish: Vector2 = collision.move(position, target - position, BOUNDS)
			_expect(finish.distance_to(target) < 0.02, "town route %s: interrupted at %s before %s" % [id, finish, target])
			position = target
		print("  town route %s: %d waypoints checked" % [id, layout.routes_uv[id].size()])
	_test_waterfront(collision)


func _blocked_ids(collision, point: Vector2) -> Array[String]:
	var ids: Array[String] = []
	for shape: Dictionary in collision.footprints():
		if collision._overlaps(point, shape): ids.append(String(shape.id))
	return ids


func _test_waterfront(collision) -> void:
	# Both sides of the one source bridge remain water; no old mirrored bridge.
	for point: Vector2 in [Vector2(860, 596), Vector2(851, 534), Vector2(666, 564), Vector2(946, 496)]:
		_expect(collision.is_blocked(point), "water: outside-deck water is walkable at %s" % point)
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ViewScript.DEFAULT_LAYOUT_PATH))
	var deck: Array = layout.routes_uv.bridge
	for index in range(5, deck.size() - 2):
		var start := _point_uv(deck[index])
		var finish := _point_uv(deck[index + 1])
		_expect(collision.move(finish, start - finish, BOUNDS).distance_to(start) < 0.02, "bridge: return passage blocked")
		var tangent := (finish - start).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		for side in [-1.0, 1.0]:
			var escaped: Vector2 = collision.move((start + finish) * 0.5, normal * side * 100.0, BOUNDS)
			_expect(not collision.is_blocked(escaped) and escaped.distance_to((start + finish) * 0.5) < 40.0,
				"bridge: walking sideways leaves the deck at %s" % escaped)


func _test_live_view() -> void:
	var view = ViewScript.new()
	root.add_child(view)
	_expect(view.load_default_assets(), "view: formal scene/characters failed to load: %s" % [view.pending_reasons()])
	var audit: Dictionary = view.render_audit()
	_expect(audit.view_size == Vector2(1008, 567) and view.world_viewport.size == Vector2i(1008, 567), "view: formal observation window reverted to close-up")
	_expect((view.world_display.size * view.world_display.scale).is_equal_approx(Vector2(1280, 720)), "view: formal canvas is not 1280x720")
	_expect(audit.town_concept.source_size == Vector2(1536, 1024), "view: source dimensions not decoded")
	_expect(audit.layers.ground == 0 and audit.layers.ground_layer == 0 and audit.layers.object_lower == 0, "view: legacy ground/objects still drawn")
	for id in ["contract", "loadout", "forge", "training", "proxy"]:
		var entry: Dictionary = view.entry_for(id)
		_expect(not entry.is_empty() and not view._collision.is_blocked(entry.feet), "view: facility interaction blocked " + id)
		view.teleport_hero(entry.feet)
		_expect(view.nearby_feature_id() == id and view.hit_test(entry.feet) == id, "view: facility entry/point hit inconsistent " + id)
		var screen: Vector2 = view.design_point_for_world(entry.feet, Vector2.ZERO, Vector2.ONE)
		_expect(view.world_point_at_design(screen, Vector2.ZERO, Vector2.ONE).distance_to(entry.feet) < 0.001, "view: camera coordinate round trip failed " + id)
	view.set_world_scale(2, Vector2(1600, 900))
	_expect((view.world_display.size * view.world_display.scale).is_equal_approx(Vector2(1600, 900)), "view: resized town clips or stretches")
	view.teleport_hero(Vector2(527, 310))
	view.move_hero(Vector2.DOWN, 1.0)
	_expect(not view._collision.is_blocked(view.hero_world_position()), "view: fire footprint escape failed")
	view.move_hero(Vector2.UP, 1.0)
	_expect(view.hero_world_position().y > 330, "view: fire remained exempt after escape")
	root.remove_child(view)
	view.free()
