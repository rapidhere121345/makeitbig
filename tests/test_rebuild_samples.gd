extends SceneTree

const ActorMotorScript := preload("res://src/runtime/geometry/actor_motor.gd")
const ActorStateScript := preload("res://src/runtime/world/actor_state.gd")
const EntityDefinitionScript := preload("res://src/runtime/world/entity_definition.gd")
const SpatialManifestScript := preload("res://src/runtime/world/spatial_manifest.gd")
const WorldPresenterScript := preload("res://src/runtime/world/world_presenter.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_test_town_building_channels_and_sort_anchor()
	_test_corridor_opening_and_wall_slide()
	_test_concave_room_preserves_hole()
	_test_multipart_boss_keeps_one_logical_identity()
	if failures.is_empty():
		print("PASS test_rebuild_samples.gd")
		quit(0)
		return
	for failure: String in failures:
		printerr("- %s" % failure)
	quit(1)


func _test_town_building_channels_and_sort_anchor() -> void:
	var manifest = SpatialManifestScript.new({
		"coordinate_convention": {"units": "pixel", "up": "negative_y"},
		"stable_bindings": [{
			"binding_id": "town.hearth.front",
			"channels": {"movement": true, "navigation": true, "vision": true, "projectile": true, "occlusion": true},
		}],
		"traversal_profiles": [{"profile_id": "standard", "radius": 6.0}],
		"regions_and_portals": [{"region_id": "town", "portals": []}],
		"spawn_interaction_exit_sockets": [{"socket_id": "town.exit", "kind": "exit"}],
		"gameplay_spatial_metadata": {"room_kind": "town"},
	})
	_expect(manifest.is_valid(), "town: authored building manifest is invalid")
	_expect(manifest.movement_bindings().size() == 1 and manifest.occlusion_bindings().size() == 1, "town: channels collapsed or disappeared")
	var definition_result: Dictionary = EntityDefinitionScript.from_dict({
		"entity_id": "ranger",
		"feet_anchor": Vector2(12.0, 18.0),
		"footprint": {"kind": "circle", "radius": 6.0},
		"sort_baseline": 18.0,
		"parts": [{"part_id": "body", "visual_id": "ranger.body"}],
	})
	_expect(bool(definition_result.ok), "town: feet anchored entity was rejected")


func _test_corridor_opening_and_wall_slide() -> void:
	var motor := ActorMotorScript.new(2.0)
	_expect(motor.register_rect("corridor.upper", Rect2(-10.0, -20.0, 60.0, 16.0)), "corridor: upper wall registration failed")
	_expect(motor.register_rect("corridor.lower", Rect2(-10.0, 4.0, 60.0, 16.0)), "corridor: lower wall registration failed")
	var through_opening: Dictionary = motor.move(Vector2(-30.0, 0.0), Vector2(80.0, 0.0), Rect2(-100.0, -100.0, 200.0, 200.0))
	_expect(not bool(through_opening.blocked) and _near(float(through_opening.position.x), 50.0), "corridor: valid opening was blocked")
	var slide := ActorMotorScript.new(2.0)
	_expect(slide.register_rect("corridor.wall", Rect2(10.0, -40.0, 4.0, 80.0)), "corridor: slide wall registration failed")
	var wall_slide: Dictionary = slide.move(Vector2.ZERO, Vector2(30.0, 20.0), Rect2(-100.0, -100.0, 200.0, 200.0))
	_expect(bool(wall_slide.blocked), "corridor: direct wall contact was not reported")
	_expect(float(wall_slide.position.x) <= 8.0001 and float(wall_slide.position.y) > 0.0, "corridor: legal tangent slide was lost")


func _test_concave_room_preserves_hole() -> void:
	var motor := ActorMotorScript.new(2.0)
	# Four authored pieces describe a room with a real central opening.  A
	# rectangle around the whole group would incorrectly fill this hole.
	_expect(motor.register_rect("room.north", Rect2(-40.0, -30.0, 80.0, 8.0)), "concave: north piece registration failed")
	_expect(motor.register_rect("room.south", Rect2(-40.0, 22.0, 80.0, 8.0)), "concave: south piece registration failed")
	_expect(motor.register_rect("room.west", Rect2(-40.0, -22.0, 8.0, 44.0)), "concave: west piece registration failed")
	_expect(motor.register_rect("room.east", Rect2(32.0, -22.0, 8.0, 44.0)), "concave: east piece registration failed")
	_expect(motor.is_position_clear(Vector2.ZERO), "concave: central hole was filled by a bounding rectangle")
	var through_hole: Dictionary = motor.move(Vector2(-20.0, 0.0), Vector2(40.0, 0.0), Rect2(-100.0, -100.0, 200.0, 200.0))
	_expect(not bool(through_hole.blocked) and _near(float(through_hole.position.x), 20.0), "concave: open hole was not traversable")


func _test_multipart_boss_keeps_one_logical_identity() -> void:
	var definition_result: Dictionary = EntityDefinitionScript.from_dict({
		"entity_id": "threshold_colossus",
		"feet_anchor": Vector2(80.0, 80.0),
		"footprint": {"kind": "circle", "radius": 18.0},
		"sort_baseline": 80.0,
		"parts": [
			{"part_id": "left_hand", "visual_id": "boss.left_hand", "damage_group_id": "hands"},
			{"part_id": "right_hand", "visual_id": "boss.right_hand", "damage_group_id": "hands"},
			{"part_id": "core", "visual_id": "boss.core", "damage_group_id": "core"},
		],
	})
	_expect(bool(definition_result.ok), "boss: multipart definition was rejected")
	var state_result: Dictionary = ActorStateScript.create("threshold_colossus", Vector2(80.0, 80.0), 18.0, "room/boss", 2)
	_expect(bool(state_result.ok), "boss: runtime state was rejected")
	var state: ActorState = state_result.value as ActorState
	state.part_ids = ["core", "right_hand", "left_hand"]
	var presenter := WorldPresenterScript.new()
	get_root().add_child(presenter)
	var core := Node2D.new()
	var hand := Node2D.new()
	_expect(bool(presenter.register_actor_view("threshold_colossus.core", core).ok), "boss: core visual registration failed")
	_expect(bool(presenter.register_actor_view("threshold_colossus.left_hand", hand).ok), "boss: hand visual registration failed")
	_expect(bool(presenter.sync_actor("threshold_colossus.core", state.feet_position, Vector2.ZERO).ok), "boss: core feet sync failed")
	_expect(core.position == Vector2(80.0, 80.0), "boss: visual sync changed the authoritative feet")
	presenter.queue_free()


func _near(left: float, right: float, tolerance: float = 0.0001) -> bool:
	return absf(left - right) <= tolerance


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

