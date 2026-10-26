extends SceneTree

## Small fail-closed guard for the fixed-tick authority seam. The mounted
## production phase domain is exercised by test_kernel_production_combat; this
## gate keeps the orchestration boundary itself from regressing to a callback
## bag.

const Simulation := preload("res://src/systems/combat_simulation.gd")
const EncounterDirectorScript := preload("res://src/game/encounter_director.gd")
const EncounterRoomPortScript := preload("res://src/game/encounter_room_port.gd")
const Assert := preload("res://tests/helpers/assert.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var simulation := Simulation.new()
	_expect(not simulation.configure(null, null, null).ok, "authority accepted missing dependencies")
	_expect(not simulation.configure(null, null, RefCounted.new()).ok, "authority accepted an untyped phase owner")
	_expect(Simulation.AUTHORITY_PHASES.has("kernel.snapshot.published"), "authority trace lost snapshot publication")
	_expect(Simulation.AUTHORITY_PHASES.has("room.reconcile"), "authority trace lost room reconcile boundary")
	_expect(not Simulation.AUTHORITY_PHASES.has("room.snapshot.observed"), "authority retained the removed observation callback seam")
	_expect(Simulation.AUTHORITY_PHASES.find("kernel.snapshot.published") < Simulation.AUTHORITY_PHASES.find("room.reconcile"), "snapshot publication is ordered after reconcile")
	_expect(not FileAccess.file_exists("res://src/game/main_combat_phase_port.gd"), "production string-callback phase adapter was reintroduced")
	var director := EncounterDirectorScript.new()
	_expect(not director.bind_room(null).ok, "encounter authority accepted a missing room dependency")
	_expect(not director.bind_room(RefCounted.new()).ok, "encounter authority accepted an untyped room dependency")
	var base_port := EncounterRoomPortScript.new()
	_expect(not director.bind_room(base_port).ok, "encounter authority accepted a room dependency without rule ports")
	_expect(not base_port.move_enemy(null, Vector2.ZERO).ok, "encounter room base port silently accepted movement")
	_expect(not base_port.set_enemy_collision_class(null, &"ghost"), "encounter room base port silently accepted a collision class update")
	_expect(not base_port.register_enemy(null).ok, "encounter room base port silently accepted an actor registration")
	_expect(base_port.collision_geometry(16.0).is_empty(), "encounter room base port fabricated collision geometry")
	_expect(base_port.layout_spawn_offsets("corridor", 1).is_empty(), "encounter room base port fabricated spawn sockets")
	_expect(not base_port.clamp_to_arena(Vector2.ZERO, 8.0).is_finite(), "encounter room base port fabricated an arena projection")
	_expect(not base_port.quantize_position(Vector2.ZERO).is_finite(), "encounter room base port fabricated a quantized position")
	var director_source := FileAccess.get_file_as_string("res://src/game/encounter_director.gd")
	_expect(not director_source.contains("move_enemy_callback"), "encounter authority regressed to a Callable member bag")
	if failures.is_empty():
		print("PASS test_kernel_authority_boundary.gd")
	else:
		for failure: String in failures:
			printerr("- " + failure)
		print("FAIL test_kernel_authority_boundary.gd")
	quit(0 if failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void: Assert.expect(condition, message, failures)
