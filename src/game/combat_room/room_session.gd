class_name RoomSession
extends RefCounted

## Authoritative state of one combat room. MainArena creates and owns the
## session and keeps every historical property name as a forwarding property, so
## the state hash builder, the room helpers, the ports and the tests keep
## reading `arena.<name>`. The session is never a Node and imports no
## presentation code; it holds no MainArena reference. Fixed-tick behavior still
## lives in MainArena's phase hooks and the combat_room collaborators; the
## session owns the simulation lifecycle (see
## docs/rebuild/ROOM_SESSION_DESIGN.md, migration items 3 and 4).

const CombatRoomLootScript := preload("res://src/game/combat_room_loot.gd")
const CombatRoomRulesScript := preload("res://src/game/combat_room_rules.gd")
const KernelBindingsScript := preload("res://src/game/combat_room/kernel_bindings.gd")
const PlayerCombatStateScript := preload("res://src/runtime/world/player_combat_state.gd")
const PlayerCombatRulesScript := preload("res://src/systems/player_combat_rules.gd")
const SmokeInputDriverScript := preload("res://src/game/diagnostics/smoke_input_driver.gd")
const CombatSystemScript := preload("res://src/systems/combat_system.gd")
const CombatSimulationScript := preload("res://src/systems/combat_simulation.gd")

## Build lock: the rule inputs frozen when a contract starts.
var selected_preset: String = "convergent"
var selected_mode: String = "Manual"
var locked_p: float = PiercingArrowModel.BASE_P
var locked_payload: float = MainArena.BASE_PAYLOAD
var locked_targeting_distance: float = MainArena.AUTO_RANGE
var locked_build: Dictionary = {}

## Contract run state: whether a contract is live, the elapsed clock, the
## command sequence and receipts, the battle report and the automation verdict.
var in_arena: bool = false
var elapsed: float = 0.0
var battle_report: String = ""
var command_sequence: int = 0
var last_command_receipts: Array[Dictionary] = []
var last_loot_pickup_command_receipt: Dictionary = {}
var automation_smoke: bool = false
var automation_smoke_failure: String = ""

## Domain objects. The untyped ones are created by MainArena's ensure_* methods
## because their construction binds typed ports to the MainArena instance.
var encounter_director
var room_catalog
var combat_system
var combat_simulation
## Production fixed-tick phase owner. CombatSimulation never receives MainArena
## as a callback bag; it receives a typed CombatPhasePort (today the
## RoomPhaseDomain MainArena binds to itself).
var room_phase_owner: CombatPhasePort = null
var player_combat_state := PlayerCombatStateScript.new()
var player_combat_rules := PlayerCombatRulesScript.new()
var smoke_input_driver := SmokeInputDriverScript.new()
var room_rules := CombatRoomRulesScript.new()
var proxy_runtime
var proxy_intent_system
var manual_aim_resolver
var enemy_tactics
var command_source
var command_source_port: RefCounted = null
var combat_event_stream
var kernel_bindings := KernelBindingsScript.new()
var room_loot := CombatRoomLootScript.new()

## Mounted-room authorities adopted from SceneRuntime (or the standalone room
## assembly) and the typed ports built over them.
var actor_registry
var simulation_world
var actor_registry_instance_id := ""
var actor_registry_revision := 0
var room_spatial_port = null
var room_combat_port = null
var room_encounter_port = null
var encounter_spawn_port: RefCounted = null

## Room definition and identity (set by the room runtime before start_room()).
var replay_geometry_profile: String = CombatSystemScript.QUERY_PROFILE_MULTIPART_V2
var framework_active_build: Dictionary = {}
var framework_resolved_build: Dictionary = {}
var framework_resolved_proxy_build: Dictionary = {}
var framework_room: Dictionary = {}
var room_id: String = ""
var layout_id: String = "rectangle_arena"
var objective_id: String = "clear"
var room_entry_start_tick: int = 0
var room_drop_tags: Array = []
var framework_seed: int = MainArena.FATE_SEED


## Creates the fixed-tick simulation on first use.
func ensure_combat_simulation() -> void:
	if combat_simulation == null:
		combat_simulation = CombatSimulationScript.new()


## Binds the fixed tick to the room's simulation world, player rules and the
## given phase port, and records the port as the session's phase owner.
func configure_simulation(phase_port: CombatPhasePort) -> Dictionary:
	ensure_combat_simulation()
	room_phase_owner = phase_port
	return combat_simulation.configure(simulation_world, player_combat_rules, phase_port)


## Runs exactly one fixed tick through CombatSimulation.
func step() -> Dictionary:
	ensure_combat_simulation()
	return combat_simulation.step()
