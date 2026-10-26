extends SceneTree
## Town movement and production-layout regression checks; never starts combat or writes saves.
## The production path is the same ActorMotor + LayoutBlockerLoader pair used by
## TownController.  Core sweep/slide cases live in test_actor_motor.gd.
const ActorMotorScript := preload("res://src/runtime/geometry/actor_motor.gd")
const LayoutBlockerLoaderScript := preload("res://src/runtime/geometry/layout_blocker_loader.gd")
const HubScript = preload("res://src/presentation/base_hub_screen.gd")
const WORLD_MARGIN := 38.0
const SOURCE_LAYOUT_PATH := "res://content/rooms/town/hearthside.spatial.json"
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
	var loaded: Dictionary = LayoutBlockerLoaderScript.populate_geometry(motor, {
		"collision": {"hero_radius": HERO_RADIUS, "world": shapes},
	})
	_expect(bool(loaded.get("ok", false)), "geometry: synthetic blocker set was rejected: %s" % [loaded.get("errors", [])])
	return motor


func _bounds() -> Rect2:
	# ActorMotor receives the outer walkable world and keeps the circular
	# footprint inside it.  The old town bounds represented the centre range.
	return Rect2(Vector2.ONE * 14.0, Vector2(1024.0, 640.0) - Vector2.ONE * 28.0)


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
	motor.clear_geometry()
	_expect(motor.snapshot().is_empty(), "reset: clearing the query retained old obstacles")
	_expect(_position(motor.move(Vector2(100,200), Vector2(300,0), _bounds())) == Vector2(400,200), "reset: empty geometry changed walking")
	var first := LayoutBlockerLoaderScript.populate_geometry(motor, {
		"placements": [{"id": "trunk", "feet": [300,200]}],
		"collision": {"hero_radius": HERO_RADIUS, "placements": {"trunk": [{"kind": "circle", "center": [4,-5], "radius": 7}]},},
	})
	_expect(bool(first.ok) and motor.is_position_clear(Vector2(100,200)), "placement: first footprint failed to load")
	_expect(not motor.is_position_clear(Vector2(304,195)), "placement: footprint did not follow native feet")
	var second := LayoutBlockerLoaderScript.populate_geometry(motor, {
		"placements": [{"id": "trunk", "feet": [400,250]}],
		"collision": {"hero_radius": HERO_RADIUS, "placements": {"trunk": [{"kind": "circle", "center": [4,-5], "radius": 7}]},},
	})
	_expect(bool(second.ok) and not motor.is_position_clear(Vector2(404,245)) and motor.is_position_clear(Vector2(304,195)), "placement: old feet leaked after a layout update")


## The live scene's checked offline derivative supplies geometry. Legacy
## illustration UV paths are retained as provenance, never a second authority.
func _live_layout() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(SOURCE_LAYOUT_PATH))


func _live_motor() -> RefCounted:
	var metadata: Dictionary = _live_layout().gameplay_spatial_metadata
	var shapes: Array = metadata.static_geometry.duplicate(true)
	for resident: Dictionary in metadata.residents:
		shapes.append({"id": "resident/" + String(resident.id), "kind": "circle", "center": resident.position, "radius": resident.radius})
	var motor := ActorMotorScript.new(HERO_RADIUS)
	var result := LayoutBlockerLoaderScript.populate_geometry(motor, {"collision": {"hero_radius": HERO_RADIUS, "world": shapes}})
	_expect(bool(result.ok), "town: production spatial geometry rejected: %s" % [result.get("errors", [])])
	return motor


func _live_bounds() -> Rect2:
	for binding: Dictionary in _live_layout().stable_bindings:
		if binding.binding_id == "town/movement-boundary":
			var rect: Array = binding.geometry.rect
			return Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3]))
	_expect(false, "town movement boundary missing")
	return Rect2()


func _test_live_layout() -> void:
	var layout: Dictionary = _live_layout()
	var metadata: Dictionary = layout.gameplay_spatial_metadata
	var collision = _live_motor()
	var pair: Array = metadata.routes.contract[0]
	var spawn := Vector2(pair[0], pair[1])
	_expect(collision.is_position_clear(spawn, _live_bounds()), "town: initial player is trapped")
	for direction: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		_expect(_position(collision.move(spawn, direction * 4, _live_bounds())).distance_to(spawn + direction * 4) < 0.01, "town: spawn cannot move in every direction")
	for id: String in metadata.routes:
		var position := spawn
		for point: Array in metadata.routes[id]:
			var target := Vector2(point[0], point[1])
			_expect(collision.is_position_clear(target, _live_bounds()), "town route %s: waypoint blocked %s" % [id, target])
			var finish: Vector2 = _position(collision.move(position, target-position, _live_bounds()))
			_expect(finish.distance_to(target) < 0.02, "town route %s: interrupted at %s before %s" % [id, finish, target])
			position = target
		print("  generated town route %s: %d waypoints checked" % [id, metadata.routes[id].size()])
	for facility: Dictionary in metadata.facilities:
		_expect(collision.is_position_clear(Vector2(facility.position[0], facility.position[1]), _live_bounds()), "facility socket blocked: " + String(facility.id))
	for point: Vector2 in [Vector2(283, 267), Vector2(711, 190), Vector2(1107, 284), Vector2(1390, 410), Vector2(790, 483)]:
		_expect(not collision.is_position_clear(point), "town: ground footprint has no collision at %s" % point)
	## 2.5D traversal: rows that sat inside the retired whole-image envelopes
	## now stand legally behind the projected art, and a continuous move
	## crosses them without interruption or footprint penetration.
	for point: Vector2 in [Vector2(283, 206), Vector2(711, 140), Vector2(1091, 175), Vector2(1390, 377), Vector2(985, 700), Vector2(280, 564), Vector2(410, 235)]:
		_expect(collision.is_position_clear(point, _live_bounds()), "town: legal stand behind projected art blocked at %s" % point)
	for sweep: Array in [[Vector2(650, 124), Vector2(770, 124)], [Vector2(1000, 178), Vector2(1200, 178)], [Vector2(950, 700), Vector2(1020, 700)]]:
		var finish: Vector2 = _position(collision.move(sweep[0], sweep[1] - sweep[0], _live_bounds()))
		_expect(finish.distance_to(sweep[1]) < 0.02, "town: cannot move continuously behind object at %s (stopped %s)" % [sweep[0], finish])
	# The traced winding river blocks off-bridge water; both measured decks and
	# the south bank stay walkable. The outer map edge still blocks.
	for point: Vector2 in [Vector2(790, 874), Vector2(300, 700), Vector2(1200, 760)]:
		_expect(not collision.is_position_clear(point, _live_bounds()), "open river water is walkable at %s" % point)
	for point: Vector2 in [Vector2(746.5, 819), Vector2(1350.5, 745.5), Vector2(600, 850)]:
		_expect(collision.is_position_clear(point, _live_bounds()), "bridge deck or south bank blocked at %s" % point)
	_expect(not collision.is_position_clear(Vector2(850, 935), _live_bounds()), "invisible map boundary is missing")


func _test_live_view() -> void:
	var hub := HubScript.new()
	root.add_child(hub)
	hub._ready()
	var view := hub.get_hub_view()
	var town = hub.get_town_runtime()
	_expect(bool(hub.town_load_report.get("ok", false)), "native town failed to load: " + str(hub.town_load_report))
	if not town.is_ready():
		_shutdown_hub(hub)
		return
	view.set_world_scale(2, Vector2(1280, 720))
	_expect(view.world_viewport.size == Vector2i(640, 360), "town lost close follow camera")
	for id: String in ["contract", "loadout", "forge", "training", "proxy"]:
		var entry: Dictionary = town.entry_for(id)
		_expect(town.hero_position_is_clear(entry.feet), "facility interaction blocked " + id)
		town.place_hero(entry.feet)
		_expect(town.nearby_feature_id() == id and hub._hit_feature(entry.feet) == id, "facility entry/point hit inconsistent " + id)
		var screen: Vector2 = view.design_point_for_world(entry.feet, Vector2.ZERO, Vector2.ONE)
		_expect(view.world_point_at_design(screen, Vector2.ZERO, Vector2.ONE).distance_to(entry.feet) < 0.001, "camera round trip failed " + id)
	view.set_world_scale(2, Vector2(1600, 900))
	_expect((view.world_display.size * view.world_display.scale).is_equal_approx(Vector2(1600, 900)), "resized town clips or stretches")
	town.place_hero(town.route_points("contract")[0])
	hub.move_hero(Vector2.DOWN, 1.5)
	_expect(town.hero_position_is_clear(town.hero_world_position()), "fixed motor produced invalid feet")
	_shutdown_hub(hub)


func _shutdown_hub(hub: Node) -> void:
	if hub == null or not is_instance_valid(hub):
		return
	var controller: Variant = hub.get("_town_controller")
	if controller != null:
		var runtime: Variant = controller.get("scene_runtime")
		if runtime != null and runtime.has_method("unmount"):
			runtime.unmount()
	if hub.get_parent() != null:
		hub.get_parent().remove_child(hub)
	hub.free()
