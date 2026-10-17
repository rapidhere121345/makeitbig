extends RefCounted

## Shared fixture factory for kernel tests: one configured room with fake
## ports. Kept static so each test builds isolated worlds.

const SimTestWorldScript := preload("res://src/runtime/world/simulation_world.gd")
const FakeSpatialPortScript := preload("res://tests/simulation/fake_spatial_port.gd")
const FakeCombatPortScript := preload("res://tests/simulation/fake_combat_port.gd")
const FakeEncounterPortScript := preload("res://tests/simulation/fake_encounter_port.gd")
const RecordingPresentationScript := preload("res://tests/simulation/recording_presentation.gd")

const DEFAULT_ROOM := "kernel-test-room"
const DEFAULT_REVISION: int = 7
const DEFAULT_TICK_RATE: int = 30


static func make_world(
	room: String = DEFAULT_ROOM,
	revision: int = DEFAULT_REVISION,
	tick_rate: int = DEFAULT_TICK_RATE
) -> Dictionary:
	var spatial = FakeSpatialPortScript.new()
	var combat = FakeCombatPortScript.new()
	var encounter = FakeEncounterPortScript.new()
	var presentation = RecordingPresentationScript.new()
	var world = SimTestWorldScript.new(spatial, combat, encounter, presentation)
	var configured: SimOutcome = world.configure(room, revision, tick_rate)
	spatial.registry = world.actor_registry
	combat.registry = world.actor_registry
	return {
		"world": world,
		"configured": configured,
		"spatial": spatial,
		"combat": combat,
		"encounter": encounter,
		"presentation": presentation,
	}
