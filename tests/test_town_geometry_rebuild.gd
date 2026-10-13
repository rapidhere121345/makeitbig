extends SceneTree

const ActorMotorScript := preload("res://src/runtime/geometry/actor_motor.gd")
const LayoutBlockerLoaderScript := preload("res://src/runtime/geometry/layout_blocker_loader.gd")
const HamletViewScript := preload("res://src/presentation/hamlet_concept_view.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(HamletViewScript.DEFAULT_LAYOUT_PATH))
	var motor := ActorMotorScript.new()
	var loaded: Dictionary = LayoutBlockerLoaderScript.populate_motor(motor, layout)
	_expect(bool(loaded.ok), "loader: production layout collision rejected: %s" % [loaded.get("errors", [])])
	_expect(int(loaded.registered) > 30, "loader: too few authored blockers were registered")
	var world_size := Vector2(float(layout.world[0]), float(layout.world[1]))
	var bounds := Rect2(Vector2(HamletViewScript.WORLD_MARGIN, HamletViewScript.WORLD_MARGIN), world_size - Vector2.ONE * HamletViewScript.WORLD_MARGIN * 2.0)
	var spawn := Vector2(float(layout.hero_start_uv[0]), float(layout.hero_start_uv[1])) * world_size
	_expect(motor.is_position_clear(spawn, bounds), "loader: hero spawn is blocked")
	for direction: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var result: Dictionary = motor.move(spawn, direction * 4.0, bounds)
		_expect(result.position.distance_to(spawn + direction * 4.0) < 0.01, "loader: hero spawn failed four-way clearance %s" % direction)
	for route_id: String in layout.routes_uv:
		var position := spawn
		for pair: Array in layout.routes_uv[route_id]:
			var target := Vector2(float(pair[0]), float(pair[1])) * world_size
			_expect(motor.is_position_clear(target, bounds), "loader: route %s waypoint blocked at %s" % [route_id, target])
			var result: Dictionary = motor.move(position, target - position, bounds)
			_expect(result.position.distance_to(target) < 0.02, "loader: route %s stopped at %s before %s" % [route_id, result.position, target])
			position = target
	if failures.is_empty():
		print("PASS test_town_geometry_rebuild.gd blockers=%d" % int(loaded.registered))
		quit(0)
		return
	for failure: String in failures:
		printerr("- %s" % failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

