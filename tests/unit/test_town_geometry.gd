extends SceneTree
## Town movement and production-layout regression checks; never starts combat or writes saves.
## The production path is the same ActorMotor + LayoutBlockerLoader pair used by
## HamletConceptView.  Core sweep/slide cases live in test_actor_motor.gd.
const ActorMotorScript := preload("res://src/runtime/geometry/actor_motor.gd")
const LayoutBlockerLoaderScript := preload("res://src/runtime/geometry/layout_blocker_loader.gd")
const ViewScript = preload("res://src/presentation/hamlet_concept_view.gd")
const HERO_RADIUS := 6.0
var failures: Array[String] = []


func _initialize() -> void:
	_test_sweep_and_slide()
	_test_narrow_passages()
	_test_reset_and_placement_loading()
	_test_live_layout()
	_test_live_view()
	if failures.is_empty():
		print("PASS  test_town_geometry.gd")
		quit(0)
	else:
		for failure: String in failures:
			printerr("- " + failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _geometry(shapes: Array) -> RefCounted:
	var motor := ActorMotorScript.new(HERO_RADIUS)
	var loaded: Dictionary = LayoutBlockerLoaderScript.populate_motor(motor, {
		"collision": {"hero_radius": HERO_RADIUS, "world": shapes},
	})
	_expect(bool(loaded.get("ok", false)), "geometry: synthetic blocker set was rejected: %s" % [loaded.get("errors", [])])
	return motor


func _bounds() -> Rect2:
	# ActorMotor receives the outer walkable world and keeps the circular
	# footprint inside it.  The old town bounds represented the centre range.
	return Rect2(Vector2.ONE * (ViewScript.WORLD_MARGIN - HERO_RADIUS), Vector2(1024.0, 640.0) - Vector2.ONE * (ViewScript.WORLD_MARGIN - HERO_RADIUS) * 2.0)


func _position(result: Dictionary) -> Vector2:
	return result.get("position", Vector2.INF) as Vector2


func _test_sweep_and_slide() -> void:
	var collision = _geometry([{"id": "wall", "kind": "rect", "rect": [200,100,40,220]}])
	var stopped: Vector2 = _position(collision.move(Vector2(100,200), Vector2(800,0), _bounds()))
	_expect(absf(stopped.x - 194) < 0.01 and stopped.y == 200, "sweep: long step crossed a building")
	var slide: Vector2 = _position(collision.move(Vector2(180,150), Vector2(60,100), _bounds()))
	_expect(absf(slide.x - 194) < 0.01 and absf(slide.y - 250) < 0.01 and collision.is_position_clear(slide), "slide: diagonal movement did not preserve tangent distance")
	var reverse: Vector2 = _position(collision.move(Vector2(180,250), Vector2(60,-100), _bounds()))
	_expect(absf(reverse.x - 194) < 0.01 and absf(reverse.y - 150) < 0.01, "slide: north/south wall response is asymmetric")
	for hz in [30,60,144]:
		var position := Vector2(180,150)
		for frame in hz:
			position = _position(collision.move(position, Vector2(60,100) / float(hz), _bounds()))
		_expect(position.distance_to(slide) < 0.02, "slide: continuous movement changed at %s Hz: %s vs %s" % [hz, position, slide])
	var corner = _geometry([
		{"id": "corner.vertical", "kind": "rect", "rect": [200,100,40,220]},
		{"id": "corner.horizontal", "kind": "rect", "rect": [100,280,100,40]},
	])
	var wedged: Vector2 = _position(corner.move(Vector2(160,200), Vector2(800,800), _bounds()))
	_expect(wedged.x < 194.01 and wedged.y < 274.01 and corner.is_position_clear(wedged), "slide: inside corner allowed penetration")
	var disc = _geometry([{"id": "resident", "kind": "circle", "center": [300,200], "radius": 7}])
	_expect(absf(_position(disc.move(Vector2(200,200), Vector2(700,0), _bounds())).x - 287) < 0.01, "sweep: long step crossed resident feet")
	var glanced: Vector2 = _position(disc.move(Vector2(270,180), Vector2(50,30), _bounds()))
	_expect(disc.is_position_clear(glanced) and glanced.x > 280 and glanced.y < 210, "slide: circle did not deflect diagonal movement")
	var boundary_slide: Vector2 = _position(collision.move(Vector2(40,400), Vector2(-60,100), _bounds()))
	_expect(boundary_slide.is_equal_approx(Vector2(20,500)), "bounds: diagonal movement lost its tangent component")


func _test_narrow_passages() -> void:
	var collision = _geometry([
		{"id": "passage.upper", "kind": "rect", "rect": [200,100,40,100]},
		{"id": "passage.lower", "kind": "rect", "rect": [200,214,40,100]},
	])
	_expect(_position(collision.move(Vector2(100,207), Vector2(300,0), _bounds())).distance_to(Vector2(400,207)) < 0.01, "passage: 14px gap closed around a 12px foot disc")
	var solid = _geometry([
		{"id": "narrow.upper", "kind": "rect", "rect": [200,100,40,100]},
		{"id": "narrow.lower", "kind": "rect", "rect": [200,210,40,100]},
	])
	var narrow_stop: Vector2 = _position(solid.move(Vector2(100,205), Vector2(300,0), _bounds()))
	_expect(narrow_stop.x < 200 and solid.is_position_clear(narrow_stop), "passage: 10px gap admitted a 12px foot disc at %s" % narrow_stop)
	# Rounded footprint corners must leave diagonally adjacent open ground usable.
	_expect(collision.is_position_clear(Vector2(195,95)), "passage: rectangle corners use a square invisible expansion")


func _test_reset_and_placement_loading() -> void:
	var motor := _geometry([{"id": "boulder", "kind": "circle", "center": [300,200], "radius": 20}])
	motor.clear()
	_expect(motor.snapshot().is_empty(), "reset: clearing the query retained old obstacles")
	_expect(_position(motor.move(Vector2(100,200), Vector2(300,0), _bounds())) == Vector2(400,200), "reset: empty geometry changed walking")
	var first := LayoutBlockerLoaderScript.populate_motor(motor, {
		"placements": [{"id": "trunk", "feet": [300,200]}],
		"collision": {"hero_radius": HERO_RADIUS, "placements": {"trunk": [{"kind": "circle", "center": [4,-5], "radius": 7}]},},
	})
	_expect(bool(first.ok) and motor.is_position_clear(Vector2(100,200)), "placement: first footprint failed to load")
	_expect(not motor.is_position_clear(Vector2(304,195)), "placement: footprint did not follow native feet")
	var second := LayoutBlockerLoaderScript.populate_motor(motor, {
		"placements": [{"id": "trunk", "feet": [400,250]}],
		"collision": {"hero_radius": HERO_RADIUS, "placements": {"trunk": [{"kind": "circle", "center": [4,-5], "radius": 7}]},},
	})
	_expect(bool(second.ok) and not motor.is_position_clear(Vector2(404,245)) and motor.is_position_clear(Vector2(304,195)), "placement: old feet leaked after a layout update")


func _live_motor() -> RefCounted:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ViewScript.DEFAULT_LAYOUT_PATH))
	var motor := ActorMotorScript.new(HERO_RADIUS)
	var result := LayoutBlockerLoaderScript.populate_motor(motor, layout)
	_expect(bool(result.ok), "town: production layout rejected: %s" % [result.get("errors", [])])
	return motor


func _point_uv(pair: Array) -> Vector2:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ViewScript.DEFAULT_LAYOUT_PATH))
	return Vector2(float(pair[0]), float(pair[1])) * Vector2(layout.world[0], layout.world[1])


func _live_bounds() -> Rect2:
	return Rect2(Vector2.ONE * (ViewScript.WORLD_MARGIN - HERO_RADIUS), _point_uv([1, 1]) - Vector2.ONE * (ViewScript.WORLD_MARGIN - HERO_RADIUS) * 2.0)


func _test_live_layout() -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ViewScript.DEFAULT_LAYOUT_PATH))
	var collision = _live_motor()
	var spawn := _point_uv(layout.hero_start_uv)
	_expect(collision.is_position_clear(spawn, _live_bounds()), "town: initial player is trapped")
	for direction: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		_expect(_position(collision.move(spawn, direction * 4.0, _live_bounds())).distance_to(spawn + direction * 4.0) < 0.01,
			"town: spawn cannot move in every direction")
	for shape: Dictionary in collision.snapshot():
		var point: Vector2
		if shape.kind == "polygon":
			var points: PackedVector2Array = shape.points
			point = Vector2.ZERO
			for vertex: Vector2 in points:
				point += vertex
			point /= float(points.size())
		elif shape.kind == "circle":
			point = shape.center
		else:
			point = shape.rect.get_center()
		_expect(not collision.is_position_clear(point), "town: visible solid has no collision " + String(shape.id))
	for id: String in layout.routes_uv:
		var position := spawn
		for pair: Array in layout.routes_uv[id]:
			var target := _point_uv(pair)
			_expect(collision.is_position_clear(target, _live_bounds()), "town route %s: waypoint blocked %s" % [id, target])
			var finish: Vector2 = _position(collision.move(position, target - position, _live_bounds()))
			_expect(finish.distance_to(target) < 0.02, "town route %s: interrupted at %s before %s" % [id, finish, target])
			position = target
		print("  town route %s: %d waypoints checked" % [id, layout.routes_uv[id].size()])
	_test_waterfront(collision)

func _test_waterfront(collision) -> void:
	# Both sides of the one source bridge remain water; no old mirrored bridge.
	# Samples are authored in the 1024x640 design space and scaled to the
	# 1536x960 world; the texture itself is a separate 1536x1024 space.
	for point: Vector2 in [Vector2(860, 596), Vector2(851, 534), Vector2(666, 564), Vector2(946, 496)]:
		point = _point_uv([point.x / 1024.0, point.y / 640.0])
		_expect(not collision.is_position_clear(point), "water: outside-deck water is walkable at %s" % point)
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ViewScript.DEFAULT_LAYOUT_PATH))
	var deck: Array = layout.routes_uv.bridge
	## Deck segments start at the plank inner section (texture 1150,740); the
	## west entrance segment legitimately escapes onto the shore path.
	for index in range(6, deck.size() - 2):
		var start := _point_uv(deck[index])
		var finish := _point_uv(deck[index + 1])
		_expect(_position(collision.move(finish, start - finish, _live_bounds())).distance_to(start) < 0.02, "bridge: return passage blocked")
		var tangent := (finish - start).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		for side in [-1.0, 1.0]:
			var escaped: Vector2 = _position(collision.move((start + finish) * 0.5, normal * side * 150.0, _live_bounds()))
			_expect(collision.is_position_clear(escaped) and escaped.distance_to((start + finish) * 0.5) < 60.0,
				"bridge: walking sideways leaves the deck at %s" % escaped)
	_test_bridge_deck(collision)


func _test_bridge_deck(collision) -> void:
	## The visible plank centerline, authored in texture pixels of the
	## 1536x1024 source, must walk end-to-end while both off-deck rails stay
	## blocked water. UV converts as x/1536 and texture_y/1024.
	var centerline_uv: Array = [
		[0.716146, 0.700195], [0.748698, 0.722656], [0.78125, 0.75],
		[0.813802, 0.774414], [0.846354, 0.805664], [0.878906, 0.838867],
		[0.911458, 0.871094], [0.93099, 0.887695],
	]
	var previous := Vector2.ZERO
	for index in centerline_uv.size():
		var point := _point_uv(centerline_uv[index])
		_expect(collision.is_position_clear(point, _live_bounds()), "bridge deck: visible centerline blocked at %s" % point)
		if index > 0:
			var walked: Vector2 = _position(collision.move(previous, point - previous, _live_bounds()))
			_expect(walked.distance_to(point) < 0.02, "bridge deck: walk interrupted at %s" % walked)
		previous = point
	for rail_uv: Array in [[0.813802, 0.722656], [0.813802, 0.839844]]:
		var rail := _point_uv(rail_uv)
		_expect(not collision.is_position_clear(rail, _live_bounds()), "bridge deck: off-deck water walkable at %s" % rail)
	## Playtest rail fix: the south water boundary sits at tex y=815 (x=1250)
	## so a 12px foot stops on the planks instead of the rail top.
	_expect(not collision.is_position_clear(_point_uv([0.813802, 0.802734]), _live_bounds()), "bridge deck: south rail stop walkable")
	_expect(collision.is_position_clear(_point_uv([0.813802, 0.787109]), _live_bounds()), "bridge deck: south plank strip blocked")
	for roof_uv: Array in [[0.41862, 0.074219], [0.16862, 0.179688], [0.650391, 0.139648], [0.917969, 0.267578]]:
		var roof := _point_uv(roof_uv)
		_expect(not collision.is_position_clear(roof, _live_bounds()), "roofs: building body walkable at %s" % roof)


func _test_live_view() -> void:
	var view = ViewScript.new()
	root.add_child(view)
	_expect(view.load_default_assets(), "view: formal scene/characters failed to load: %s" % [view.pending_reasons()])
	var audit: Dictionary = view.render_audit()
	_expect(audit.view_size == Vector2(640, 360) and view.world_viewport.size == Vector2i(640, 360), "view: town lost its close follow camera")
	_expect((view.world_display.size * view.world_display.scale).is_equal_approx(Vector2(1280, 720)), "view: formal canvas is not 1280x720")
	_expect(audit.town_concept.source_size == Vector2(1536, 1024), "view: source dimensions not decoded")
	_expect(audit.layers.ground == 0 and audit.layers.ground_layer == 0 and audit.layers.object_lower == 0, "view: legacy ground/objects still drawn")
	for id in ["contract", "loadout", "forge", "training", "proxy"]:
		var entry: Dictionary = view.entry_for(id)
		_expect(not entry.is_empty() and view.hero_position_is_clear(entry.feet), "view: facility interaction blocked " + id)
		view.teleport_hero(entry.feet)
		_expect(view.nearby_feature_id() == id and view.hit_test(entry.feet) == id, "view: facility entry/point hit inconsistent " + id)
		var screen: Vector2 = view.design_point_for_world(entry.feet, Vector2.ZERO, Vector2.ONE)
		_expect(view.world_point_at_design(screen, Vector2.ZERO, Vector2.ONE).distance_to(entry.feet) < 0.001, "view: camera coordinate round trip failed " + id)
	view.set_world_scale(2, Vector2(1600, 900))
	_expect((view.world_display.size * view.world_display.scale).is_equal_approx(Vector2(1600, 900)), "view: resized town clips or stretches")
	view.teleport_hero(_point_uv([500.0 / 1024.0, 402.0 / 640.0]))
	_expect(view.hero_position_is_clear(view.hero_world_position()), "view: clear hero anchor is blocked")
	view.move_hero(Vector2.DOWN, 1.5)
	_expect(view.hero_position_is_clear(view.hero_world_position()), "view: motor produced an invalid hero position")
	root.remove_child(view)
	view.free()
