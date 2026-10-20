class_name MainArena
extends Node2D

signal return_requested

const PresentationController := preload("res://src/presentation/combat_presentation_controller.gd")
const PresentationSnapshot := preload("res://src/presentation/combat_presentation_snapshot.gd")
const ArenaWorldViewScript := preload("res://src/presentation/arena_world_view.gd")
const InputAdapter := preload("res://src/presentation/combat_input_adapter.gd")
const LabView := preload("res://src/presentation/combat_lab_view.gd")

const ContentRegistryScript = preload("res://src/content/content_registry.gd")
const DestinyForgeScript = preload("res://src/systems/destiny_forge.gd")
const ProxyRuntimeScript = preload("res://src/systems/proxy_runtime.gd")
const ProxyDecisionScript = preload("res://src/systems/proxy_decision.gd")
const ProxyIntentSystemScript = preload("res://src/systems/proxy_intent_system.gd")
const CombatCommandProtocolScript = preload("res://src/systems/combat_command_protocol.gd")
const ManualAimResolverScript = preload("res://src/systems/manual_aim_resolver.gd")
const EnemyTacticsScript = preload("res://src/systems/enemy_tactics.gd")
const ArenaGeometryScript = preload("res://src/runtime/geometry/arena_geometry.gd")
const CombatQueryScript = preload("res://src/runtime/geometry/combat_query.gd")
const CombatEventStreamScript = preload("res://src/systems/combat_event_stream.gd")
const SaveStoreScript = preload("res://src/persistence/save_store.gd")
const RangerSkillRulesScript = preload("res://src/systems/ranger_skill_rules.gd")
const PiercingArrowModelScript = preload("res://src/systems/piercing_arrow_model.gd")
const ActorRegistryScript = preload("res://src/runtime/world/actor_registry.gd")
const SimulationWorldScript = preload("res://src/runtime/world/simulation_world.gd")
const SimOutcomeScript = preload("res://src/runtime/simulation/sim_outcome.gd")
const StaticSpatialIndexScript = preload("res://src/runtime/spatial/static_spatial_index.gd")
const DynamicSpatialIndexScript = preload("res://src/runtime/spatial/dynamic_spatial_index.gd")
const SpatialOverlayScript = preload("res://src/runtime/spatial/spatial_overlay.gd")
const MovementResolverScript = preload("res://src/runtime/spatial/movement_resolver.gd")
const BodyCollisionPolicyScript = preload("res://src/runtime/spatial/body_collision_policy.gd")
const RoomActorAccessScript = preload("res://src/runtime/world/room_actor_access.gd")
const RoomSpatialPortScript = preload("res://src/runtime/world/room_spatial_port.gd")
const RoomCombatPortScript = preload("res://src/runtime/world/room_combat_port.gd")
const RoomEncounterPortScript = preload("res://src/runtime/world/room_encounter_port.gd")
const RoomPresentationPortScript = preload("res://src/runtime/world/room_presentation_port.gd")
const CombatStateSnapshotBuilderScript = preload("res://src/game/combat_state_snapshot_builder.gd")
const CombatEnemyStateScript = preload("res://src/runtime/world/combat_enemy_state.gd")
const RoomCatalogScript = preload("res://src/runtime/world/room_catalog.gd")
const EncounterDirectorScript = preload("res://src/game/encounter_director.gd")
const EncounterSpawnRequestScript := preload("res://src/runtime/encounter/encounter_spawn_request.gd")
const EncounterSpawnResultScript := preload("res://src/runtime/encounter/encounter_spawn_result.gd")
const RoomTerminalObservationScript := preload("res://src/runtime/encounter/room_terminal_observation.gd")
const SmokeInputDriverScript := preload("res://src/game/diagnostics/smoke_input_driver.gd")
const CombatRoomRulesScript := preload("res://src/game/combat_room_rules.gd")
const CombatSystemScript = preload("res://src/systems/combat_system.gd")
const PlayerCombatStateScript := preload("res://src/runtime/world/player_combat_state.gd")
const PlayerCombatRulesScript := preload("res://src/systems/player_combat_rules.gd")
const CombatCommandSourceScript = preload("res://src/systems/combat_command_source.gd")
const MainCombatCommandSourcePortScript: Script = preload("res://src/game/main_combat_command_source_port.gd")
const CombatSimulationScript = preload("res://src/systems/combat_simulation.gd")
const RangerArrowFlightScript := preload("res://src/runtime/combat/ranger_arrow_flight.gd")
const BossCombatDomainScript := preload("res://src/runtime/combat/boss_combat_domain.gd")
const BossTargetViewScript := preload("res://src/runtime/combat/boss_target_view.gd")
const BossHurtboxScript := preload("res://src/runtime/combat/boss_hurtbox.gd")
const BossArrowFlightScript := preload("res://src/runtime/combat/boss_arrow_flight.gd")
const CombatHazardDomainScript := preload("res://src/runtime/combat/combat_hazard_domain.gd")
const DeathSettlementNotificationScript := preload("res://src/runtime/combat/death_settlement_notification.gd")
const RoomEncounterScript := preload("res://src/runtime/encounter/room_encounter.gd")
const SimTickContextScript := preload("res://src/runtime/simulation/sim_tick_context.gd")
const CombatRoomLootScript := preload("res://src/game/combat_room_loot.gd")
const MainLootPlacementPortScript := preload("res://src/game/main_loot_placement_port.gd")
const CombatLootPickupProtocolScript := preload("res://src/systems/combat_loot_pickup_protocol.gd")
const CombatStatsSnapshotScript := preload("res://src/game/combat_stats_snapshot.gd")

const ARENA_MARGIN: float = 42.0
const AUTHORITY_VIEWPORT_SIZE: Vector2 = Vector2(1280.0, 720.0)
const SIM_TICKS_PER_SECOND: int = RangerSkillRulesScript.TICKS_PER_SECOND
const SIM_STEP_SECONDS: float = 1.0 / float(SIM_TICKS_PER_SECOND)
const AUTO_RANGE: float = 225.0
const BASE_PAYLOAD: float = 160.0
const FATE_SEED: int = 52969
const SAVE_PROTOCOL_VERSION: int = 1
const ENEMY_HIT_FLASH_TICKS: int = 3
const MAX_ACTIVE_PIERCING_PROJECTILES: int = 16
# Early campaign durability only; movement, action timing and Boss authority stay separate.
const EARLY_NORMAL_HEALTH_BY_KIND := {
	"melee_pursuer": 720.0,
	"charging_raider": 420.0,
	"fan_ranged": 240.0,
}
const EARLY_ELITE_HEALTH_BY_KIND := {
	"melee_pursuer": 1600.0,
	"charging_raider": 1300.0,
	"fan_ranged": 1000.0,
}
const MELEE_MOVE_SPEED: float = 72.0
const CHARGER_MOVE_SPEED: float = 62.0
const FAN_MOVE_SPEED: float = 58.0
const MELEE_WINDUP_TICKS: int = 5
const MELEE_ACTIVE_TICKS: int = 1
const MELEE_RECOVERY_TICKS: int = 11
const CHARGE_WINDUP_TICKS: int = 18
const CHARGE_ACTIVE_TICKS: int = 10
const CHARGE_RECOVERY_TICKS: int = 22
const FAN_WINDUP_TICKS: int = 21
const FAN_ACTIVE_TICKS: int = 1
const FAN_RECOVERY_TICKS: int = 28
const BOSS_TRANSITION_TICKS: int = 30
const BOSS_WINDUP_TICKS: int = 24
const BOSS_ACTIVE_TICKS: int = 1
const BOSS_RECOVERY_TICKS: int = 24
const HAZARD_WARNING_TICKS: int = 30
const HAZARD_ACTIVE_TICKS: int = 15
const HAZARD_CYCLE_TICKS: int = 90
const ELITE_BARRIER_PERIOD_TICKS: int = 60
const ELITE_BARRIER_ACTIVE_TICKS: int = 20
const TIMED_BREAK_BONUS_TICKS: int = 900
const ATTACK_SOURCE_ASSISTED: String = "assisted"
const ATTACK_SOURCE_POINTER: String = "pointer"
const ATTACK_SOURCE_PROXY: String = "proxy"

var selected_preset: String = "convergent"
var selected_mode: String = "Manual"
var locked_p: float = PiercingArrowModel.BASE_P
var locked_payload: float = BASE_PAYLOAD
var locked_targeting_distance: float = AUTO_RANGE
var locked_build: Dictionary = {}
var in_arena: bool = false
var encounter_director
var room_catalog
var enemies: Array[CombatEnemyState]:
	get:
		return encounter_director.enemies
	set(value):
		encounter_director.enemies = value
var boss: CombatEnemyState:
	get:
		return encounter_director.boss
	set(value):
		encounter_director.boss = value
var boss_maximum: BigValue:
	get:
		return combat_system.outcome_snapshot().boss_maximum
var boss_damage: BigValue:
	get:
		return combat_system.outcome_snapshot().boss_damage
var combat_system
var combat_simulation
var _charge_movement_policy = null
var _mobility_movement_policy = null
var player_combat_state := PlayerCombatStateScript.new()
var player_combat_rules := PlayerCombatRulesScript.new()
## Narrow, read-only observations used by room diagnostics and play_session.
var player_position: Vector2:
	get:
		return player_combat_state.snapshot(sim_tick)["player_position"]
var player_health: float:
	get:
		return float(player_combat_state.snapshot(sim_tick).get("player_health", 0.0))
var projectiles: Array[CombatArrowProjectile]:
	get:
		return combat_system.projectiles
var elapsed: float = 0.0
var sim_tick: int:
	get:
		return int(simulation_world.tick) if simulation_world != null else 0
	set(value):
		# Authority ticks are committed only by SimulationWorld.step_tick().
		# Retain the setter surface for scene/test construction, but never let a
		# caller fabricate a tick in the live room.
		pass
var shots: int:
	get:
		return int(combat_system.outcome_snapshot().shots)
var arrow_hits: int:
	get:
		return int(combat_system.outcome_snapshot().arrow_hits)
var defeated: int:
	get:
		return int(combat_system.outcome_snapshot().defeated)
var smoke_input_driver := SmokeInputDriverScript.new()
var room_rules := CombatRoomRulesScript.new()
var battle_over: bool:
	get:
		if room_encounter_port != null and room_encounter_port.encounter != null and room_encounter_port.encounter.has_method("snapshot"):
			var terminal: Dictionary = room_encounter_port.snapshot().get("terminal", {})
			if String(terminal.get("phase", "")) in ["victory", "defeat"]:
				return true
		return bool(room_rules.snapshot().battle_over)
var battle_victory: bool:
	get:
		if room_encounter_port != null and room_encounter_port.encounter != null and room_encounter_port.encounter.has_method("snapshot"):
			var terminal: Dictionary = room_encounter_port.snapshot().get("terminal", {})
			if String(terminal.get("phase", "")) in ["victory", "defeat"]:
				return bool(terminal.get("victory", false))
		return bool(room_rules.snapshot().battle_victory)
var battle_report: String = ""
var attack_requested: bool:
	get:
		return command_source.attack_requested if command_source != null else false
var attack_requested_source: String:
	get:
		return command_source.attack_requested_source if command_source != null else ""
var attack_requested_target_entity_id: int:
	get:
		return command_source.attack_requested_target_entity_id if command_source != null else 0
var attack_requested_pointer_gameplay: Vector2:
	get:
		return command_source.attack_requested_pointer_gameplay if command_source != null else Vector2.ZERO
var command_sequence: int = 0
var last_command_receipts: Array[Dictionary] = []
var last_loot_pickup_command_receipt: Dictionary = {}
var last_attack_outcome: Dictionary:
	get:
		return combat_system.last_attack_outcome
var content_registry
var proxy_runtime
var proxy_intent_system
var manual_aim_resolver
var enemy_tactics
var command_source
var command_source_port: RefCounted = null
var actor_registry
var scene_runtime
var simulation_world
var actor_registry_instance_id := ""
var actor_registry_revision := 0
## Mounted-room typed ports adopted from SceneRuntime (or the standalone room
## assembly). The fixed-tick kernel owns combat authority through them.
var room_spatial_port = null
var room_combat_port = null
var room_encounter_port = null
var encounter_spawn_port: RefCounted = null
var _hazard_domain = null
var _kernel_arrow_flight := RangerArrowFlightScript.new()
var _kernel_boss_flight := BossArrowFlightScript.new()
var _boss_combat_domain: BossCombatDomain = null
var _boss_domain_targets: Dictionary = {}
var _boss_settlement_cursor := 0
var _boss_encounter_authority := false
var _terminal_projection_applied := false
## Detached authority evidence: publication is recorded before any room-domain
## reconcile mutates legacy room mirrors.
var last_kernel_snapshot = null
var kernel_snapshot_publications: Array[Dictionary] = []
var kernel_reconcile_events: Array[Dictionary] = []
## Stable entity key ("actor/<key>") to legacy enemy entity id, rebuilt at
## every room registration boundary for death settlement reconciliation.
var _enemy_stable_keys: Dictionary = {}
var _kernel_settlement_cursor := 0
var combat_event_stream
var destiny_forge
var save_store
var startup_errors: Array[String] = []
var proxy_prediction: String = "unknown"
var contract_wins: int = 0
var last_drop_id: String = ""
var last_drop: String = "None"
var last_loot_rng_state: Dictionary = {}
var last_save_message: String = "No save yet"
var command_line_arguments: PackedStringArray = []
var test_session: bool = false
var embedded_session: bool = false
var presentation_enabled: bool = true
var state_hash_output_path: String = ""
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
var framework_seed: int = FATE_SEED
var _room_loot = CombatRoomLootScript.new()
var room_loot_enabled: bool:
	get:
		return _room_loot != null and _room_loot.enabled()
var room_loot_snapshot: Dictionary:
	get:
		return _room_loot.snapshot() if _room_loot != null else {"enabled": false, "entities": [], "events": [], "settlement": {}}
var room_loot_settlement: Dictionary:
	get:
		return _room_loot.settlement_snapshot() if _room_loot != null else {}
var room_loot_window_open: bool:
	get:
		return battle_victory and _room_loot != null and _room_loot.has_unsettled_entities()
var hazard_states: Array[Dictionary]:
	get:
		if _hazard_domain != null and _hazard_domain.is_configured():
			return _hazard_domain.snapshots()
		return encounter_director.hazard_states
	set(value):
		if _hazard_domain == null:
			encounter_director.hazard_states = value
var elite_rule_ids: Array[String]:
	get:
		return encounter_director.elite_rule_ids
	set(value):
		encounter_director.elite_rule_ids = value
var elite_entity_id: int:
	get:
		return encounter_director.elite_entity_id
	set(value):
		encounter_director.elite_entity_id = int(value)
var elite_barrier_active: bool:
	get:
		return encounter_director.elite_barrier_active
	set(value):
		encounter_director.elite_barrier_active = bool(value)
var reinforcements_summoned: bool:
	get:
		return encounter_director.reinforcements_summoned
	set(value):
		encounter_director.reinforcements_summoned = bool(value)
var timed_bonus_available: bool:
	get:
		return encounter_director.timed_bonus_available
	set(value):
		encounter_director.timed_bonus_available = bool(value)
var next_entity_id: int:
	get:
		return encounter_director.next_entity_id
	set(value):
		encounter_director.next_entity_id = int(value)
var next_enemy_action_instance_id: int:
	get:
		return encounter_director.next_enemy_action_instance_id
	set(value):
		encounter_director.next_enemy_action_instance_id = int(value)
var room_reward_snapshot: Dictionary:
	get:
		return room_rules.snapshot().room_reward_snapshot


var automation_smoke: bool = false
var automation_expected_contract_wins: int = 1
var automation_smoke_failure: String = ""
var presentation
var input_adapter
var lab_view
## Production fixed-tick phase owner. CombatSimulation never receives Main as a
## callback bag; it receives the typed RoomPhaseDomain declared at the bottom
## of this script. Phase dispatch is typed virtual calls only.
var room_phase_owner: CombatPhasePort = null

## These read-only input relays are used by CombatStateSnapshotBuilder; the
## device adapter is their sole state owner. No physical source ids are replay ids.
var manual_combat_input: RefCounted:
	get:
		return input_adapter.manual_combat_input if input_adapter != null else null
var manual_pointer_target_entity_id: int:
	get:
		return input_adapter.manual_pointer_target_entity_id if input_adapter != null else 0


func _init() -> void:
	presentation = PresentationController.new()
	presentation.name = "CombatPresentation"
	add_child(presentation)
	input_adapter = InputAdapter.new()

	_ensure_simulation_world()
	_ensure_combat_simulation()
	_ensure_room_catalog()
	_ensure_combat_system()
	_ensure_encounter_director()
	_ensure_encounter_spawn_port()
	_ensure_command_source()
	presentation.skill_requested.connect(_on_skill_requested)
	presentation.return_requested.connect(_on_return_requested)
	input_adapter.report_requested.connect(func(text: String) -> void: battle_report = text)
	combat_system.impact_trace_requested.connect(presentation.feedback.add_impact_traces)
	combat_system.corpse_requested.connect(presentation.animations.detach_corpse)


func _ensure_simulation_world() -> void:
	if simulation_world != null:
		return
	simulation_world = SimulationWorldScript.new()
	var configured = simulation_world.configure("combat/unmounted", 0, SIM_TICKS_PER_SECOND)
	if not configured.ok:
		push_error("simulation_world_initialization_failed:%s" % String(configured.error))


func _ensure_room_catalog() -> void:
	if room_catalog == null:
		room_catalog = RoomCatalogScript.new()


func _ensure_combat_simulation() -> void:
	if combat_simulation == null:
		combat_simulation = CombatSimulationScript.new()


func _ensure_encounter_director() -> void:
	if encounter_director != null:
		return
	encounter_director = EncounterDirectorScript.new()
	var room_port := MainEncounterRoomPort.new()
	var room_bound: Dictionary = room_port.bind(self, player_combat_rules, combat_system)
	if not bool(room_bound.get("ok", false)):
		push_error("encounter_room_port_bind_failed:%s" % String(room_bound.get("error", "unknown")))
		return
	var director_bound: Dictionary = encounter_director.bind_room(room_port)
	if not bool(director_bound.get("ok", false)):
		push_error("encounter_director_bind_failed:%s" % String(director_bound.get("error", "unknown")))
		return
	enemy_tactics = encounter_director.enemy_tactics


func _ensure_encounter_spawn_port() -> void:
	if encounter_spawn_port != null:
		return
	var port := MainEncounterSpawnPort.new()
	var bound: Dictionary = port.bind(self)
	if not bool(bound.get("ok", false)):
		push_error("encounter_spawn_port_bind_failed:%s" % String(bound.get("error", "unknown")))
		return
	encounter_spawn_port = port


func _ensure_combat_system() -> void:
	if combat_system == null:
		combat_system = CombatSystemScript.new()


func _configure_player_domain(start_tick: int) -> bool:
	var reset: Dictionary = player_combat_state.reset_for_room(locked_build, actor_registry, "ranger", start_tick)
	if not bool(reset.get("ok", false)):
		last_save_message = "Deployment blocked: %s" % String(reset.get("error", "player_reset_failed"))
		return false
	var rules_ready: Dictionary = player_combat_rules.configure(player_combat_state, simulation_world, combat_event_stream)
	if not bool(rules_ready.get("ok", false)):
		last_save_message = "Deployment blocked: %s" % String(rules_ready.get("error", "player_rules_unavailable"))
		return false
	if not _configure_combat_ports():
		return false
	_ensure_combat_simulation()
	var phase_domain := RoomPhaseDomain.new()
	var phase_bound: Dictionary = phase_domain.bind(self)
	if not bool(phase_bound.get("ok", false)):
		last_save_message = "Deployment blocked: %s" % String(phase_bound.get("error", "combat_phase_port_unavailable"))
		return false
	room_phase_owner = phase_domain
	var configured: Dictionary = combat_simulation.configure(simulation_world, player_combat_rules, phase_domain)
	if not bool(configured.get("ok", false)):
		last_save_message = "Deployment blocked: %s" % String(configured.get("error", "combat_simulation_unavailable"))
		return false
	return true


func _configure_combat_ports() -> bool:
	if replay_geometry_profile != CombatSystemScript.QUERY_PROFILE_MULTIPART_V2 and not automation_smoke:
		last_save_message = "Deployment blocked: historical replay profile requires auto smoke"
		return false
	var room_port := MainCombatRoomPort.new()
	var port_bound: Dictionary = room_port.bind(self)
	if not bool(port_bound.get("ok", false)):
		last_save_message = "Deployment blocked: %s" % String(port_bound.get("error", "combat_room_port_unavailable"))
		return false
	var configured: Dictionary = combat_system.bind_room(room_port, replay_geometry_profile)

	if not bool(configured.get("ok", false)):
		last_save_message = "Deployment blocked: %s" % String(configured.get("error", "combat_ports_unavailable"))
		return false
	return true


func _ready() -> void:
	command_line_arguments = OS.get_cmdline_user_args()
	test_session = embedded_session or command_line_arguments.has("--smoke") or command_line_arguments.has("--auto-smoke")
	for argument: String in command_line_arguments:
		if argument.begins_with("--state-hash-out="):
			state_hash_output_path = argument.trim_prefix("--state-hash-out=")
		elif argument.begins_with("--replay-geometry-profile="):
			replay_geometry_profile = argument.trim_prefix("--replay-geometry-profile=")
	_initialize_runtime()
	lab_view = LabView.new()
	add_child(lab_view)
	lab_view.build({"presets": content_registry.presets, "preset_order": content_registry.preset_order, "cores": content_registry.cores})
	lab_view.preset_requested.connect(_select_preset)
	lab_view.mode_requested.connect(_select_mode)
	lab_view.deploy_requested.connect(start_room)
	lab_view.forge_requested.connect(_choose_forge_candidate)
	startup_errors.append_array(presentation.load_assets(presentation_enabled, lab_view.interface_theme))
	_show_base()
	get_viewport().size_changed.connect(refresh_presentation)
	if not embedded_session:
		_handle_command_line()


func _process(delta: float) -> void:
	if not in_arena:
		return
	var snapshot := gameplay_snapshot()
	presentation.advance_time(snapshot, delta)
	if simulation_world == null or not simulation_world.has_method("ticks_for_frame"):
		push_error("simulation_world_unavailable")
		return
	var ticks_to_run: int = simulation_world.ticks_for_frame(delta)
	for _index in ticks_to_run:
		if not _can_simulate_tick():
			break
		_simulate_tick()
		refresh_presentation()
	# The display clock advances once per frame, regardless of tick batching.
	snapshot = gameplay_snapshot()
	presentation.commit(snapshot, input_adapter.view_state(snapshot), delta)


func _can_simulate_tick() -> bool:
	return in_arena and (not battle_over or room_loot_window_open)
func _unhandled_input(event: InputEvent) -> void:
	input_adapter.capture_actions(event, gameplay_snapshot())


func _input(event: InputEvent) -> void:
	input_adapter.capture_attack_event(event, presentation.is_pointer_over_interface(), gameplay_snapshot())


func release_manual_controls() -> void:
	input_adapter.reset_intent()
	# The lab has no configured player yet. Once a room owns the player, Rules
	# clears queued mobility on the current tick without producing a command.
	if String(player_combat_state.snapshot(sim_tick)["actor_id"]).is_empty():
		return
	var released: Dictionary = player_combat_rules.release_input(sim_tick)
	if not bool(released.get("ok", false)):
		push_error("player_input_release_failed:%s" % String(released.get("error", "unknown")))


func take_continuous_manual_input() -> RefCounted:
	return input_adapter.take_continuous_input(selected_mode)


func resume_continuous_manual_input(continued_input: RefCounted) -> void:
	input_adapter.resume_continuous_input(continued_input, gameplay_snapshot())


func set_effects_volume(value: float) -> void:
	presentation.feedback.set_effects_volume(value)


func _initialize_runtime() -> void:
	_ensure_encounter_director()
	if scene_runtime != null and scene_runtime.has_method("is_ready"):
		# A mounted Main adopts the SceneRuntime authorities before its first
		# frame. The scene configures its simulation and actor access before
		# this node enters the tree, so the LOADING lifecycle is not a fallback
		# trigger: falling back here would fork the room into two worlds.
		actor_registry = scene_runtime.get("actor_registry")
		simulation_world = scene_runtime.get("simulation")
		if actor_registry == null or simulation_world == null:
			startup_errors.append("native_room_authorities_unavailable")
	else:
		actor_registry = ActorRegistryScript.new()
		_ensure_simulation_world()
		var configured = simulation_world.configure("combat/unmounted", 0, SIM_TICKS_PER_SECOND)
		if not configured.ok:
			startup_errors.append("simulation_world_initialization_failed:%s" % String(configured.error))
	content_registry = ContentRegistryScript.new()
	startup_errors = content_registry.load_all()
	if content_registry.early_enemy_profile_registry != null and startup_errors.is_empty():
		var enemy_profiles_ready: Dictionary = encounter_director.set_enemy_profile_registry(content_registry.early_enemy_profile_registry)
		if not bool(enemy_profiles_ready.get("ok", false)):
			startup_errors.append("enemy_profiles: %s" % String(enemy_profiles_ready.get("error", "unavailable")))
	proxy_runtime = ProxyRuntimeScript.new()
	proxy_intent_system = ProxyIntentSystemScript.new()
	input_adapter.reset_intent()
	manual_aim_resolver = ManualAimResolverScript.new()
	combat_event_stream = CombatEventStreamScript.new()
	proxy_prediction = "unknown"
	var forge_families: Array[Dictionary] = [
		{"name": "growth_probability", "weight": 1},
		{"name": "shared_lifetime", "weight": 2},
		{"name": "branch_count", "weight": 2},
		{"name": "payload", "weight": 3},
		{"name": "flight_speed", "weight": 3},
		{"name": "turn_time", "weight": 1},
	]
	destiny_forge = DestinyForgeScript.new(FATE_SEED, forge_families, 3)
	destiny_forge.set_dice(DestinyForgeScript.TRACK_ADD, 6)
	save_store = SaveStoreScript.new()
	if not test_session:
		_load_progress()


func _load_progress() -> void:
	var loaded: Dictionary = save_store.load_latest()
	if not bool(loaded.get("ok", false)):
		last_save_message = "Fresh profile — save begins after a reward or forge choice"
		return
	var payload: Variant = loaded.get("payload", {})
	if not (payload is Dictionary) or int((payload as Dictionary).get("sim_protocol_version", -1)) != SAVE_PROTOCOL_VERSION:
		last_save_message = "Save ignored: incompatible simulation protocol"
		return
	var saved: Dictionary = payload
	contract_wins = maxi(0, int(saved.get("contract_wins", 0)))
	last_drop_id = String(saved.get("last_drop_id", ""))
	last_drop = String(saved.get("last_drop", "None"))
	var saved_loot_state: Variant = saved.get("last_loot_rng_state", {})
	if saved_loot_state is Dictionary:
		last_loot_rng_state = saved_loot_state.duplicate(true)
	var saved_preset := _normalize_preset_id(String(saved.get("selected_preset", selected_preset)))
	var saved_mode := String(saved.get("selected_mode", selected_mode))
	if content_registry.presets.has(saved_preset):
		selected_preset = saved_preset
	if saved_mode in ["Manual", "Auto"]:
		selected_mode = saved_mode
	var forge_state: Variant = saved.get("forge", {})
	if forge_state is Dictionary and not (forge_state as Dictionary).is_empty():
		if not destiny_forge.restore_state(forge_state):
			startup_errors.append("save: invalid forge state")
	last_save_message = "Recovered generation %d from slot %s (no offline progress)" % [int(loaded.generation), String(loaded.slot).to_upper()]


func _save_progress(reason: String) -> void:
	if test_session:
		return
	var result: Dictionary = save_store.save({
		"content_hash": _content_hash(),
		"contract_wins": contract_wins,
		"forge": destiny_forge.state(),
		"last_drop": last_drop,
		"last_drop_id": last_drop_id,
		"last_loot_rng_state": last_loot_rng_state,
		"offline_progress": 0,
		"selected_mode": selected_mode,
		"selected_preset": selected_preset,
		"sim_protocol_version": SAVE_PROTOCOL_VERSION,
	})
	if bool(result.get("ok", false)):
		last_save_message = "%s — generation %d / slot %s" % [reason, int(result.generation), String(result.slot).to_upper()]
	else:
		last_save_message = "SAVE FAILED: %s" % String(result.get("error", "unknown error"))


func _content_hash() -> String:
	var source := FileAccess.get_file_as_string(ContentRegistryScript.PROXY_PATH)
	source += "\n" + FileAccess.get_file_as_string(ContentRegistryScript.PRESET_PATH)
	source += "\n" + FileAccess.get_file_as_string("res://content/early_campaign.json")
	source += "\n" + FileAccess.get_file_as_string("res://content/early_items.json")
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return "unavailable"
	if context.update(source.to_utf8_buffer()) != OK:
		return "unavailable"
	return context.finish().hex_encode()


func _select_preset(preset: String) -> void:
	if not in_arena and content_registry.presets.has(preset):
		selected_preset = preset
		_refresh_lab()


func _select_mode(mode: String) -> void:
	if not in_arena:
		selected_mode = mode
		_refresh_lab()


func _normalize_preset_id(value: String) -> String:
	var normalized := value.strip_edges().to_lower()
	if content_registry.presets.has(normalized):
		return normalized
	# One-way compatibility for saves created by the earliest prototype.
	for preset_id in content_registry.preset_order:
		if String(content_registry.presets[preset_id].name).to_lower() == normalized:
			return preset_id
	return selected_preset


func _preset_display_name(preset_id: String) -> String:
	if not content_registry.presets.has(preset_id):
		return preset_id
	return "%s / %s" % [preset_id.capitalize(), String(content_registry.presets[preset_id].name)]


func _forge_family_name(family: String) -> String:
	return String(LabView.FORGE_FAMILY_LABELS.get(family, family))


func _next_empty_forge_slot() -> int:
	for index in destiny_forge.affixes.size():
		if (destiny_forge.affixes[index] as Dictionary).is_empty():
			return index
	return -1


func _choose_forge_candidate(choice_number: int) -> void:
	if in_arena or not startup_errors.is_empty():
		return
	var active_slot := _next_empty_forge_slot()
	if active_slot < 0:
		last_save_message = "All three prototype affix slots are filled"
		_refresh_lab()
		return
	var chosen: Dictionary = destiny_forge.choose(DestinyForgeScript.TRACK_ADD, active_slot, choice_number)
	if bool(chosen.get("ok", false)):
		var result: Dictionary = chosen.result
		last_drop = "Forged %s T%d" % [_forge_family_name(String(result.family)), int(result.tier)]
		_save_progress("Forge choice #%d committed" % choice_number)
	else:
		last_save_message = "Forge refused: %s" % String(chosen.get("error", "unknown error"))
	_refresh_lab()


func _show_base() -> void:
	in_arena = false
	room_rules.reset()
	_reset_room_loot()
	presentation.leave_arena()
	release_manual_controls()
	if proxy_runtime != null:
		proxy_runtime.end_contract()
	if proxy_intent_system != null:
		proxy_intent_system.reset()
	lab_view.show_base(presentation_enabled)
	_refresh_lab()
	refresh_presentation()


func start_room() -> void:
	if scene_runtime != null and (not scene_runtime.is_ready() or _arena_rect().size.x <= 0.0 or _arena_rect().size.y <= 0.0 or _collision_geometry(14.0).is_empty()):
		last_save_message = "Deployment blocked: native_room_geometry_unavailable"
		_refresh_lab()
		return
	if not startup_errors.is_empty():
		last_save_message = "Deployment blocked by content validation"
		_refresh_lab()
		return
	if embedded_session and not _resolved_build_is_valid(framework_resolved_build):
		last_save_message = "Deployment blocked: invalid_resolved_build"
		_refresh_lab()
		return
	var room_error := _framework_room_error()
	if not room_error.is_empty():
		last_save_message = "Deployment blocked: %s" % room_error
		_refresh_lab()
		return
	_freeze_room_build()
	var room_stats := _apply_room_combat_stats()
	if not bool(room_stats.get("ok", false)):
		last_save_message = "Deployment blocked: %s" % String(room_stats.get("error", "invalid_room_combat_stats"))
		_refresh_lab()
		return
	proxy_runtime.end_contract()
	if selected_mode == "Auto":
		var proxy_install: Dictionary = proxy_runtime.install_resolved(
			framework_resolved_proxy_build,
			"nearest_enemy"
		)
		if not bool(proxy_install.get("ok", false)):
			last_save_message = "Deployment blocked: proxy_%s" % String(proxy_install.get("error", "invalid_build"))
			_refresh_lab()
			return
		var proxy_start: Dictionary = proxy_intent_system.begin_contract(framework_resolved_proxy_build)
		if not bool(proxy_start.get("ok", false)):
			last_save_message = "Deployment blocked: proxy_%s" % String(proxy_start.get("error", "invalid_initial_state"))
			_refresh_lab()
			proxy_runtime.end_contract()
			return
	else:
		proxy_intent_system.reset()
	var contract_start: Dictionary = proxy_runtime.begin_contract(selected_mode.to_lower())
	if not bool(contract_start.get("ok", false)):
		last_save_message = "Deployment blocked: %s" % String(contract_start.get("error", "unknown error"))
		_refresh_lab()
		return
	var requirements := {
		"perception": {"target_count": 1},
		"movement": {"pathing": 1.0, "range_control": 1.0},
		"execution": {"skill_count": 1, "timing": 1.0},
		"memory": {"target_memory": 1, "rotation_steps": 1},
	}
	proxy_prediction = proxy_runtime.predict(requirements) if selected_mode == "Auto" else "manual"
	in_arena = true
	room_rules.reset()
	_reset_room_loot()
	lab_view.hide_base()
	input_adapter.reset_intent()
	command_sequence = 0
	last_command_receipts.clear()
	last_loot_pickup_command_receipt.clear()
	presentation.reset_battle()
	combat_event_stream.reset()
	automation_smoke_failure = ""
	room_entry_start_tick = 0
	elapsed = 0.0
	_terminal_projection_applied = false
	if scene_runtime != null and scene_runtime.is_ready() and simulation_world != null and sim_tick > 0:
		var restarted: Dictionary = scene_runtime.restart_room_instance(SIM_TICKS_PER_SECOND)
		if not bool(restarted.get("ok", false)):
			last_save_message = "Deployment blocked: %s" % String(restarted.get("error", "room_restart_failed"))
			in_arena = false
			_refresh_lab()
			return
		actor_registry = scene_runtime.get("actor_registry")
		simulation_world = scene_runtime.get("simulation")
	if simulation_world != null:
		simulation_world.reset_clock()
	battle_report = "Deployed: %s / %s. Proxy mode and loadout are locked for this contract." % [_preset_display_name(selected_preset), selected_mode]
	var reset: Dictionary = combat_system.reset_room(BigValue.from_power10(12.0))
	if not bool(reset.get("ok", false)):
		last_save_message = "Deployment blocked: %s" % String(reset.get("error", "combat_room_reset_failed"))
		in_arena = false
		return
	if not _spawn_wave():
		return
	if not _configure_actor_registry():
		if not last_save_message.begins_with("Deployment blocked:"):
			last_save_message = "Deployment blocked: actor_registry_configuration_failed"
		in_arena = false
		_refresh_lab()
		return
	var loot_room: Dictionary = framework_room.duplicate(true)
	if loot_room.is_empty() and test_session:
		loot_room = _load_test_room_fixture()
	var loot_configured: Dictionary = _configure_room_loot(loot_room)
	if not bool(loot_configured.get("ok", false)):
		last_save_message = "Deployment blocked: %s" % String(loot_configured.get("error", "room_loot_unavailable"))
		in_arena = false
		_refresh_lab()
		return
	if not _start_mounted_encounter():
		in_arena = false
		_refresh_lab()
		return
	refresh_presentation()


func _freeze_room_build() -> void:
	if _resolved_build_is_valid(framework_resolved_build):
		locked_build = framework_resolved_build.duplicate(true)
		locked_build["skills"] = (framework_active_build.get("skills", [String(locked_build.get("skill_id", "piercing_arrow"))]) as Array).duplicate()
	else:
		# The diagnostic model keeps its historical calibrated generation count;
		# its gameplay range remains the old Main AUTO_RANGE, frozen for Rules.
		var equipped: Dictionary = content_registry.preset_equipped_parameters
		var preset_p := float(content_registry.presets[selected_preset].p)
		var model: Dictionary = PiercingArrowModel.evaluate(preset_p, float(equipped.shared_lifetime), float(equipped.distance), float(equipped.speed), float(equipped.minimum_turn_time), true, true)
		var events: BigValue = model.total_events
		locked_build = {
			"skills": ["piercing_arrow"], "talent_capabilities": {},
			"final_parameters": {"p": preset_p, "T": float(equipped.shared_lifetime), "d": AUTO_RANGE, "v": float(equipped.speed), "turn": float(equipped.minimum_turn_time), "damage": BASE_PAYLOAD, "max_health": 100.0},
			"total_events": {"layer": events.layer, "magnitude": events.magnitude},
			"total_events_float": model.total_events_float, "generation_count": model.g,
			"R": model.R, "generation_time": model.generation_time, "growth_classification": model.state,
		}
	var parameters: Dictionary = locked_build.final_parameters
	locked_p = float(parameters.p)
	locked_payload = float(parameters.damage)
	locked_targeting_distance = float(parameters.d)


func _apply_room_combat_stats() -> Dictionary:
	if not framework_room.has("combat_stats"):
		return {"ok": true, "error": "", "enabled": false}
	var authored_room_id := room_id if not room_id.is_empty() else String(framework_room.get("room_id", framework_room.get("id", "")))
	var result := CombatStatsSnapshotScript.from_room_overlay(locked_build, framework_room.get("combat_stats"), authored_room_id)
	if not bool(result.get("ok", false)):
		return result
	var stats: Variant = result.get("value", null)
	if not stats is RefCounted or not stats.has_method("snapshot"):
		return {"ok": false, "error": "invalid_room_combat_stats_snapshot"}
	locked_build["combat_stats"] = stats.snapshot()
	return {"ok": true, "error": "", "enabled": true, "combat_stats": locked_build["combat_stats"].duplicate(true)}


func _spawn_wave() -> bool:
	## A new wave is a route reset: the enemy action presentation starts over.
	actor_registry_instance_id = ""
	presentation.reset_battle()
	input_adapter.reset_intent()
	if combat_event_stream != null:
		combat_event_stream.reset()
	_encounter_context()
	var spawn_room: Dictionary = framework_room.duplicate(true)
	if spawn_room.is_empty() and test_session:
		spawn_room = _load_test_room_fixture()
	var origin: Variant = _room_socket("combat/encounter-origin") if scene_runtime != null else _arena_rect().get_center()
	if not origin is Vector2 or not (origin as Vector2).is_finite():
		last_save_message = "Deployment blocked: missing_combat_encounter_origin"
		in_arena = false
		return false
	var mounted_encounter: bool = scene_runtime != null and scene_runtime.is_ready() and scene_runtime.get("encounter_domain") != null
	var spawned: Dictionary = encounter_director.prepare_room(spawn_room, origin) if mounted_encounter else encounter_director.spawn_wave(spawn_room, origin)
	if not bool(spawned.get("ok", false)):
		last_save_message = "Deployment blocked: %s" % String(spawned.get("error", "room_spawn_failed"))
		in_arena = false
		return false
	var hazard_configured: Dictionary = _configure_hazard_domain(spawn_room.get("hazard_ids", []), origin)
	if not bool(hazard_configured.get("ok", false)):
		last_save_message = "Deployment blocked: %s" % String(hazard_configured.get("error", "hazard_domain_failed"))
		in_arena = false
		return false
	room_id = String(spawned.get("room_id", ""))
	layout_id = String(spawned.get("layout_id", ""))
	objective_id = String(spawned.get("objective_id", "clear"))
	room_drop_tags = (framework_room.get("drop_tags", []) as Array).duplicate(true) if embedded_session else []
	_encounter_context()
	var reward_port := MainRewardPort.new()
	var reward_bound: Dictionary = reward_port.bind(self)
	if not bool(reward_bound.get("ok", false)):
		last_save_message = "Deployment blocked: %s" % String(reward_bound.get("error", "room_reward_port_unavailable"))
		in_arena = false
		return false
	var configured: Dictionary = room_rules.reset_for_room(
		{"objective_id": objective_id, "drop_tags": room_drop_tags}, embedded_session,
		selected_mode, FATE_SEED, {"contract_wins": contract_wins, "cores": content_registry.cores},
		reward_port
	)
	if not bool(configured.get("ok", false)):
		last_save_message = "Deployment blocked: %s" % String(configured.get("error", "room_rules_unavailable"))
		in_arena = false
		return false
	return true


func _reset_room_loot() -> void:
	_room_loot.reset()


func _configure_room_loot(room: Dictionary) -> Dictionary:
	if content_registry == null or content_registry.early_item_registry == null:
		_room_loot.reset()
		return {"ok": false, "error": "loot_item_registry_unavailable"} if room.has("loot_slots") else {"ok": true, "error": "", "enabled": false}
	var placement_room: Variant = scene_runtime if scene_runtime != null and scene_runtime.is_ready() else actor_registry
	var placement_port := MainLootPlacementPortScript.new()
	var placement_bound: Dictionary = placement_port.configure(placement_room)
	if not bool(placement_bound.get("ok", false)):
		_room_loot.reset()
		return placement_bound
	return _room_loot.configure(room, room_id, framework_seed, content_registry.early_item_registry, placement_port)


func _configure_hazard_domain(hazard_ids: Variant, center: Vector2) -> Dictionary:
	if encounter_director == null or encounter_director.room_port == null:
		return {"ok": false, "error": "hazard_room_port_unavailable"}
	if not hazard_ids is Array:
		return {"ok": false, "error": "invalid_hazard_ids"}
	var domain: RefCounted = CombatHazardDomainScript.new()
	var configured: Dictionary = domain.configure_ids(encounter_director.room_port, _arena_rect(), hazard_ids, center)
	if not bool(configured.get("ok", false)):
		return configured
	_hazard_domain = domain
	var read_bound: Dictionary = encounter_director.set_hazard_read_port(domain)
	if not bool(read_bound.get("ok", false)):
		return read_bound
	# The director's tactics snapshot consumes the same detached view objects;
	# it no longer advances or resolves them in production.
	encounter_director.hazard_states = _hazard_domain.snapshots()
	return {"ok": true, "error": "", "count": _hazard_domain.hazards.size()}


func _spawn_room_loot_for_source(source: String, source_entity_id: int, position: Vector2) -> Dictionary:
	return _room_loot.spawn_for_source(sim_tick, source, source_entity_id, position)


func request_loot_pickup(loot_entity_id: String) -> Dictionary:
	return _room_loot.request_pickup(sim_tick, in_arena, battle_over, battle_victory, loot_entity_id)


func _process_room_loot_pickups_tick() -> void:
	var player := player_combat_state.snapshot(sim_tick)
	var receipts_before: Array = (_room_loot.snapshot().get("pickup_receipts", []) as Array).duplicate(true)
	_room_loot.process_pickups(sim_tick, float(player.get("player_health", 0.0)), player.player_position, battle_over, battle_victory)
	var receipts_after: Array = _room_loot.snapshot().get("pickup_receipts", [])
	if receipts_after.size() > receipts_before.size() and presentation != null and presentation.feedback != null:
		var receipt_value: Variant = receipts_after[receipts_after.size() - 1]
		if receipt_value is Dictionary and bool((receipt_value as Dictionary).get("ok", false)):
			presentation.feedback.show_input_feedback("掉落已拾取 · 离场后计入结算", sim_tick)
		elif receipt_value is Dictionary:
			presentation.feedback.show_input_feedback("掉落未拾取 · %s" % String((receipt_value as Dictionary).get("error", "请求失效")), sim_tick)


func _settle_room_loot(outcome: String) -> void:
	_room_loot.settle(outcome)


func settle_room_loot(outcome: String) -> Dictionary:
	if outcome not in ["victory", "defeat", "abandoned"]:
		return {"ok": false, "error": "invalid_loot_outcome"}
	return _room_loot.settle(outcome)


func _load_test_room_fixture() -> Dictionary:
	const FIXTURE_PATH := "res://content/rooms/combat/test_fixture.json"
	if not FileAccess.file_exists(FIXTURE_PATH):
		return {}
	var file := FileAccess.open(FIXTURE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


func _configure_actor_registry() -> bool:
	var room_key := room_id.strip_edges()
	if room_key.is_empty():
		push_error("actor_registry_configuration_failed:missing_room_id")
		return false
	if scene_runtime != null and not scene_runtime.is_ready():
		push_error("actor_registry_configuration_failed:scene_runtime_not_ready")
		return false
	var injected_runtime: bool = scene_runtime != null
	if injected_runtime:
		# SceneRuntime is the only authority for a mounted room: its actor
		# access, SimulationWorld, and the world's bound ports are adopted
		# as-is. Main must never rebuild or replace them here, including when
		# presentation is disabled.
		actor_registry = scene_runtime.get("actor_registry")
		simulation_world = scene_runtime.get("simulation")
		actor_registry_instance_id = String(scene_runtime.get("room_instance_id"))
		actor_registry_revision = int(scene_runtime.get("world_revision"))
		if actor_registry == null or simulation_world == null or actor_registry_instance_id.is_empty():
			push_error("actor_registry_configuration_failed:injected_access_missing")
			return false
		room_spatial_port = scene_runtime.get("spatial_port")
		room_combat_port = scene_runtime.get("combat_port")
		room_encounter_port = scene_runtime.get("encounter_port")
		if presentation_enabled:
			scene_runtime.clear_actor_presentation_bindings()
			var presentation_ready: Dictionary = scene_runtime.prepare_presentation()
			if not bool(presentation_ready.get("ok", false)):
				push_error("presentation_projector_configuration_failed:%s" % String(presentation_ready.get("error", "unknown")))
				return false
	else:
		if not _configure_standalone_room_access(room_key):
			push_error("actor_registry_configuration_failed:standalone_access_failed")
			return false
	if not _bind_kernel_room_ports():
		actor_registry_instance_id = ""
		return false
	var movement_policy_port := MainMovementPolicyPort.new()
	var movement_policy_bound: Dictionary = movement_policy_port.bind(self)
	if not bool(movement_policy_bound.get("ok", false)):
		push_error("actor_registry_configuration_failed:movement_policy_port:%s" % String(movement_policy_bound.get("error", "unknown")))
		actor_registry_instance_id = ""
		return false
	actor_registry.set_movement_policy_port(movement_policy_port)
	var preserved_sim_tick := sim_tick
	if actor_registry.has_method("reset_actors"):
		var reset_result: Dictionary = actor_registry.reset_actors()
		if not bool(reset_result.get("ok", false)):
			push_error("actor_registry_configuration_failed:actor_reset:%s" % str(reset_result))
			actor_registry_instance_id = ""
			return false
	if not actor_registry.has_method("has_movement_boundary") or not bool(actor_registry.has_movement_boundary()):
		push_error("manifest_movement_boundary_missing:%s" % layout_id)
		push_error("actor_registry_configuration_failed:movement_boundary_missing")
		actor_registry_instance_id = ""
		return false
	var spawn_position: Vector2
	if injected_runtime:
		var authored_spawn: Variant = _room_socket("combat/spawn")
		if not authored_spawn is Vector2 or not actor_registry.is_position_clear(authored_spawn, 14.0):
			push_error("actor_registry_configuration_failed:invalid_player_spawn:%s" % str(authored_spawn))
			return false
		spawn_position = authored_spawn
	else:
		var projected: Dictionary = _project_actor_spawn_position(_arena_rect().get_center() + Vector2(-220.0, 100.0), 14.0)
		if not bool(projected.get("ok", false)):
			return false
		spawn_position = _quantize_position(projected["position"])
	var player_result: Dictionary = actor_registry.register_actor("ranger", spawn_position, 14.0, 1, &"soft", [&"movement", &"hurtbox"])
	if not bool(player_result.get("ok", false)):
		push_error("actor_registry_configuration_failed:player_registration:%s" % str(player_result))
		actor_registry_instance_id = ""
		return false
	if injected_runtime and presentation_enabled and not _bind_runtime_actor_presentation("ranger", "ranger.south.idle", 2):
		return false
	for enemy: CombatEnemyState in enemies:
		if not _register_enemy_actor(enemy):
			push_error("actor_registry_configuration_failed:enemy_registration:%d" % enemy.entity_id)
			actor_registry_instance_id = ""
			return false
	# Standalone Main fixtures do not own a SceneRuntime/RoomEncounter port.
	# Mounted production rooms do, and must bind the Boss domain to that typed
	# encounter authority. Keep the standalone authority self-contained so
	# geometry and combat tests can exercise a Boss without inventing a second
	# encounter runtime.
	if scene_runtime != null and not _bind_boss_production_encounter():
		actor_registry_instance_id = ""
		return false
	# The mounted SimulationWorld starts at tick zero.  A live room never
	# rewinds or fabricates its authority tick during actor registration.
	if not _configure_player_domain(preserved_sim_tick):
		push_error("actor_registry_configuration_failed:player_domain:%s" % last_save_message)
		actor_registry_instance_id = ""
		return false
	return true


func _configure_standalone_room_access(room_key: String) -> bool:
	actor_registry_revision += 1
	actor_registry_instance_id = "combat/%s/%d" % [room_key, actor_registry_revision]
	var boundary := ArenaGeometryScript.movement_boundary(layout_id, _arena_rect())
	if boundary.is_empty():
		return false
	var static_build: Dictionary = StaticSpatialIndexScript.build({
		"schema_version": StaticSpatialIndexScript.SCHEMA_VERSION,
		"asset_id": "runtime/%s" % layout_id,
		"surfaces": [],
		"movement_boundary": _boundary_for_static_index(boundary),
	})
	if not bool(static_build.get("ok", false)):
		return false
	var static_index = static_build.get("value")
	var dynamic_index = DynamicSpatialIndexScript.new()
	var overlay = SpatialOverlayScript.new()
	var movement_build: Dictionary = MovementResolverScript.make(static_index, overlay, dynamic_index)
	if not bool(movement_build.get("ok", false)):
		return false
	var spatial_port = RoomSpatialPortScript.new()
	var combat_port = RoomCombatPortScript.new()
	var encounter_port = RoomEncounterPortScript.new()
	var presentation_port = RoomPresentationPortScript.new()
	var raw_registry = ActorRegistryScript.new()
	simulation_world = SimulationWorldScript.new(spatial_port, combat_port, encounter_port, presentation_port, raw_registry)
	var configured = simulation_world.configure(actor_registry_instance_id, actor_registry_revision, SIM_TICKS_PER_SECOND)
	if not configured.ok:
		return false
	var access = RoomActorAccessScript.new()
	var access_result: Dictionary = access.configure(simulation_world, raw_registry, static_index, dynamic_index, movement_build.get("value"), overlay)
	if not bool(access_result.get("ok", false)):
		return false
	actor_registry = access
	spatial_port.bind(access)
	combat_port.bind(access)
	room_spatial_port = spatial_port
	room_combat_port = combat_port
	room_encounter_port = encounter_port
	return true


func _boundary_for_static_index(boundary: Dictionary) -> Dictionary:
	var kind := String(boundary.get("type", boundary.get("kind", "")))
	match kind:
		"rect", "corridor":
			var rect: Variant = boundary.get("rect", null)
			var value := {"kind": kind, "rect": rect}
			if kind == "corridor":
				value["half_height"] = float(boundary.get("half_height", 0.0))
			return value
		"ring":
			return {
				"kind": "ring",
				"center": boundary.get("center", Vector2.ZERO),
				"inner_radius": float(boundary.get("inner_radius", 0.0)),
				"outer_radius": float(boundary.get("outer_radius", 0.0)),
			}
	return {}


	## Production encounter materialization for the mounted room. RoomEncounter
	## owns when and how many actors appear; EncounterDirector only creates the
	## room-local state object requested by that typed deployment fact.
## The returned entity key is the kernel settlement identity
## ("actor/<stable_key>"), so a later DeathSettlement reaches the bound
## RoomEncounter under the same key. Unmatched requests fail closed; this
	## method never fabricates a receipt and never registers a duplicate actor.
func reconcile_encounter_spawn(request: Variant, _context: Variant) -> Variant:
	if request == null or not request is EncounterSpawnRequestScript:
		return EncounterSpawnResultScript.failed(request, "invalid_encounter_spawn_request")
	if scene_runtime == null or not scene_runtime.is_ready() or actor_registry == null:
		return EncounterSpawnResultScript.failed(request, "runtime_not_ready")
	var archetype := String(request.archetype_id).strip_edges()
	if archetype.is_empty():
		return EncounterSpawnResultScript.failed(request, "invalid_encounter_archetype")
	var position_value: Variant = _room_socket(String(request.socket_id))
	if not position_value is Vector2 or not (position_value as Vector2).is_finite():
		return EncounterSpawnResultScript.failed(request, "encounter_spawn_socket_unavailable")
	var spawn_position: Vector2 = encounter_director.encounter_spawn_position(position_value)
	var created: Dictionary = encounter_director.create_encounter_enemy(archetype, spawn_position)
	if not bool(created.get("ok", false)):
		return EncounterSpawnResultScript.failed(request, String(created.get("error", "encounter_enemy_create_failed")))
	var enemy: CombatEnemyState = created.get("enemy", null)
	if enemy == null or not _register_enemy_actor(enemy):
		encounter_director.discard_encounter_enemy(enemy)
		return EncounterSpawnResultScript.failed(request, "encounter_actor_registration_failed")
	var actor_id := "enemy/%d" % enemy.entity_id
	var handle = actor_registry.actor_handle(actor_id)
	if handle == null or not handle.is_valid():
		encounter_director.discard_encounter_enemy(enemy)
		return EncounterSpawnResultScript.failed(request, "encounter_actor_handle_unavailable")
	var entity_key: String = actor_registry.entity_key_for_handle(handle)
	var stable_key := int(actor_registry.actor_snapshot(actor_id).get("stable_key", 0))
	if entity_key.is_empty() or stable_key < 1:
		encounter_director.discard_encounter_enemy(enemy)
		return EncounterSpawnResultScript.failed(request, "encounter_actor_identity_unavailable")
	_sync_encounter_active_state()
	return EncounterSpawnResultScript.spawned(
		request,
		handle,
		entity_key,
		stable_key,
		handle.generation,
		String(scene_runtime.room_instance_id),
		int(scene_runtime.world_revision)
	)


func _start_mounted_encounter() -> bool:
	if scene_runtime == null or not scene_runtime.is_ready():
		return true
	var encounter_domain: Variant = scene_runtime.get("encounter_domain")
	if encounter_domain == null:
		return true
	var phase := String(encounter_domain.snapshot().get("phase", "")) if encounter_domain.has_method("snapshot") else ""
	if phase != "idle" and sim_tick == 0 and encounter_domain.has_method("restart"):
		var restarted: Dictionary = encounter_domain.restart(sim_tick)
		if not bool(restarted.get("ok", false)):
			last_save_message = "Deployment blocked: %s" % String(restarted.get("error", "encounter_restart_failed"))
			return false
		phase = "idle"
	if phase == "idle":
		var started: Dictionary = scene_runtime.start_encounter(sim_tick)
		if not bool(started.get("ok", false)):
			last_save_message = "Deployment blocked: %s" % String(started.get("error", "encounter_start_failed"))
			return false
	var encounter_port = scene_runtime.get("encounter_port")
	if encounter_port != null and encounter_port.has_method("prime_spawn_requests"):
		encounter_port.prime_spawn_requests(sim_tick)
	var materialized: Array[Dictionary] = scene_runtime.materialize_encounter_spawns()
	for result: Dictionary in materialized:
		if String(result.get("kind", "")) == "failed":
			last_save_message = "Deployment blocked: encounter_spawn_failed:%s" % String(result.get("error", "unknown"))
			return false
	return true



func _register_enemy_actor(enemy: CombatEnemyState) -> bool:
	if actor_registry == null or enemy == null:
		push_error("enemy_actor_registration_failed:missing_dependency")
		return false
	var projected: Dictionary = _project_actor_spawn_position(enemy.position, 16.0)
	if not bool(projected.get("ok", false)):
		push_error("enemy_actor_registration_failed:projection:%d:%s" % [enemy.entity_id, str(projected)])
		return false
	var position: Vector2 = projected["position"]
	if not actor_registry.is_position_clear(position, 16.0):
		push_error("enemy_actor_registration_failed:blocked:%d:%s" % [enemy.entity_id, str(position)])
		return false
	var drop_tags: Array[String] = []
	for tag: Variant in room_drop_tags:
		drop_tags.append(String(tag))
	var registered: Dictionary = actor_registry.register_actor(
		"enemy/%d" % enemy.entity_id, position, 16.0, maxi(1, roundi(enemy.health)), &"soft",
		[&"movement", &"hurtbox"], PackedStringArray(), maxf(1.0, enemy.maximum_health), {},
		enemy.kind_id, "enemy/%d" % enemy.entity_id, drop_tags
	)
	if not bool(registered.get("ok", false)):
		push_error("enemy_actor_registration_failed:register:%d:%s" % [enemy.entity_id, str(registered)])
	if bool(registered.get("ok", false)):
		enemy.position = position
		_enemy_stable_keys["actor/%d" % int(registered.stable_key)] = enemy.entity_id
		if enemy.is_boss and not _register_boss_kernel_target(enemy, int(registered.stable_key), enemies.find(enemy)):
			return false
		if scene_runtime != null and presentation_enabled:
			var role := "melee"
			match enemy.kind_id:
				"charging_raider": role = "charger"
				"fan_ranged": role = "ranged"
			if not _bind_runtime_actor_presentation("enemy/%d" % enemy.entity_id, "enemy.%s.idle" % role, 1):
				return false
	return bool(registered.get("ok", false))


func _register_boss_kernel_target(enemy: CombatEnemyState, stable_key: int, ordinal: int) -> bool:
	if not _boss_domain_room_is_current():
		push_error("boss_domain_registration_room_mismatch")
		return false
	if stable_key < 1 or ordinal < 0:
		push_error("boss_domain_registration_identity_invalid:%d:%d" % [enemy.entity_id, stable_key])
		return false
	var maximum: BigValue = combat_system.outcome_snapshot().boss_maximum
	if maximum == null or maximum.is_zero():
		push_error("boss_domain_maximum_unavailable:%d" % enemy.entity_id)
		return false
	var target_key := "actor/%d" % stable_key
	var drop_tags: Array[String] = []
	for tag: Variant in room_drop_tags:
		drop_tags.append(String(tag))
	var target := BossTargetViewScript.make(
		target_key,
		maximum,
		enemy.position,
		enemy.kind_id,
		_production_boss_spawn_key(enemy, ordinal),
		drop_tags
	)
	for part: Dictionary in enemy.hurtbox_parts():
		var hurtbox: Variant = (part.get("hurtbox", {}) as Dictionary).get("radius", null)
		var boss_part := BossHurtboxScript.make(
			String(part.get("part_id", "")),
			String(part.get("damage_group_id", "body")),
			part.get("pose", Vector2.ZERO),
			float(hurtbox),
			bool(part.get("active", true)),
			bool(part.get("broken", false))
		)
		var added: Dictionary = target.add_part(boss_part)
		if not bool(added.get("ok", false)):
			push_error("boss_domain_part_registration_failed:%s" % String(added.get("error", "unknown")))
			return false
	var registered: Dictionary = _boss_combat_domain.register_target(target)
	if not bool(registered.get("ok", false)):
		push_error("boss_domain_target_registration_failed:%s" % String(registered.get("error", "unknown")))
		return false
	_boss_domain_targets[int(enemy.entity_id)] = target
	return true


func _production_boss_spawn_key(enemy: CombatEnemyState, ordinal: int) -> String:
	return "wave.production/%s.%d/0" % [enemy.kind_id, ordinal]


func _bind_boss_production_encounter() -> bool:
	if boss == null:
		return true
	if scene_runtime == null or not scene_runtime.is_ready():
		push_error("boss_encounter_runtime_unavailable")
		return false
	# CombatRoomRuntime owns the single mixed-room encounter composition.  Its
	# production wave includes both ordinary roster actors and this Boss, so a
	# second Boss-only bind here would replace the shared domain and split
	# terminal/death authority.  Boss-only Main construction still uses this
	# fallback binding.
	var mounted_room_roster: Variant = framework_room.get("enemy_ids", [])
	if embedded_session and mounted_room_roster is Array and not (mounted_room_roster as Array).is_empty():
		return true
	var spawns: Array = []
	for index: int in enemies.size():
		var enemy: CombatEnemyState = enemies[index]
		spawns.append({
			"spawn_id": "%s.%d" % [enemy.kind_id, index],
			"archetype_id": enemy.kind_id,
			"socket_id": "combat/encounter-origin",
			"count": 1,
		})
	var encounter := RoomEncounterScript.new()
	var configured: Dictionary = encounter.configure(room_id, [{
		"wave_id": "wave.production",
		"clear_policy": "all_dead",
		"spawns": spawns,
	}])
	if not bool(configured.get("ok", false)):
		push_error("boss_encounter_configure_failed:%s" % String(configured.get("error", "unknown")))
		return false
	var bound: Dictionary = scene_runtime.bind_encounter(encounter, encounter_spawn_port)
	if not bool(bound.get("ok", false)):
		push_error("boss_encounter_bind_failed:%s" % String(bound.get("error", "unknown")))
		return false
	var started: Dictionary = scene_runtime.start_encounter(sim_tick)
	if not bool(started.get("ok", false)):
		push_error("boss_encounter_start_failed:%s" % String(started.get("error", "unknown")))
		return false
	room_encounter_port = scene_runtime.get("encounter_port")
	_boss_encounter_authority = true
	return true


func _bind_runtime_actor_presentation(actor_id: String, visual_id: String, rank: int) -> bool:
	if scene_runtime == null or not presentation_enabled:
		return true
	var world_view: Variant = presentation.world_view if presentation != null else null
	if world_view == null or not world_view.has_method("sprite_art_box"):
		push_error("presentation_art_box_unavailable:%s" % visual_id)
		return false
	var world_box: Rect2 = world_view.sprite_art_box(visual_id, Vector2.ZERO)
	if world_box.size.x <= 0.0 or world_box.size.y <= 0.0:
		push_error("presentation_art_box_missing:%s" % visual_id)
		return false
	# Simulation actors use authored gameplay pixels while the skin draws at its
	# fixed world scale. Convert the real art box once into the projector's
	# detached gameplay coordinate domain; never substitute the hurtbox radius.
	var scale := ArenaWorldViewScript.GAMEPLAY_TO_WORLD
	var gameplay_box := Rect2(world_box.position / scale, world_box.size / scale)
	var bound: Dictionary = scene_runtime.bind_actor_presentation(actor_id, visual_id, rank, gameplay_box)
	if not bool(bound.get("ok", false)):
		push_error("presentation_binding_failed:%s:%s" % [actor_id, String(bound.get("error", "unknown"))])
		return false
	return true


func _ensure_actor_registry_ready() -> bool:
	if actor_registry_instance_id.is_empty():
		if not _configure_actor_registry():
			return false
	return actor_registry != null and actor_registry.has_actor("ranger")


func teleport_actor(actor_id: String, position: Vector2) -> Dictionary:
	var normalized_id := actor_id.strip_edges()
	if normalized_id != "ranger" and not normalized_id.begins_with("enemy/"):
		return {"ok": false, "error": "unsupported_actor_id"}
	var enemy: CombatEnemyState = null
	if normalized_id != "ranger":
		var entity_id := int(normalized_id.trim_prefix("enemy/"))
		enemy = _enemy_by_entity_id(entity_id)
		if enemy == null:
			return {"ok": false, "error": "enemy_mirror_not_found"}
	if not _ensure_actor_registry_ready() or not position.is_finite():
		return {"ok": false, "error": "actor_registry_not_ready_or_invalid_position"}
	var result: Dictionary = actor_registry.teleport_actor(normalized_id, position)
	if not bool(result.get("ok", false)):
		return result
	if normalized_id == "ranger":
		return result
	enemy.position = position
	return result


func _commit_actor_move(actor_id: String, displacement: Vector2, movement_policy: Variant = null) -> Dictionary:
	if not _ensure_actor_registry_ready():
		return {"ok": false, "error": "actor_registry_not_ready", "position": Vector2.ZERO, "displacement": Vector2.ZERO}
	var state = actor_registry.actor(actor_id)
	if state == null:
		return {"ok": false, "error": "actor_not_registered", "position": Vector2.ZERO, "displacement": Vector2.ZERO}
	if movement_policy == null and actor_id == "ranger" and _has_active_charge():
		movement_policy = _charge_movement_policy_value()
	var result: Dictionary = actor_registry.move_actor(actor_id, displacement, sim_tick, movement_policy)
	if not bool(result.get("ok", false)):
		if String(result.get("error", "")) in ["non_monotonic_motor_tick", "non_monotonic_movement_tick"]:
			return result
		push_error("actor_move_failed:%s:%s" % [actor_id, String(result.get("error", "unknown"))])
		return result
	return result


func _charge_movement_policy_value() -> Variant:
	if _charge_movement_policy != null:
		return _charge_movement_policy
	var built: Dictionary = BodyCollisionPolicyScript.make({
		"solid": {"response": BodyCollisionPolicyScript.RESPONSE_BLOCK, "record": true},
		"soft": {"response": BodyCollisionPolicyScript.RESPONSE_IGNORE, "record": true},
		"ghost": {"response": BodyCollisionPolicyScript.RESPONSE_IGNORE, "record": true},
	})
	if bool(built.get("ok", false)):
		_charge_movement_policy = built.get("value")
	return _charge_movement_policy


## Main-owned mobility policy seam: an active dash/dodge crosses enemy soft
## bodies instead of being separated away, while contacts stay recorded for
## presentation. Normal movement keeps the default soft separation policy.
func _resolve_ranger_movement_policy(actor_id: String) -> Variant:
	if actor_id != "ranger" or player_combat_state == null:
		return null
	var player: Dictionary = player_combat_state.snapshot(sim_tick)
	if int(player.get("dash_remaining_ticks", 0)) <= 0 and int(player.get("dodge_remaining_ticks", 0)) <= 0:
		return null
	return _mobility_policy_value()


func _mobility_policy_value() -> Variant:
	if _mobility_movement_policy != null:
		return _mobility_movement_policy
	var built: Dictionary = BodyCollisionPolicyScript.make({
		"solid": {"response": BodyCollisionPolicyScript.RESPONSE_BLOCK, "record": true},
		"soft": {"response": BodyCollisionPolicyScript.RESPONSE_IGNORE, "record": true},
		"ghost": {"response": BodyCollisionPolicyScript.RESPONSE_IGNORE, "record": true},
	})
	if bool(built.get("ok", false)):
		_mobility_movement_policy = built.get("value")
	return _mobility_movement_policy


func _has_active_charge() -> bool:
	for enemy: CombatEnemyState in enemies:
		if enemy != null and enemy.action_state == "active" and enemy.action_id == "charge":
			return true
	return false


func _move_enemy_actor(enemy: CombatEnemyState, displacement: Vector2) -> Dictionary:
	var before := enemy.position
	var movement_policy: Variant = null
	if enemy.action_state == "active" and enemy.action_id == "charge":
		movement_policy = _charge_movement_policy_value()
	var result := _commit_actor_move("enemy/%d" % enemy.entity_id, displacement, movement_policy)
	if bool(result.get("ok", false)):
		enemy.position = result.get("position", before)
		enemy.facing = result.get("facing", enemy.facing)
	return result


func _simulate_tick() -> void:
	_ensure_combat_simulation()
	var result: Dictionary = combat_simulation.step()
	if not bool(result.get("ok", false)):
		push_error("combat_simulation_step_failed:%s" % String(result.get("error", "unknown")))


func _room_domain_is_ready() -> bool:
	return (
		in_arena
		and simulation_world != null
		and player_combat_rules != null
		and combat_system != null
		and encounter_director != null
		and input_adapter != null
	)


func _simulation_set_elapsed(value: float) -> void:
	elapsed = value


func _simulation_collect_commands() -> Array[Dictionary]:
	var snapshot := gameplay_snapshot()
	var loot_command: Dictionary = input_adapter.collect_loot_pickup_command(snapshot)
	if loot_command.is_empty() and selected_mode == "Auto":
		loot_command = _auto_loot_pickup_command(snapshot)
	if not loot_command.is_empty():
		_submit_loot_pickup_command(loot_command)
	if embedded_session and automation_smoke and selected_mode == "Manual":
		var result: Dictionary = smoke_input_driver.decide({
			"player": player_combat_state.snapshot(sim_tick), "targets": _read_only_targets(),
			"hazards": hazard_states.duplicate(true), "targeting_distance": locked_targeting_distance,
			"boss": {"impact_tick": boss.impact_tick, "target_shape": boss.target_shape.duplicate(true)} if boss != null else {},
		}, command_sequence)
		command_sequence = int(result.next_sequence)
		return result.commands
	return _auto_commands() if selected_mode == "Auto" else input_adapter.collect_commands(gameplay_snapshot())


func _submit_loot_pickup_command(command: Dictionary) -> Dictionary:
	var arbitration: Dictionary = CombatLootPickupProtocolScript.arbitrate([command], sim_tick, "ranger")
	var receipts: Array = arbitration.get("receipts", [])
	var receipt: Dictionary = receipts[0].duplicate(true) if not receipts.is_empty() and receipts[0] is Dictionary else {"status": "rejected", "reason": "invalid_receipt", "command": command.duplicate(true)}
	if String(receipt.get("status", "")) == CombatLootPickupProtocolScript.STATUS_ACCEPTED:
		var normalized: Dictionary = receipt.get("command", {})
		var room_receipt := request_loot_pickup(String(normalized.get("loot_entity_id", "")))
		receipt["room_receipt"] = room_receipt.duplicate(true)
		if not bool(room_receipt.get("accepted", false)) and selected_mode == "Manual" and presentation != null and presentation.feedback != null:
			presentation.feedback.show_input_feedback("掉落未进入拾取范围 · 靠近后再按 F", sim_tick)
	last_loot_pickup_command_receipt = receipt.duplicate(true)
	return last_loot_pickup_command_receipt.duplicate(true)


func _auto_loot_pickup_command(snapshot: Dictionary) -> Dictionary:
	if not bool(snapshot.get("in_arena", false)) or (bool(snapshot.get("battle_over", false)) and not bool(snapshot.get("battle_victory", false))):
		return {}
	var room_loot_value: Variant = snapshot.get("room_loot", {})
	if not room_loot_value is Dictionary:
		return {}
	var room_loot: Dictionary = room_loot_value
	var pending_ids: Dictionary = {}
	for pending_value: Variant in room_loot.get("pending_pickup_requests", []):
		if pending_value is Dictionary:
			pending_ids[String((pending_value as Dictionary).get("loot_entity_id", ""))] = true
	var player_position_value: Variant = snapshot.get("player_position", Vector2.ZERO)
	var player_position := player_position_value as Vector2 if player_position_value is Vector2 else Vector2.ZERO
	var nearest_id := ""
	var nearest_distance := INF
	for entity_value: Variant in room_loot.get("entities", []):
		if not entity_value is Dictionary:
			continue
		var entity: Dictionary = entity_value
		var loot_id := String(entity.get("loot_entity_id", "")).strip_edges()
		if loot_id.is_empty() or String(entity.get("state", "")) != "available" or pending_ids.has(loot_id):
			continue
		var position_value: Variant = entity.get("position", Vector2.ZERO)
		var position := position_value as Vector2 if position_value is Vector2 else Vector2.ZERO
		var radius := maxf(0.0, float(entity.get("pickup_radius", 0.0)))
		var distance := player_position.distance_squared_to(position)
		if distance > radius * radius + 0.000001:
			continue
		if distance < nearest_distance or (is_equal_approx(distance, nearest_distance) and (nearest_id.is_empty() or loot_id < nearest_id)):
			nearest_distance = distance
			nearest_id = loot_id
	if nearest_id.is_empty():
		return {}
	return _loot_pickup_command(nearest_id)


func _simulation_check_timeout() -> void:
	if automation_smoke and not battle_over and sim_tick >= SIM_TICKS_PER_SECOND * 180:
		_fail_automation_smoke("timeout ticks=%d casts=%d" % [sim_tick, shots])


func _bind_kernel_room_ports() -> bool:
	if room_spatial_port == null or room_combat_port == null or room_encounter_port == null:
		push_error("kernel_room_ports_unavailable")
		return false
	var hit_admission_port := MainHitAdmissionPort.new()
	var admission_bound: Dictionary = hit_admission_port.bind(self)
	if not bool(admission_bound.get("ok", false)):
		push_error("kernel_hit_admission_port_bind_failed:%s" % String(admission_bound.get("error", "unknown")))
		return false
	var filter_bound: Dictionary = room_combat_port.bind_hit_admission_port(hit_admission_port)
	if not bool(filter_bound.get("ok", false)):
		push_error("kernel_hit_admission_port_bind_failed:%s" % String(filter_bound.get("error", "unknown")))
		return false
	var player_damage_bound: Dictionary = room_combat_port.bind_player_rule_port(player_combat_rules)
	if not bool(player_damage_bound.get("ok", false)):
		push_error("kernel_player_damage_port_bind_failed:%s" % String(player_damage_bound.get("error", "unknown")))
		return false
	var flight_configured: Dictionary = _kernel_arrow_flight.configure(room_spatial_port)
	if not bool(flight_configured.get("ok", false)):
		push_error("kernel_arrow_flight_configure_failed:%s" % String(flight_configured.get("error", "unknown")))
		return false
	if not _bind_boss_kernel_domain():
		return false
	last_kernel_snapshot = null
	kernel_snapshot_publications.clear()
	kernel_reconcile_events.clear()
	_enemy_stable_keys.clear()
	_kernel_settlement_cursor = 0
	_boss_domain_targets.clear()
	_boss_settlement_cursor = 0
	_boss_encounter_authority = false
	return true


func _bind_boss_kernel_domain() -> bool:
	if simulation_world == null or String(simulation_world.room_instance_id).is_empty() or int(simulation_world.world_revision) < 0:
		push_error("boss_domain_room_identity_unavailable")
		return false
	var domain := BossCombatDomainScript.new()
	var configured: Dictionary = domain.configure(String(simulation_world.room_instance_id), int(simulation_world.world_revision))
	if not bool(configured.get("ok", false)):
		push_error("boss_domain_configure_failed:%s" % String(configured.get("error", "unknown")))
		return false
	var spatial_bound: Dictionary = room_spatial_port.bind_boss_domain(domain)
	if not bool(spatial_bound.get("ok", false)):
		push_error("boss_spatial_domain_bind_failed:%s" % String(spatial_bound.get("error", "unknown")))
		return false
	var combat_bound: Dictionary = room_combat_port.bind_boss_domain(domain)
	if not bool(combat_bound.get("ok", false)):
		push_error("boss_combat_domain_bind_failed:%s" % String(combat_bound.get("error", "unknown")))
		return false
	if room_spatial_port.boss_domain != domain or room_combat_port.boss_domain != domain:
		push_error("boss_domain_instance_mismatch")
		return false
	var boss_flight_configured: Dictionary = _kernel_boss_flight.configure(room_spatial_port)
	if not bool(boss_flight_configured.get("ok", false)):
		push_error("kernel_boss_flight_configure_failed:%s" % String(boss_flight_configured.get("error", "unknown")))
		return false
	_boss_combat_domain = domain
	return true


func _boss_domain_room_is_current() -> bool:
	return (
		_boss_combat_domain != null
		and room_spatial_port != null
		and room_spatial_port.boss_domain == _boss_combat_domain
		and room_combat_port != null
		and room_combat_port.boss_domain == _boss_combat_domain
		and simulation_world != null
		and _boss_combat_domain.room_id == String(simulation_world.room_instance_id)
		and int(_boss_combat_domain.world_revision) == int(simulation_world.world_revision)
	)


func _is_boss_kernel_projectile(projectile) -> bool:
	if projectile == null:
		return false
	var enemy := _enemy_by_entity_id(int(projectile.target_entity_id))
	return enemy != null and enemy.is_boss and _boss_domain_room_is_current()


func _is_normal_kernel_projectile(projectile) -> bool:
	if projectile == null or room_spatial_port == null or room_combat_port == null:
		return false
	var enemy := _enemy_by_entity_id(int(projectile.target_entity_id))
	return enemy == null or not enemy.is_boss


func _is_kernel_projectile(projectile) -> bool:
	if projectile == null or room_spatial_port == null or room_combat_port == null:
		return false
	return _is_normal_kernel_projectile(projectile) or _is_boss_kernel_projectile(projectile)


## The room-facing enemy record remains the health record other migrating
## systems read; the actor store is the kernel resolution substrate. They are
## synced at query submission so DamageResolution always resolves the current
## committed health, and the reconcile mirrors the result back.
## The room-facing enemy record remains the record other migrating systems
## read and mutate; the actor store is the kernel resolution substrate. Both
## health and pose are synced at query submission so the spatial indexes and
## DamageResolution always resolve the current committed room-facing record.
## In production the mirror is written after actor commits, so the pose sync
## is a no-op; a failed relocation keeps the authoritative actor pose.
func _sync_kernel_target_record(projectile) -> void:
	var enemy := _enemy_by_entity_id(int(projectile.target_entity_id))
	if enemy == null or enemy.is_boss:
		return
	var actor_id := "enemy/%d" % enemy.entity_id
	if actor_registry == null or not actor_registry.has_actor(actor_id):
		return
	var state = actor_registry.actor(actor_id)
	if state == null or not state.alive:
		return
	if state.feet_position.distance_squared_to(enemy.position) > 0.000001:
		var relocated: Dictionary = actor_registry.teleport_actor(actor_id, enemy.position)
		if bool(relocated.get("ok", false)):
			enemy.position = relocated.get("position", enemy.position)
	# The room-facing record may legally sit above its spawn maximum (legacy
	# fixtures raise health without raising maximum); the actor store must be
	# able to hold the current committed value.
	state.maximum_health = maxf(state.maximum_health, maxf(maxf(1.0, enemy.health), enemy.maximum_health))
	if absf(state.health - enemy.health) > 0.0005:
		state.commit_resolved_health(maxf(0.0, enemy.health))


## Keeps the detached BossTargetView pose/part facts equal to the actor-backed
## room mirror before a query. Health is deliberately not copied: once the room
## starts, BossCombatDomain owns BigValue health and mortality.
func _sync_boss_kernel_target(projectile) -> BossTargetView:
	var enemy := _enemy_by_entity_id(int(projectile.target_entity_id))
	if enemy == null or not enemy.is_boss or not _boss_domain_room_is_current():
		return null
	var target: BossTargetView = _boss_domain_targets.get(int(enemy.entity_id), null)
	if target == null or not target.alive:
		return null
	var actor_id := "enemy/%d" % enemy.entity_id
	if actor_registry != null and actor_registry.has_actor(actor_id):
		var state = actor_registry.actor(actor_id)
		if state == null or not state.alive:
			return null
		enemy.position = state.feet_position
	target.position = enemy.position
	var admission_blocked: bool = encounter_director != null and encounter_director.is_target_blocked(enemy)
	var admission := target.set_admission(admission_blocked, "periodic_barrier" if admission_blocked else "")
	if not bool(admission.get("ok", false)):
		push_error("boss_domain_admission_sync_failed:%s" % String(admission.get("error", "unknown")))
		return null
	for room_part: Dictionary in enemy.hurtbox_parts():
		for boss_part: BossHurtbox in target.parts:
			if boss_part.part_id != String(room_part.get("part_id", "")):
				continue
			boss_part.local_offset = room_part.get("pose", boss_part.local_offset)
			var state_result: Dictionary = target.set_part_state(
				boss_part.part_id,
				bool(room_part.get("active", true)),
				bool(room_part.get("broken", false))
			)
			if not bool(state_result.get("ok", false)):
				push_error("boss_domain_part_sync_failed:%s" % boss_part.part_id)
				return null
	return target


## Hit admission at the damage boundary. Keeps the legacy arrow contract
## while the sweep itself moved to the kernel's typed path queries: only the
## locked non-boss target is admitted, and the elite periodic barrier
## suppresses the hit before DamageResolution.
func _admit_kernel_hit(hit: Dictionary) -> Dictionary:
	var attack_id := String(hit.get("attack_instance_id", ""))
	if not attack_id.begins_with("arrow/"):
		return {"allowed": true, "reason": ""}
	var action_id := int(attack_id.trim_prefix("arrow/"))
	var projectile = null
	for candidate in combat_system.projectiles:
		if int(candidate.action_instance_id) == action_id:
			projectile = candidate
			break
	if projectile == null:
		return {"allowed": false, "reason": "arrow_not_in_flight"}
	var enemy := _enemy_by_entity_id(int(projectile.target_entity_id))
	if enemy == null or enemy.is_boss:
		return {"allowed": false, "reason": "legacy_big_value_target"}
	var hit_entity_id := int(_enemy_stable_keys.get(String(hit.get("target_key", "")), 0))
	if hit_entity_id != int(projectile.target_entity_id):
		return {"allowed": false, "reason": "not_locked_target"}
	if encounter_director != null and encounter_director.is_target_blocked(enemy):
		return {"allowed": false, "reason": "periodic_barrier"}
	return {"allowed": true, "reason": ""}


func _enemy_by_stable_key(target_key: String) -> CombatEnemyState:
	var entity_id := int(_enemy_stable_keys.get(target_key, 0))
	if entity_id <= 0:
		return null
	return _enemy_by_entity_id(entity_id)


func _consume_kernel_room_combat() -> void:
	if room_spatial_port == null or room_combat_port == null or not _kernel_arrow_flight.is_configured():
		return
	var published_snapshot = simulation_world.latest_snapshot() if simulation_world != null else null
	if published_snapshot != null and published_snapshot.has_method("sha256_hex"):
		var published_tick := int(published_snapshot.tick)
		if last_kernel_snapshot == null or int(last_kernel_snapshot.tick) != published_tick:
			last_kernel_snapshot = published_snapshot
			kernel_snapshot_publications.append({
				"tick": published_tick,
				"room_instance_id": String(published_snapshot.room_instance_id),
				"world_revision": int(published_snapshot.world_revision),
				"phase": "kernel.snapshot.published",
				"hash": published_snapshot.sha256_hex(),
			})
	_combat_context()
	var previous_report := String(combat_system.battle_report)
	var previous_event_id: int = combat_event_stream.latest_event_id()
	var results: Array = room_spatial_port.take_path_results()
	var records: Array = _kernel_arrow_flight.pending_records()
	var published_tick := int(last_kernel_snapshot.tick) if last_kernel_snapshot != null else -1
	var published_hash: String = last_kernel_snapshot.sha256_hex() if last_kernel_snapshot != null and last_kernel_snapshot.has_method("sha256_hex") else ""
	kernel_reconcile_events.append({
		"phase": "room.reconcile.begin",
		"tick": sim_tick,
		"snapshot_tick": published_tick,
		"snapshot_hash": published_hash,
		"path_results": results.size(),
		"pending_arrows": records.size(),
	})
	var admitted: Dictionary = {}
	for hit: Dictionary in room_combat_port.last_hits:
		admitted[String(hit.get("attack_instance_id", ""))] = hit
	var suppressed: Dictionary = {}
	for entry: Variant in room_combat_port.last_batch.get("suppressed", []):
		if entry is Dictionary:
			suppressed[String((entry as Dictionary).get("attack_instance_id", ""))] = entry
	var outcome_by_attack: Dictionary = {}
	for outcome: Variant in room_combat_port.last_batch.get("outcomes", []):
		if outcome is Dictionary:
			outcome_by_attack[String((outcome as Dictionary).get("attack_instance_id", ""))] = outcome
	var count := mini(results.size(), records.size())
	for index in count:
		var result = results[index]
		var record = records[index]
		var projectile = record.projectile
		if projectile == null or not combat_system.projectiles.has(projectile):
			continue
		var attack_key: String = record.attack_key
		if admitted.has(attack_key) and outcome_by_attack.has(attack_key):
			_reconcile_kernel_hit(projectile, record, admitted[attack_key], outcome_by_attack[attack_key])
			kernel_reconcile_events.append({
				"phase": "room.reconcile.arrow_hit",
				"tick": sim_tick,
				"snapshot_tick": published_tick,
				"snapshot_hash": published_hash,
				"attack_instance_id": attack_key,
				"target_key": String(admitted[attack_key].get("target_key", "")),
			})
			_retire_kernel_projectile(projectile, attack_key)
			continue
		if suppressed.has(attack_key):
			var rejection: Dictionary = suppressed[attack_key]
			# Only a barrier block on the locked target consumes the arrow.
			# Every other suppression (a piercing pass-through on a non-locked
			# hurtbox, a legacy BigValue target) leaves the arrow in flight.
			if String(rejection.get("reason", "")) == "periodic_barrier":
				var blocked_enemy := _enemy_by_stable_key(String(rejection.get("target_key", "")))
				var blocked_point_value: Variant = rejection.get("contact_point", projectile.position)
				var blocked_point: Vector2 = blocked_point_value if blocked_point_value is Vector2 else projectile.position
				projectile.position = blocked_point
				combat_system.apply_kernel_blocked(projectile, blocked_enemy, blocked_point)
				_retire_kernel_projectile(projectile, attack_key)
				continue
		if result != null and bool(result.clipped):
			projectile.position = result.end_point
			combat_system.resolve_projectile_miss(projectile)
			_retire_kernel_projectile(projectile, attack_key)
			continue
		if projectile.distance_travelled >= projectile.maximum_range:
			combat_system.resolve_projectile_miss(projectile)
			_retire_kernel_projectile(projectile, attack_key)
	_kernel_arrow_flight.clear_pending()
	_reconcile_kernel_deaths()
	_consume_kernel_boss_combat(published_tick, published_hash)
	kernel_reconcile_events.append({
		"phase": "room.reconcile.end",
		"tick": sim_tick,
		"snapshot_tick": published_tick,
		"snapshot_hash": published_hash,
		"path_results": results.size(),
		"pending_arrows": records.size(),
	})
	_combat_report(previous_report, previous_event_id)


func _retire_kernel_projectile(projectile, attack_key: String) -> void:
	combat_system.remove_projectile(projectile)
	_kernel_arrow_flight.forget_arrow(attack_key)


func _consume_kernel_boss_combat(published_tick: int, published_hash: String) -> void:
	if not _kernel_boss_flight.is_configured():
		return
	if not _boss_domain_room_is_current():
		push_error("boss_domain_room_mismatch:%s:%d" % [String(_boss_combat_domain.room_id), int(_boss_combat_domain.world_revision)])
		_kernel_boss_flight.clear_pending()
		return
	var results: Array = room_spatial_port.take_boss_path_results()
	var records: Array = _kernel_boss_flight.pending_records()
	var batch: Dictionary = room_combat_port.last_boss_batch
	if not (batch.get("rejected", []) as Array).is_empty():
		push_error("boss_damage_resolution_rejected:%s" % str(batch.get("rejected", [])))
	var outcome_by_attack: Dictionary = {}
	for outcome: Variant in batch.get("outcomes", []):
		if outcome is Dictionary:
			outcome_by_attack[String((outcome as Dictionary).get("attack_instance_id", ""))] = outcome
	var suppressed_by_attack: Dictionary = {}
	for suppressed: Variant in batch.get("suppressed", []):
		if suppressed is Dictionary:
			var suppressed_value: Dictionary = suppressed as Dictionary
			suppressed_by_attack[String(suppressed_value.get("attack_instance_id", ""))] = suppressed_value
	var count := mini(results.size(), records.size())
	for index in count:
		var result = results[index]
		var record = records[index]
		var projectile = record.projectile
		if projectile == null or not combat_system.projectiles.has(projectile):
			continue
		var attack_key: String = record.attack_key
		if not outcome_by_attack.has(attack_key):
			if suppressed_by_attack.has(attack_key):
				var suppression: Dictionary = suppressed_by_attack[attack_key]
				if String(suppression.get("reason", "")) == "periodic_barrier":
					var blocked_enemy := _enemy_by_entity_id(int(projectile.target_entity_id))
					var blocked_point_value: Variant = suppression.get("contact_point", projectile.position)
					var blocked_point: Vector2 = blocked_point_value if blocked_point_value is Vector2 else projectile.position
					projectile.position = blocked_point
					combat_system.apply_kernel_blocked(projectile, blocked_enemy, blocked_point)
					_retire_boss_kernel_projectile(projectile, attack_key)
					continue
			if result != null and bool(result.clipped):
				projectile.position = result.end_point
				combat_system.resolve_projectile_miss(projectile)
				_retire_boss_kernel_projectile(projectile, attack_key)
			elif projectile.distance_travelled >= projectile.maximum_range:
				combat_system.resolve_projectile_miss(projectile)
				_retire_boss_kernel_projectile(projectile, attack_key)
			continue
		var outcome: Dictionary = outcome_by_attack[attack_key]
		var enemy := _enemy_by_entity_id(int(projectile.target_entity_id))
		if enemy == null or not enemy.is_boss:
			push_error("boss_kernel_target_mirror_unresolved:%s" % attack_key)
			continue
		var target: BossTargetView = _boss_domain_targets.get(int(enemy.entity_id), null)
		if target == null or record.health_before == null:
			push_error("boss_kernel_target_domain_unresolved:%s" % attack_key)
			continue
		var applied: BigValue = _big_value_from_snapshot(outcome.get("applied_damage", {}).get("big", {}))
		var remaining: BigValue = _big_value_from_snapshot(outcome.get("remaining_health", {}))
		if applied == null or remaining == null:
			push_error("boss_kernel_outcome_big_value_invalid:%s" % attack_key)
			continue
		var mirrored: Dictionary = combat_system.sync_boss_domain_resolution(target.maximum_health, applied, remaining)
		if not bool(mirrored.get("ok", false)):
			push_error("boss_domain_mirror_failed:%s" % String(mirrored.get("error", "unknown")))
			continue
		var contact := _boss_contact_for_outcome(result, outcome)
		var contact_point: Vector2 = contact.get("contact_point", projectile.position) if contact.get("contact_point", null) is Vector2 else projectile.position
		projectile.position = contact_point
		enemy.hit_flash_until_tick = sim_tick + ENEMY_HIT_FLASH_TICKS
		combat_system.apply_boss_kernel_contact(
			projectile,
			enemy,
			contact_point,
			contact,
			record.health_before,
			remaining,
			record.aggregate
		)
		kernel_reconcile_events.append({
			"phase": "room.reconcile.boss_arrow_hit",
			"tick": sim_tick,
			"snapshot_tick": published_tick,
			"snapshot_hash": published_hash,
			"attack_instance_id": attack_key,
			"target_key": target.target_key,
			"part_id": String(outcome.get("part_id", "body")),
		})
		_retire_boss_kernel_projectile(projectile, attack_key)
		if bool(outcome.get("lethal", false)):
			enemy.health = 0.0
			_finalize_boss_kernel_death(enemy, target)
	_kernel_boss_flight.clear_pending()
	_settle_boss_kernel_deaths(published_tick)


func _boss_contact_for_outcome(result: Variant, outcome: Dictionary) -> Dictionary:
	if result == null:
		return {}
	var part_id := String(outcome.get("part_id", ""))
	for contact: BossHitContact in result.hit_contacts:
		if contact.part_id == part_id:
			return {"part_id": contact.part_id, "damage_group_id": contact.damage_group_id, "contact_point": contact.contact_point}
	if not result.hit_contacts.is_empty():
		var first: BossHitContact = result.hit_contacts[0]
		return {"part_id": first.part_id, "damage_group_id": first.damage_group_id, "contact_point": first.contact_point}
	return {}


func _big_value_from_snapshot(value: Variant) -> BigValue:
	if not value is Dictionary:
		return null
	var data: Dictionary = value
	return BigValue.from_components(int(data.get("layer", -1)), float(data.get("magnitude", NAN)))


func _retire_boss_kernel_projectile(projectile, attack_key: String) -> void:
	combat_system.remove_projectile(projectile)
	_kernel_boss_flight.forget_arrow(attack_key)


func _finalize_boss_kernel_death(enemy: CombatEnemyState, target: BossTargetView) -> void:
	var actor_id := "enemy/%d" % enemy.entity_id
	if actor_registry != null and actor_registry.has_actor(actor_id):
		var unregistered: Dictionary = actor_registry.unregister_actor(actor_id)
		if not bool(unregistered.get("ok", false)):
			push_error("boss_actor_unregister_failed:%d:%s" % [enemy.entity_id, String(unregistered.get("error", "unknown"))])
	_boss_domain_targets.erase(int(enemy.entity_id))
	_finalize_kernel_enemy_death(enemy)


func _settle_boss_kernel_deaths(settlement_tick: int) -> void:
	if not _boss_domain_room_is_current():
		return
	if settlement_tick < 0:
		return
	var settled: Dictionary = room_combat_port.settle_boss_deaths(settlement_tick)
	if not bool(settled.get("ok", false)):
		push_error("boss_death_settlement_failed:%s" % String(settled.get("error", "unknown")))
		return
	var settlements: Array[Dictionary] = room_combat_port.last_boss_settlements
	var notifications: Array[RefCounted] = room_combat_port.last_boss_death_notifications
	var context := SimTickContextScript.new()
	context.tick = settlement_tick
	context.room_instance_id = String(simulation_world.room_instance_id)
	context.world_revision = int(simulation_world.world_revision)
	while _boss_settlement_cursor < settlements.size():
		var settlement: Dictionary = settlements[_boss_settlement_cursor]
		var notification: Variant = notifications[_boss_settlement_cursor] if _boss_settlement_cursor < notifications.size() else null
		_boss_settlement_cursor += 1
		if room_encounter_port != null and notification is DeathSettlementNotificationScript:
			room_encounter_port.on_death_settlement(notification, context)
		elif room_encounter_port != null:
			push_error("boss_death_notification_missing:%s" % String(settlement.get("entity_key", "")))
		var loot_value: Variant = settlement.get("loot_spawn_request", {})
		if loot_value is Dictionary and not (loot_value as Dictionary).is_empty():
			var entity_id := int(_enemy_stable_keys.get(String(settlement.get("entity_key", "")), 0))
			if entity_id <= 0:
				push_error("boss_death_loot_entity_unresolved:%s" % String(settlement.get("entity_key", "")))
				continue
			var position_value: Variant = (loot_value as Dictionary).get("position", Vector2.ZERO)
			var position: Vector2 = position_value if position_value is Vector2 else Vector2.ZERO
			_spawn_room_loot_for_source("enemy_death", entity_id, position)


func _reconcile_kernel_hit(projectile, record: Variant, hit: Dictionary, outcome: Dictionary) -> void:
	var enemy := _enemy_by_stable_key(String(hit.get("target_key", "")))
	if enemy == null:
		return
	var health_before: float = enemy.health
	var remaining: float = clampf(float(outcome.get("remaining_health", 0.0)), 0.0, maxf(enemy.maximum_health, health_before))
	# The resolver reports the target-side surface point; the authoritative
	# contact for events and traces is the point on the frozen arrow path.
	var toi := clampf(float(hit.get("toi", 0.0)), 0.0, 1.0)
	var contact: Vector2 = record.query_start + record.query_displacement * toi
	enemy.health = snappedf(remaining, 0.001)
	enemy.hit_flash_until_tick = sim_tick + ENEMY_HIT_FLASH_TICKS
	projectile.position = contact
	combat_system.apply_kernel_contact(projectile, enemy, contact, hit, health_before, enemy.health, record.aggregate)
	_maybe_summon_reinforcements(enemy)
	if enemy.health <= 0.0:
		_finalize_kernel_enemy_death(enemy)


func _finalize_kernel_enemy_death(enemy: CombatEnemyState) -> void:
	enemies.erase(enemy)
	combat_system.note_kernel_death(enemy)
	var canceled_request_id: int = _cancel_buffered_target(enemy.entity_id)
	if canceled_request_id > 0:
		_erase_attack_request(canceled_request_id)
	_refresh_player_mark()


func _reconcile_kernel_deaths() -> void:
	var settlements: Array[Dictionary] = room_combat_port.last_settlements
	while _kernel_settlement_cursor < settlements.size():
		var settlement: Dictionary = settlements[_kernel_settlement_cursor]
		_kernel_settlement_cursor += 1
		var loot_value: Variant = settlement.get("loot_spawn_request", {})
		if not loot_value is Dictionary or (loot_value as Dictionary).is_empty():
			continue
		var entity_id := int(_enemy_stable_keys.get(String(settlement.get("entity_key", "")), 0))
		if entity_id <= 0:
			push_error("kernel_death_loot_entity_unresolved:%s" % String(settlement.get("entity_key", "")))
			continue
		var position_value: Variant = (loot_value as Dictionary).get("position", Vector2.ZERO)
		var position: Vector2 = position_value if position_value is Vector2 else Vector2.ZERO
		_spawn_room_loot_for_source("enemy_death", entity_id, position)


func _route_commands(commands: Array[Dictionary]) -> Dictionary:
	return CombatCommandProtocolScript.arbitrate(commands, sim_tick, player_combat_state.equipped_ability_ids(), true)


func _read_only_targets() -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	for enemy: CombatEnemyState in enemies:
		targets.append(_manual_aim_candidate(enemy))
	return targets


func _refresh_player_mark() -> void:
	player_combat_rules.update_mark(sim_tick, _read_only_targets())


func _consume_player_events(result: Dictionary) -> void:
	# Both the pre-command timeline and post-command timeline have their own
	# pre-motor context. Never let later mark expiry/movement alter arrow release.
	var player: Dictionary = result["player"]
	var action_player: Dictionary = result.get("action_player", player)
	for receipt: Dictionary in result.get("receipts", []):
		var command: Dictionary = receipt.get("command", {})
		if String(command.get("ability_id", "")) == "piercing_arrow":
			var default_source := ATTACK_SOURCE_PROXY if selected_mode == "Auto" else ATTACK_SOURCE_ASSISTED
			var source: String = presentation.feedback.take_command_source(int(command.get("sequence", -1)), default_source)
			_present_cast_receipt(receipt, source)
		else:
			if String(command.get("ability_id", "")) == "hunter_mark":
				_present_mark_receipt(receipt, player)
			presentation.feedback.discard_command(int(command.get("sequence", -1)))
	if result.has("protocol_receipts"):
		last_command_receipts.assign((result["protocol_receipts"] as Array).duplicate(true))
	_combat_context(action_player)
	_process_player_action_events(result.get("action_events", []), action_player)
	_combat_context(player)


func _present_cast_receipt(receipt: Dictionary, source: String) -> void:
	if bool(receipt.get("accepted", false)):
		var request_id := int(receipt.get("request_id", 0))
		presentation.feedback.remember_request_source(request_id, source, int(receipt.get("replaced_request_id", 0)))
		if String(receipt.get("status", "")) == "started":
			presentation.feedback.bind_action_request(int(receipt.get("action_instance_id", 0)), request_id)
		battle_report = "穿刺箭已缓冲，等待动作窗口。" if String(receipt.get("status", "")) in ["buffered", "replaced"] else "穿刺箭拉弓中。"
	elif String(receipt.get("reason", "")) == "target_out_of_range" and selected_mode == "Manual" and source != ATTACK_SOURCE_PROXY:
		presentation.feedback.show_input_feedback("目标在射程外 · 靠近后再射", sim_tick)


func request_player_cast(ability_id: String, target_entity_id: int = 0, direction: Vector2 = Vector2.ZERO, source: String = ATTACK_SOURCE_ASSISTED) -> Dictionary:
	# Explicit diagnostic input enters the same domain as device/replay commands.
	var receipt: Dictionary = player_combat_rules.request_cast(sim_tick, ability_id, target_entity_id, direction, _read_only_targets())
	if ability_id == "piercing_arrow":
		_present_cast_receipt(receipt, source)
	elif ability_id == "hunter_mark":
		_present_mark_receipt(receipt, player_combat_state.snapshot(sim_tick))
	_process_player_action_events(receipt.get("action_events", []), player_combat_state.snapshot(sim_tick))
	return receipt


func _present_mark_receipt(receipt: Dictionary, player: Dictionary) -> void:
	if not bool(receipt.get("accepted", false)):
		return
	var target := _enemy_by_entity_id(int(player["marked_entity_id"]))
	if target != null and target.health > 0.0:
		battle_report = "猎人印记锁定：%s。" % presentation.frame_builder.enemy_public_label(target)


func interrupt_player_action(reason: String) -> Dictionary:
	var result: Dictionary = player_combat_rules.interrupt_action(sim_tick, reason)
	presentation.feedback.forget_request(int(result.get("cleared_request_id", 0)))
	_process_player_action_events(result.get("events", []), player_combat_state.snapshot(sim_tick))
	return result


func _auto_commands() -> Array[Dictionary]:
	var observation := _public_proxy_snapshot()
	var collision_geometry := _collision_geometry(14.0)
	if not collision_geometry.is_empty():
		observation["walkable_geometry"] = collision_geometry
	var result: Dictionary = proxy_intent_system.decide(observation, command_sequence)
	if not bool(result.get("ok", false)):
		return []
	command_sequence = int(result.get("next_sequence", command_sequence))
	return (result.get("commands", []) as Array).duplicate(true)


func _proxy_failure_snapshot() -> Dictionary:
	if proxy_intent_system == null:
		return {}
	return proxy_intent_system.failure_snapshot()


func _proxy_trace_snapshot() -> Array[String]:
	if proxy_intent_system == null:
		return []
	return proxy_intent_system.trace_snapshot()


func _public_proxy_snapshot() -> Dictionary:
	var player := player_combat_state.snapshot(sim_tick)
	var public_geometry := _walkable_geometry(14.0).duplicate(true)
	## Public geometry describes only the space the actor may occupy. Route and
	## room identifiers remain private even if a future helper revision carries
	## spatial metadata alongside the geometric primitives.
	public_geometry.erase("layout_id")
	var observations: Array = framework_resolved_proxy_build.get("observation_contract", [])
	var include_classification := "enemy.public_classification_tags" in observations
	var visible: Array[Dictionary] = []
	for enemy: CombatEnemyState in enemies:
		var entry := {
			"entity_id": enemy.entity_id,
			"position": enemy.position,
			"health": enemy.health,
			## Action legality is part of enemy.basic. It reveals no barrier rule,
			## phase duration, or future opening tick.
			"targetable": encounter_director.is_targetable(enemy) and _is_enemy_actor_active(enemy),
		}
		if include_classification:
			var classification_tags: Array[String] = []
			if enemy.is_boss:
				classification_tags.append("boss")
			if enemy.entity_id == elite_entity_id:
				classification_tags.append("elite")
			if enemy.entity_id == player["marked_entity_id"]:
				classification_tags.append("marked")
			entry["classification_tags"] = classification_tags
		visible.append(entry)
	return {
		"snapshot_version": ProxyDecisionScript.SNAPSHOT_VERSION,
		"tick": sim_tick,
		"actor_id": "ranger",
		"player_position": player_position,
		"facing": player["player_facing"],
		"action_state": _player_authority_action_state(),
		"attack_ready_tick": sim_tick + player["attack_cooldown_ticks"],
		"targeting_distance": locked_targeting_distance,
		"visible_enemies": visible,
		"walkable_geometry": public_geometry,
	}


func _player_authority_action_state() -> String:
	var player := player_combat_state.snapshot(sim_tick)
	if player["dodge_remaining_ticks"] > 0:
		return "dodge"
	if player["dash_remaining_ticks"] > 0:
		return "dash"
	return String(player["action_phase"])


func _move_command(direction: Vector2, speed_scale: float) -> Dictionary:
	var milli := _direction_to_milli(direction)
	var result := CombatCommandProtocolScript.move(sim_tick, "ranger", command_sequence, milli.x, milli.y, clampi(roundi(speed_scale * 1000.0), 1, 1000))
	command_sequence += 1
	return result


func _dodge_command(direction: Vector2) -> Dictionary:
	var milli := _direction_to_milli(direction)
	var result := CombatCommandProtocolScript.dodge(sim_tick, "ranger", command_sequence, milli.x, milli.y)
	command_sequence += 1
	return result


func _cast_command(ability_id: String, target_entity_id: int, direction: Vector2 = Vector2.ZERO) -> Dictionary:
	var result: Dictionary
	if ability_id in ["dash", "piercing_arrow"]:
		var direction_milli := _direction_to_milli(direction)
		result = CombatCommandProtocolScript.cast(sim_tick, "ranger", command_sequence, ability_id, target_entity_id, direction_milli.x, direction_milli.y)
	else:
		result = CombatCommandProtocolScript.cast(sim_tick, "ranger", command_sequence, ability_id, target_entity_id)
	command_sequence += 1
	return result


func _loot_pickup_command(loot_entity_id: String) -> Dictionary:
	var result := CombatLootPickupProtocolScript.make_request(sim_tick, "ranger", command_sequence, loot_entity_id)
	command_sequence += 1
	return result


func _direction_to_milli(direction: Vector2) -> Vector2i:
	var player := player_combat_state.snapshot(sim_tick)
	var normalized: Vector2 = direction.normalized() if direction != Vector2.ZERO else (player["player_facing"] as Vector2).normalized()
	if normalized == Vector2.ZERO:
		normalized = Vector2.RIGHT
	return Vector2i(roundi(normalized.x * 1000.0), roundi(normalized.y * 1000.0))


func _process_player_action_events(events: Array, action_player: Dictionary) -> void:
	for event: Dictionary in events:
		var action_id := int(event.get("action_instance_id", 0))
		match String(event.get("type", "")):
			"buffered_started", "action_started":
				presentation.feedback.bind_action_request(action_id, int(event.get("request_id", 0)))
			"action_impact":
				_resolve_piercing_arrow(event, action_player)
			"action_ended", "action_interrupted":
				presentation.feedback.forget_action(action_id)


func _combat_context(player: Dictionary = {}) -> void:
	if player.is_empty():
		player = player_combat_state.snapshot(sim_tick)
	_ensure_combat_system()
	combat_system.set_context(
		sim_tick,
		player["player_position"],
		player["player_facing"],
		locked_payload,
		locked_targeting_distance,
		_current_projectile_speed(),
		player["marked_entity_id"],
		player["talent_capabilities"],
		combat_event_stream,
		manual_aim_resolver,
		enemies
	)
	combat_system.attack_origins = (player.get("attack_origins", {}) as Dictionary).duplicate(true)


func _combat_report(previous_report: String, previous_event_id: int) -> void:
	var report := String(combat_system.battle_report)
	if report.is_empty():
		return
	var fresh := report != previous_report
	for event: Dictionary in combat_event_stream.events_after(previous_event_id):
		if String(event.get("type", "")) == "projectile_spawned" or (String(event.get("type", "")) == "attack_resolved" and String(event.get("source_id", "")) == "ranger/piercing_arrow"):
			fresh = true
	if fresh:
		battle_report = report


func _resolve_piercing_arrow(action_event: Dictionary, action_player: Dictionary) -> void:
	_combat_context(action_player)
	var previous_report := String(combat_system.battle_report)
	var previous_event_id: int = combat_event_stream.latest_event_id()
	combat_system.resolve_piercing_arrow(action_event)
	_combat_report(previous_report, previous_event_id)

func _current_projectile_speed() -> float:
	var speed := 0.0
	if not locked_build.is_empty():
		speed = float((locked_build.get("final_parameters", {}) as Dictionary).get("v", 0.0))
	elif content_registry != null:
		speed = float(content_registry.preset_equipped_parameters.get("speed", 0.0))
	if not is_finite(speed) or speed <= 0.0:
		return 1.0
	return speed


func _advance_piercing_projectiles_tick() -> void:
	_combat_context()
	var previous_report := String(combat_system.battle_report)
	var previous_event_id: int = combat_event_stream.latest_event_id()
	# Every production ranger arrow flies through the mounted kernel. Normal
	# targets use PathQuery/SimHit; Boss targets use BossAttackQuery and the
	# multipart BossHitBuffer. Both paths resolve in the fixed
	# CONTINUOUS_QUERIES/DAMAGE_STATUS phases; neither may settle here.
	if room_spatial_port != null and room_combat_port != null and _kernel_arrow_flight.is_configured():
		var ranger_handle = actor_registry.actor_handle("ranger") if actor_registry != null else null
		_kernel_arrow_flight.submit_tick(
			combat_system.projectiles,
			ranger_handle,
			sim_tick,
			combat_system.room_port
		)
	if room_spatial_port != null and room_combat_port != null and _kernel_boss_flight.is_configured() and _boss_domain_room_is_current():
		var ranger_handle = actor_registry.actor_handle("ranger") if actor_registry != null else null
		_kernel_boss_flight.submit_tick(
			combat_system.projectiles,
			ranger_handle,
			sim_tick,
			combat_system.room_port
		)
	_combat_report(previous_report, previous_event_id)

func _resolve_piercing_arrow_contact(projectile: CombatArrowProjectile, target: CombatEnemyState, contact_point: Vector2) -> void:
	_combat_context()
	var previous_report := String(combat_system.battle_report)
	var previous_event_id: int = combat_event_stream.latest_event_id()
	combat_system.resolve_projectile_contact(projectile, target, contact_point)
	_combat_report(previous_report, previous_event_id)

func _resolve_piercing_arrow_miss(projectile: CombatArrowProjectile) -> void:
	_combat_context()
	var previous_report := String(combat_system.battle_report)
	var previous_event_id: int = combat_event_stream.latest_event_id()
	combat_system.resolve_projectile_miss(projectile)
	_combat_report(previous_report, previous_event_id)

func _piercing_arrow_swept_contact(start: Vector2, finish: Vector2, target: CombatEnemyState) -> Variant:
	_combat_context()
	return combat_system.swept_contact(start, finish, target)


func _remove_combat_target(target: CombatEnemyState) -> void:
	enemies.erase(target)
	if target == null or target.health > 0.0:
		return
	var actor_id := "enemy/%d" % target.entity_id
	if actor_registry != null and actor_registry.has_actor(actor_id):
		var unregistered: Dictionary = actor_registry.unregister_actor(actor_id)
		if not bool(unregistered.get("ok", false)):
			push_error("enemy_actor_unregister_failed:%d:%s" % [target.entity_id, String(unregistered.get("error", "unknown"))])
	_spawn_room_loot_for_source("enemy_death", target.entity_id, target.position)


func _cancel_buffered_target(entity_id: int) -> int:
	return player_combat_rules.cancel_buffered_target(entity_id)


func _erase_attack_request(request_id: int) -> void:
	if request_id > 0:
		presentation.feedback.forget_request(request_id)


func _encounter_context() -> void:
	if encounter_director == null:
		return
	_sync_encounter_active_state()
	encounter_director.set_context(
		sim_tick,
		player_position,
		_arena_rect(),
		combat_event_stream,
		layout_id,
		objective_id
	)


func _sync_encounter_active_state() -> void:
	if encounter_director == null or room_encounter_port == null or room_encounter_port.encounter == null:
		return
	if actor_registry == null or not actor_registry.has_method("is_actor_active"):
		return
	var active_ids: Array[int] = []
	for enemy: CombatEnemyState in encounter_director.enemies:
		var actor_id := "enemy/%d" % enemy.entity_id
		if actor_registry.has_actor(actor_id) and actor_registry.is_actor_active(actor_id):
			active_ids.append(enemy.entity_id)
	encounter_director.set_active_entity_ids(active_ids)


func _encounter_report(previous_report: String) -> void:
	var report := String(encounter_director.battle_report)
	if not report.is_empty() and report != previous_report:
		battle_report = report


func _update_enemies_tick() -> void:
	_encounter_context()
	var previous_report := String(encounter_director.battle_report)
	encounter_director.update_tick()
	_encounter_report(previous_report)


func _enemy_tactics_snapshot() -> Dictionary:
	_encounter_context()
	return encounter_director.enemy_tactics_snapshot()


func _enemy_tactics_hazards() -> Array[Dictionary]:
	if _hazard_domain != null and _hazard_domain.is_configured():
		return _hazard_domain.active_geometry()
	_encounter_context()
	return encounter_director.enemy_tactics_hazards()


func _maybe_summon_reinforcements(elite: CombatEnemyState) -> void:
	_encounter_context()
	var previous_report := String(encounter_director.battle_report)
	encounter_director._maybe_summon_reinforcements(elite)
	_encounter_report(previous_report)


func _update_room_rules_tick() -> void:
	# CombatSimulation submits the kernel tick through SimulationWorld directly,
	# bypassing SceneRuntime.step_tick(). Drain pending kernel encounter spawn
	# requests here - after this tick's snapshot was published, before the
	# reconciliation binding adopts legacy actors - so structural spawn acks
	# land in the between-tick window exactly once.
	if scene_runtime != null and scene_runtime.is_ready():
		scene_runtime.materialize_encounter_spawns()
	# Consume the kernel's typed combat output for the queries submitted last
	# tick: PathQuery results, the HitBuffer-derived batch RoomCombatPort
	# resolved through DamageResolution, and DeathSettlement receipts. Damage
	# and deaths commit here, before buffered casts start and before enemies,
	# hazards or the battle-end check observe the room.
	_consume_kernel_room_combat()
	_encounter_context()
	encounter_director.update_room_rules_tick()


func _update_hazards_tick() -> void:
	_refresh_hazard_states_tick()
	_resolve_hazard_hits_tick()


func _refresh_hazard_states_tick() -> void:
	if _hazard_domain != null and _hazard_domain.is_configured():
		var refreshed: Dictionary = _hazard_domain.refresh(sim_tick)
		if not bool(refreshed.get("ok", false)):
			battle_report = "hazard_refresh_failed:%s" % String(refreshed.get("error", "unknown"))
		encounter_director.hazard_states = _hazard_domain.snapshots()
		return
	_encounter_context()
	encounter_director.refresh_hazard_states_tick()


func _resolve_hazard_hits_tick() -> void:
	if _hazard_domain != null and _hazard_domain.is_configured():
		var resolved: Dictionary = _hazard_domain.resolve(sim_tick, player_position)
		if not bool(resolved.get("ok", false)):
			battle_report = "hazard_resolve_failed:%s" % String(resolved.get("error", "unknown"))
		else:
			for contact: Dictionary in resolved.get("contacts", []):
				combat_event_stream.emit(sim_tick, "attack_resolved", {
					"action_instance_id": 0,
					"source_id": String(contact.get("source_id", "")),
					"target_id": "ranger",
					"outcome": "queued",
					"contact_point": contact.get("contact_point", player_position),
				})
		# Player contacts are consumed after staging and after the kernel has
		# published this tick, preserving the existing fixed-tick boundary.
		if room_combat_port != null:
			var receipts: Array[Dictionary] = room_combat_port.commit_player_contacts(sim_tick)
			for receipt: Dictionary in receipts:
				if String(receipt.get("contact_kind", "")) != "hostile_attack":
					continue
				combat_event_stream.emit(sim_tick, "attack_resolved", {
					"action_instance_id": int(String(receipt.get("attack_instance_id", "0"))),
					"source_id": String(receipt.get("source_id", "")),
					"target_id": "ranger",
					"outcome": "damage" if bool(receipt.get("accepted", false)) else "avoided",
					"contact_point": player_position,
				})
		return
	_encounter_context()
	var previous_report := String(encounter_director.battle_report)
	encounter_director.resolve_hazard_hits_tick()
	if room_combat_port != null:
		var receipts: Array[Dictionary] = room_combat_port.commit_player_contacts(sim_tick)
		for receipt: Dictionary in receipts:
			if String(receipt.get("contact_kind", "")) != "hostile_attack":
				continue
			combat_event_stream.emit(sim_tick, "attack_resolved", {
				"action_instance_id": int(String(receipt.get("attack_instance_id", "0"))),
				"source_id": String(receipt.get("source_id", "")),
				"target_id": "ranger",
				"outcome": "damage" if bool(receipt.get("accepted", false)) else "avoided",
				"contact_point": player_position,
			})
	_encounter_report(previous_report)


func _queue_kernel_hazard_hit(tick: int, amount: float, source_id: String, source_position: Vector2) -> Dictionary:
	return _queue_kernel_player_hit(tick, amount, source_id, source_position)


## Stages one room-owned player contact for the next kernel tick. Hazard
## amounts stay integer-valued; enemy impacts use milli units so the existing
## 1.2/1.8 damage values cross SimHit without rounding.
func _queue_kernel_player_hit(tick: int, amount: float, source_id: String, source_position: Vector2) -> Dictionary:
	if room_spatial_port == null or actor_registry == null:
		return {"ok": false, "error": "kernel_player_contact_port_unavailable"}
	if tick != sim_tick or not is_finite(amount) or amount <= 0.0 or not source_position.is_finite():
		return {"ok": false, "error": "invalid_kernel_player_contact_context"}
	var contact_kind: StringName
	var encoded_amount: int
	var attack_instance_id := ""
	if source_id.begins_with("hazard/"):
		contact_kind = &"hazard"
		encoded_amount = maxi(1, roundi(amount))
		attack_instance_id = "hazard/%s/%d" % [source_id, tick]
	elif source_id.begins_with("enemy/") or source_id.begins_with("boss/"):
		contact_kind = &"hostile_attack"
		encoded_amount = maxi(1, roundi(amount * 1000.0))
		var action_instance_id := _hostile_action_instance_id(source_id)
		attack_instance_id = str(action_instance_id) if action_instance_id > 0 else "hostile/%s/%d" % [source_id, tick]
	else:
		return {"ok": false, "error": "invalid_kernel_player_contact_source"}
	var target: Variant = actor_registry.actor_handle("ranger")
	if target == null:
		return {"ok": false, "error": "player_actor_unavailable"}
	return room_spatial_port.queue_player_hit(
		target,
		encoded_amount,
		source_id,
		source_position,
		attack_instance_id,
		contact_kind
	)


func _hostile_action_instance_id(source_id: String) -> int:
	if encounter_director == null:
		return 0
	if source_id.begins_with("enemy/"):
		var parts := source_id.split("/")
		if parts.size() >= 2:
			var enemy: CombatEnemyState = encounter_director._enemy_by_entity_id(int(parts[1]))
			return int(enemy.action_instance_id) if enemy != null else 0
	if source_id.begins_with("boss/") and encounter_director.boss != null:
		return int(encounter_director.boss.action_instance_id)
	return 0


func _new_hazard_state(id: String, center: Vector2) -> Dictionary:
	_encounter_context()
	return encounter_director.new_hazard_state(id, center)


func _hazard_contains(state: Dictionary, point: Vector2) -> bool:
	_encounter_context()
	return encounter_director.hazard_contains(state, point)


func _enemy_by_entity_id(id: int) -> CombatEnemyState:
	_encounter_context()
	return encounter_director._enemy_by_entity_id(id)


func _allocate_entity_id() -> int:
	_encounter_context()
	return encounter_director._allocate_entity_id()


func _update_enemy_tick(enemy: CombatEnemyState, intent: Dictionary = {}) -> void:
	_encounter_context()
	var previous_report := String(encounter_director.battle_report)
	encounter_director._update_enemy_tick(enemy, intent)
	_encounter_report(previous_report)


func _advance_action_state(enemy: CombatEnemyState, active_ticks: int, recovery_ticks: int) -> bool:
	_encounter_context()
	var previous_report := String(encounter_director.battle_report)
	var result: bool = bool(encounter_director._advance_action_state(enemy, active_ticks, recovery_ticks))
	_encounter_report(previous_report)
	return result


func _finish_enemy_recovery_if_due(enemy: CombatEnemyState) -> bool:
	_encounter_context()
	var previous_report := String(encounter_director.battle_report)
	var result: bool = bool(encounter_director._finish_enemy_recovery_if_due(enemy))
	_encounter_report(previous_report)
	return result


func _begin_action(enemy: CombatEnemyState, action_id: String, windup_ticks: int) -> void:
	_encounter_context()
	encounter_director._begin_action(enemy, action_id, windup_ticks)


func _emit_enemy_action_accepted(enemy: CombatEnemyState) -> void:
	_encounter_context()
	encounter_director._emit_enemy_action_accepted(enemy)


func _enemy_breath_ticks(kind_id: String) -> int:
	_encounter_context()
	return encounter_director._enemy_breath_ticks(kind_id)


func _intent_for_enemy(enemy: CombatEnemyState) -> Dictionary:
	_encounter_context()
	return encounter_director._intent_for_enemy(enemy)


func _update_melee_tick(enemy: CombatEnemyState, intent: Dictionary = {}) -> void:
	_encounter_context()
	var previous_report := String(encounter_director.battle_report)
	encounter_director._update_melee_tick(enemy, intent)
	_encounter_report(previous_report)


func _start_melee_action(enemy: CombatEnemyState, direction: Vector2 = Vector2.ZERO) -> void:
	_encounter_context()
	encounter_director._start_melee_action(enemy, direction)


func _start_charger_action(enemy: CombatEnemyState, direction: Vector2, action_distance: float) -> bool:
	_encounter_context()
	var previous_report := String(encounter_director.battle_report)
	var result: bool = bool(encounter_director._start_charger_action(enemy, direction, action_distance))
	_encounter_report(previous_report)
	return result


func _set_enemy_collision_class(enemy: CombatEnemyState, collision_class: StringName) -> bool:
	if enemy == null or actor_registry == null or not actor_registry.has_method("set_collision_class"):
		return false
	var result: Dictionary = actor_registry.set_collision_class("enemy/%d" % enemy.entity_id, collision_class)
	if not bool(result.get("ok", false)):
		push_error("enemy_collision_class_update_failed:%d:%s" % [enemy.entity_id, String(result.get("error", "unknown"))])
		return false
	return true


func _update_charger_tick(enemy: CombatEnemyState, intent: Dictionary = {}) -> void:
	_encounter_context()
	var previous_report := String(encounter_director.battle_report)
	encounter_director._update_charger_tick(enemy, intent)
	_encounter_report(previous_report)


func _start_fan_action(enemy: CombatEnemyState, direction: Vector2 = Vector2.ZERO) -> void:
	_encounter_context()
	encounter_director._start_fan_action(enemy, direction)


func _update_fan_tick(enemy: CombatEnemyState, intent: Dictionary = {}) -> void:
	_encounter_context()
	var previous_report := String(encounter_director.battle_report)
	encounter_director._update_fan_tick(enemy, intent)
	_encounter_report(previous_report)


func _commit_normal_enemy_intent(enemy: CombatEnemyState, intent: Dictionary) -> void:
	_encounter_context()
	var previous_report := String(encounter_director.battle_report)
	encounter_director._commit_normal_enemy_intent(enemy, intent)
	_encounter_report(previous_report)


func _resolve_hostile_attack(enemy: CombatEnemyState, amount: float, shape_hit: bool) -> void:
	_encounter_context()
	var previous_report := String(encounter_director.battle_report)
	encounter_director._resolve_hostile_attack(enemy, amount, shape_hit)
	_encounter_report(previous_report)


func _update_boss_tick(enemy: CombatEnemyState, intent: Dictionary = {}) -> void:
	_encounter_context()
	var previous_report := String(encounter_director.battle_report)
	encounter_director._update_boss_tick(enemy, intent)
	_encounter_report(previous_report)


func _start_boss_action(enemy: CombatEnemyState, action: String, planned_direction: Vector2 = Vector2.ZERO) -> void:
	_encounter_context()
	encounter_director._start_boss_action(enemy, action, planned_direction)


func _update_boss_hands(enemy: CombatEnemyState) -> void:
	_encounter_context()
	encounter_director._update_boss_hands(enemy)


func _boss_shape_contains(shape: Dictionary, point: Vector2) -> bool:
	return CombatQueryScript.shape_contains(shape, point)


func _quantize_position(value: Vector2) -> Vector2:
	# Authority stores a 1/1000-pixel grid. Rendering may interpolate later, but
	# identical whole-tick commands always land on identical coordinates.
	return Vector2(snappedf(value.x, 0.001), snappedf(value.y, 0.001))


func _framework_room_error() -> String:
	if not embedded_session or framework_room.is_empty():
		return ""
	_ensure_room_catalog()
	return EncounterDirectorScript.validate_room(framework_room, room_catalog)


func _layout_spawn_offsets(id: String, count: int) -> Array[Vector2]:
	_ensure_room_catalog()
	var spawn_room_id := String(encounter_director.room_id) if encounter_director != null else room_id
	if room_catalog == null:
		return []
	return room_catalog.spawn_offsets({"layout_id": id, "room_id": spawn_room_id}, count)



func _check_battle_end() -> void:
	var embedded_state_before := _embedded_authority_state_snapshot()
	# Pickup is a committed post-movement phase. Requests are queued by the
	# public input boundary and can only mutate the room ledger here.
	_process_room_loot_pickups_tick()
	if _mounted_encounter_terminal_active():
		var terminal_result := _observe_mounted_encounter_terminal()
		if not bool(terminal_result.get("ok", false)):
			push_error("room_terminal_observation_failed:%s" % String(terminal_result.get("error", "unknown")))
			return
		var terminal_phase := String(terminal_result.get("phase", ""))
		if terminal_phase not in ["victory", "defeat"] or _terminal_projection_applied:
			return
		_terminal_projection_applied = true
		var victory := terminal_phase == "victory"
		battle_report = "VICTORY — Room encounter cleared." if victory else "DEFEAT — The ranger fell. Refit at base."
		var projected := room_rules.project_terminal(victory, timed_bonus_available, elapsed, shots, defeated)
		if not bool(projected.get("ok", false)):
			push_error("room_terminal_reward_projection_failed:%s" % String(projected.get("error", "unknown")))
			return
		if victory:
			_spawn_room_loot_for_source("wave_clear", 0, player_position)
		else:
			_settle_room_loot("defeat")
		_handle_terminal_automation(victory, embedded_state_before)
		return
	var observed: Dictionary = room_rules.observe(player_combat_state.snapshot(sim_tick), {
		"has_boss": boss != null, "boss_health": boss.health if boss != null else 0.0,
		"enemy_count": enemies.size(), "elite_entity_id": elite_entity_id,
		"elite_alive": _enemy_by_entity_id(elite_entity_id) != null,
		"elite_rule_ids": elite_rule_ids, "timed_bonus_available": timed_bonus_available,
		"elapsed": elapsed, "shots": shots, "defeated": defeated,
	})
	if not bool(observed.changed):
		return
	battle_report = String(observed.state.report)
	if battle_victory:
		_spawn_room_loot_for_source("wave_clear", 0, player_position)
	if not battle_victory:
		_settle_room_loot("defeat")
	if battle_victory:
		if automation_smoke:
			var smoke_valid := false
			if embedded_session:
				smoke_valid = (
					not framework_room.is_empty()
					and battle_victory
					and (selected_mode != "Auto" or proxy_prediction == "stable")
					and _embedded_authority_state_snapshot() == embedded_state_before
				)
			else:
				smoke_valid = contract_wins == automation_expected_contract_wins and destiny_forge.get_dice(DestinyForgeScript.TRACK_ADD) == 7 and not last_drop_id.is_empty() and proxy_prediction == "stable"
			if not smoke_valid:
				_fail_automation_smoke("integrated room/proxy/reward state is invalid")
				return
			if embedded_session:
				return
			var state_hash := _semantic_state_hash("victory")
			if not _write_state_hash(state_hash):
				Engine.time_scale = 1.0
				get_tree().quit(1)
				return
			print("AUTO_SMOKE_PASS elapsed=%.2f ticks=%d casts=%d damage=%s state_hash=%s" % [elapsed, sim_tick, shots, boss_damage.to_short_string(5), state_hash])
			Engine.time_scale = 1.0
			get_tree().quit(0)
	elif automation_smoke:
		if embedded_session:
			automation_smoke_failure = "defeat elapsed=%.2f casts=%d" % [elapsed, shots]
			return
		printerr("AUTO_SMOKE_FAIL elapsed=%.2f casts=%d" % [elapsed, shots])
		Engine.time_scale = 1.0
		get_tree().quit(1)


func _mounted_encounter_terminal_active() -> bool:
	return room_encounter_port != null and room_encounter_port.encounter != null and room_encounter_port.encounter.has_method("observe_terminal")


func _observe_mounted_encounter_terminal() -> Dictionary:
	var observation := RoomTerminalObservationScript.new()
	observation.tick = sim_tick
	observation.room_instance_id = String(simulation_world.room_instance_id)
	observation.world_revision = int(simulation_world.world_revision)
	var player := player_combat_state.snapshot(sim_tick)
	observation.player_alive = float(player.get("player_health", 0.0)) > 0.0
	var encounter_state: Dictionary = room_encounter_port.encounter.snapshot()
	observation.current_wave_index = int(encounter_state.get("current_wave_index", -1))
	var waves: Array = encounter_state.get("waves", [])
	var wave_id := ""
	if observation.current_wave_index >= 0 and observation.current_wave_index < waves.size() and waves[observation.current_wave_index] is Dictionary:
		wave_id = String((waves[observation.current_wave_index] as Dictionary).get("wave_id", ""))
	for raw_record: Variant in encounter_state.get("spawn_records", []):
		if not raw_record is Dictionary or String((raw_record as Dictionary).get("wave_id", "")) != wave_id:
			continue
		observation.requested_member_count += 1
		var state := String((raw_record as Dictionary).get("state", ""))
		if state == "alive":
			observation.alive_member_count += 1
		if state in ["requested", "alive"]:
			observation.unresolved_member_count += 1
	var objective := String(framework_room.get("objective_id", objective_id))
	if objective == "hunt_elite" and elite_entity_id > 0:
		var elite_alive := _enemy_by_entity_id(elite_entity_id) != null
		var requires_full_clear := "summon_reinforcements" in elite_rule_ids
		observation.objective_satisfied = not elite_alive and (not requires_full_clear or enemies.is_empty())
	var result: RoomTerminalResult = room_encounter_port.observe_terminal(observation)
	return result.snapshot()


func _handle_terminal_automation(victory: bool, embedded_state_before: Dictionary) -> void:
	if not automation_smoke:
		return
	if embedded_session:
		if not victory:
			automation_smoke_failure = "defeat elapsed=%.2f casts=%d" % [elapsed, shots]
			return
		var smoke_valid := not framework_room.is_empty() and battle_victory and (selected_mode != "Auto" or proxy_prediction == "stable") and _embedded_authority_state_snapshot() == embedded_state_before
		if not smoke_valid:
			_fail_automation_smoke("integrated room/proxy/reward state is invalid")
		return
	if not victory:
		printerr("AUTO_SMOKE_FAIL elapsed=%.2f casts=%d" % [elapsed, shots])
		Engine.time_scale = 1.0
		get_tree().quit(1)
		return
	var state_hash := _semantic_state_hash("victory")
	if not _write_state_hash(state_hash):
		Engine.time_scale = 1.0
		get_tree().quit(1)
		return
	print("AUTO_SMOKE_PASS elapsed=%.2f ticks=%d casts=%d damage=%s state_hash=%s" % [elapsed, sim_tick, shots, boss_damage.to_short_string(5), state_hash])
	Engine.time_scale = 1.0
	get_tree().quit(0)


func _fail_automation_smoke(reason: String) -> void:
	automation_smoke_failure = reason
	room_rules.fail(reason)
	battle_report = String(room_rules.snapshot().report)
	if embedded_session:
		return
	printerr("AUTO_SMOKE_FAIL %s" % reason)
	Engine.time_scale = 1.0
	get_tree().quit(1)


func _commit_legacy_room_reward(commit: Dictionary) -> void:
	# The room domain decides the reward and commits once. This sink projects its
	# prepared values into the existing diagnostic profile/persistence ports.
	contract_wins = int(commit.contract_wins)
	last_drop_id = String(commit.last_drop_id)
	last_drop = String(commit.last_drop)
	last_loot_rng_state = (commit.last_loot_rng_state as Dictionary).duplicate(true)
	destiny_forge.grant_dice(commit.track, int(commit.dice_awarded))
	_save_progress(String(commit.save_reason))


func _embedded_authority_state_snapshot() -> Dictionary:
	return {
		"contract_wins": contract_wins,
		"forge": destiny_forge.state().duplicate(true),
		"last_drop": last_drop,
		"last_drop_id": last_drop_id,
		"last_loot_rng_state": last_loot_rng_state.duplicate(true),
	}


func _semantic_state_hash(result: String) -> String:
	return CombatStateSnapshotBuilderScript.hash_runtime(self, result)


func _write_state_hash(state_hash: String) -> bool:
	if state_hash.is_empty():
		printerr("STATE_HASH_FAIL: could not calculate hash")
		return false
	if state_hash_output_path.is_empty():
		return true
	var output_path := state_hash_output_path
	if not output_path.is_absolute_path() and not output_path.begins_with("user://") and not output_path.begins_with("res://"):
		output_path = ProjectSettings.globalize_path("res://" + output_path)
	var output_directory := output_path.get_base_dir()
	if not output_directory.is_empty():
		var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_directory))
		if directory_error != OK:
			printerr("STATE_HASH_FAIL: %s" % error_string(directory_error))
			return false
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		printerr("STATE_HASH_FAIL: %s" % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(state_hash + "\n")
	file.close()
	return true


func _current_model() -> Dictionary:
	var player := player_combat_state.snapshot(sim_tick)
	if not locked_build.is_empty():
		var event_value: Dictionary = locked_build.get("total_events", {})
		var total_events := BigValue.from_components(
			int(event_value.get("layer", 0)),
			float(event_value.get("magnitude", 0.0))
		)
		if total_events != null:
			var generations := int(locked_build.generation_count)
			return {
				"p": float(locked_build.final_parameters.p),
				"R": float(locked_build.R),
				"g": generations,
				"generation_time": float(locked_build.generation_time),
				"state": String(locked_build.growth_classification),
				"total_events": total_events,
				"total_events_float": float(locked_build.total_events_float),
				"growth_snapshot_details": bool((player.get("talent_capabilities", {}) as Dictionary).get("growth_snapshot_details", false)),
			}
	var equipped: Dictionary = content_registry.preset_equipped_parameters
	return PiercingArrowModel.evaluate(
		locked_p,
		float(equipped.shared_lifetime),
		float(equipped.distance),
		float(equipped.speed),
		float(equipped.minimum_turn_time),
		true,
		true
	)


func _manual_aim_candidate(enemy: CombatEnemyState) -> Dictionary:
	return {
		"entity_id": enemy.entity_id,
		"kind_id": enemy.kind_id,
		"position": enemy.position,
		"health": enemy.health,
		"is_boss": enemy.is_boss,
	}


func _preferred_skill_one_target() -> CombatEnemyState:
	var player := player_combat_state.snapshot(sim_tick)
	var marked := _enemy_by_entity_id(player["marked_entity_id"])
	if marked != null and _is_enemy_actor_active(marked) and marked.health > 0.0 and sim_tick < player["hunter_mark_expires_tick"] and player_position.distance_to(marked.position) <= locked_targeting_distance:
		return marked
	if player["hunter_mark_candidate_entity_id"] > 0 and sim_tick <= player["hunter_mark_candidate_expires_tick"]:
		var candidate := _enemy_by_entity_id(player["hunter_mark_candidate_entity_id"])
		if candidate != null and _is_enemy_actor_active(candidate) and candidate.health > 0.0 and player_position.distance_to(candidate.position) <= locked_targeting_distance:
			return candidate
	return _nearest_enemy()


func _nearest_enemy(maximum_distance: float = INF) -> CombatEnemyState:
	var nearest: CombatEnemyState
	var best_distance: float = maximum_distance * maximum_distance
	for enemy: CombatEnemyState in enemies:
		if enemy.health <= 0.0 or not _is_enemy_actor_active(enemy):
			continue
		var distance: float = player_position.distance_squared_to(enemy.position)
		if distance < best_distance or (is_equal_approx(distance, best_distance) and (nearest == null or enemy.entity_id < nearest.entity_id)):
			best_distance = distance
			nearest = enemy
	return nearest


func _is_enemy_actor_active(enemy: CombatEnemyState) -> bool:
	if enemy == null:
		return false
	if actor_registry != null and actor_registry.has_method("is_actor_active"):
		return bool(actor_registry.is_actor_active("enemy/%d" % enemy.entity_id))
	return true


func _is_skill_equipped(slot_index: int, expected_id: String) -> bool:
	var skills: Array = player_combat_state.snapshot(sim_tick).get("equipped_skills", [])
	return slot_index >= 0 and slot_index < skills.size() and String(skills[slot_index]) == expected_id


func _arena_rect() -> Rect2:
	if scene_runtime != null:
		var authored: Variant = scene_runtime.get("authored_arena_rect")
		return authored as Rect2 if authored is Rect2 else Rect2()
	return Rect2(Vector2(ARENA_MARGIN, 190.0), Vector2(
		AUTHORITY_VIEWPORT_SIZE.x - ARENA_MARGIN * 2.0,
		AUTHORITY_VIEWPORT_SIZE.y - 190.0 - ARENA_MARGIN))


func _walkable_geometry(padding: float) -> Dictionary:
	var geometry: Dictionary = {}
	if scene_runtime != null:
		var native_boundary: Variant = scene_runtime.get("movement_boundary")
		if native_boundary is Dictionary:
			geometry = ArenaGeometryScript.from_native_boundary(native_boundary, _arena_rect(), padding)
	else:
		geometry = ArenaGeometryScript.from_layout(layout_id, _arena_rect(), padding)
	var normalized: Dictionary = ArenaGeometryScript.normalize(geometry)
	return (normalized.get("value", {}) as Dictionary).duplicate(true) if bool(normalized.get("ok", false)) else {}


func _presentation_geometry() -> Dictionary:
	var boundary: Dictionary = {}
	if scene_runtime != null:
		var native_boundary: Variant = scene_runtime.get("movement_boundary")
		if native_boundary is Dictionary:
			boundary = (native_boundary as Dictionary).duplicate(true)
	else:
		boundary = ArenaGeometryScript.movement_boundary(layout_id, _arena_rect())
	if not boundary.is_empty():
		var native_geometry := ArenaGeometryScript.from_native_boundary(boundary, _arena_rect(), 0.0)
		if not native_geometry.is_empty():
			return native_geometry
	return ArenaGeometryScript.from_layout(layout_id, _arena_rect(), 0.0)


func _collision_geometry(radius: float) -> Dictionary:
	if not is_finite(radius) or radius < 0.0:
		return {}
	var boundary: Dictionary = {}
	if scene_runtime != null:
		var native_boundary: Variant = scene_runtime.get("movement_boundary")
		if native_boundary is Dictionary:
			boundary = (native_boundary as Dictionary).duplicate(true)
	else:
		boundary = ArenaGeometryScript.movement_boundary(layout_id, _arena_rect())
	return ArenaGeometryScript.from_native_boundary_for_footprint(boundary, _arena_rect(), radius)


## Bounding circles of the authored static blockers in the mounted room's
## movement channel. Standalone fixtures without a mounted registry have no
## authored blockers and steer on the boundary geometry alone.
func _static_blocker_bounds() -> Array[Dictionary]:
	if actor_registry == null:
		return []
	return actor_registry.static_blocker_bounds()


func _room_socket(binding: String) -> Variant:
	if scene_runtime == null:
		return null
	var sockets: Variant = scene_runtime.get("spawn_socket_bindings")
	if not sockets is Array:
		return null
	for socket: Dictionary in sockets:
		if String(socket.get("binding", "")) == binding:
			return socket.get("position")
	return null


func _clamp_to_arena(value: Vector2, padding: float) -> Vector2:
	var projected: Dictionary = ArenaGeometryScript.project(value, _walkable_geometry(padding))
	if not bool(projected.get("ok", false)) or not projected.get("position", null) is Vector2:
		var projection_error := "walkable_geometry_projection_failed: %s" % String(projected.get("error", "invalid_position"))
		push_error(projection_error)
		assert(false, projection_error)
		return value
	return projected.position


func _project_actor_spawn_position(value: Vector2, radius: float) -> Dictionary:
	## Initialization uses the same footprint-aware limits as ActorMotor. Once a
	## room is live, all further displacement is submitted through the registry.
	if not value.is_finite() or not is_finite(radius) or radius <= 0.0:
		return {"ok": false, "error": "invalid_spawn_footprint"}
	var geometry := _collision_geometry(radius)
	if geometry.is_empty():
		return {"ok": false, "error": "spawn_geometry_unavailable"}
	var projected: Dictionary = ArenaGeometryScript.project(value, geometry)
	if not bool(projected.get("ok", false)):
		return {"ok": false, "error": "spawn_projection_failed:%s" % String(projected.get("error", "invalid_geometry"))}
	var position := Vector2(projected["position"])
	if actor_registry != null:
		var static_clear: Variant = _project_static_clear(position, radius)
		if static_clear == null:
			return {"ok": false, "error": "spawn_static_projection_failed"}
		position = static_clear
	return {"ok": true, "position": position}


## Authored static blockers (ruins, gates, the tower) also own spawn clearance.
## Deterministic expanding-ring search around the boundary-projected point: the
## first clear candidate wins in a fixed ring/step order, so fixed-tick replays
## stay byte-stable. Returns null when no candidate inside the arena clears
## every static surface, keeping the fail-closed contract of the caller.
func _project_static_clear(position: Vector2, radius: float) -> Variant:
	if actor_registry.is_position_clear(position, radius):
		return position
	for ring: float in [16.0, 32.0, 48.0, 64.0, 96.0, 128.0, 160.0, 192.0, 224.0, 256.0]:
		for step: int in 16:
			var candidate := position + Vector2(ring, 0.0).rotated(TAU * float(step) / 16.0)
			if candidate.is_finite() and actor_registry.is_position_clear(candidate, radius):
				return candidate
	return null


func _handle_command_line() -> void:
	if command_line_arguments.has("--smoke"):
		if not startup_errors.is_empty() or destiny_forge.preview(DestinyForgeScript.TRACK_ADD, 0, 3).size() != 3:
			printerr("SCENE_SMOKE_FAIL systems=%s" % str(startup_errors))
			get_tree().quit(1)
			return
		print("SCENE_SMOKE_PASS systems=content,forge,proxy,save fixed_tick=%d" % SIM_TICKS_PER_SECOND)
		get_tree().create_timer(0.25).timeout.connect(func() -> void: get_tree().quit(0))
	if command_line_arguments.has("--auto-smoke"):
		automation_smoke = true
		selected_preset = "exponential"
		selected_mode = "Auto"
		start_room()
		if not in_arena:
			printerr("AUTO_SMOKE_FAIL deployment blocked")
			get_tree().quit(1)
			return
		Engine.time_scale = 20.0
	for argument: String in command_line_arguments:
		if argument.begins_with("--capture="):
			_capture_frame.call_deferred(argument.trim_prefix("--capture="))


func _capture_frame(path: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var error: Error = get_viewport().get_texture().get_image().save_png(path)
	if error != OK:
		printerr("CAPTURE_FAIL %s: %s" % [path, error_string(error)])
		get_tree().quit(1)
		return
	print("CAPTURE_PASS %s" % path)
	get_tree().quit(0)


func _resolved_build_is_valid(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var build: Dictionary = value
	if not bool(build.get("ok", false)) or String(build.get("build_fingerprint", "")).length() != 64:
		return false
	var parameters: Variant = build.get("final_parameters", {})
	if not parameters is Dictionary:
		return false
	for key in ["p", "T", "v", "d", "turn", "damage", "max_health"]:
		var parameter: Variant = (parameters as Dictionary).get(key, null)
		if typeof(parameter) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(parameter)):
			return false
	if not build.get("total_events", {}) is Dictionary:
		return false
	return true


func _ensure_command_source() -> void:
	if command_source != null:
		return
	command_source = CombatCommandSourceScript.new()
	command_source_port = MainCombatCommandSourcePortScript.new()
	var port_result: Dictionary = command_source_port.bind(self, input_adapter)
	if not bool(port_result.get("ok", false)):
		push_error("command_source_port_bind_failed:%s" % String(port_result.get("error", "unknown")))
		command_source = null
		command_source_port = null
		return
	input_adapter.configure(command_source, command_source_port, presentation.feedback, presentation.screen_to_gameplay, presentation.is_pointer_over_interface)


func _on_skill_requested(ability: String) -> void:
	input_adapter.request_skill(ability, gameplay_snapshot())


func _on_return_requested() -> void:
	if embedded_session:
		return_requested.emit()
	else:
		_show_base()


func _refresh_lab() -> void:
	if lab_view == null:
		return
	var active_slot := _next_empty_forge_slot()
	lab_view.select_build(selected_preset, selected_mode)
	lab_view.present_status({
		"startup_errors": startup_errors.duplicate(), "proxy_prediction": proxy_prediction,
		"active_slot": active_slot, "dice": destiny_forge.get_dice(DestinyForgeScript.TRACK_ADD),
		"affixes": destiny_forge.affixes.duplicate(true),
		"candidates": [] if active_slot < 0 else destiny_forge.preview(DestinyForgeScript.TRACK_ADD, active_slot, 3),
		"in_arena": in_arena, "contract_wins": contract_wins,
		"last_drop": last_drop, "last_save_message": last_save_message,
	})


## This boundary is actually consumed by the controller and input adapter.
## Snapshot capture detaches all mutable records before crossing into the view.
func gameplay_snapshot() -> Dictionary:
	var values := player_combat_state.snapshot(sim_tick)
	values.merge({
		"sim_tick": sim_tick,
		"in_arena": in_arena,
		"battle_over": battle_over,
		"battle_victory": battle_victory,
		"battle_report": battle_report,
		"enemies": enemies,
		"boss": boss,
		"boss_damage": boss_damage,
		"boss_maximum": boss_maximum,
		"shots": shots,
		"defeated": defeated,
		"elapsed": elapsed,
		"room_id": room_id,
		"layout_id": layout_id,
		"objective_id": objective_id,
		"embedded_session": embedded_session,
		"framework_room": framework_room,
		"room_loot": room_loot_snapshot,
		"room_entry_start_tick": room_entry_start_tick,
		"locked_build": locked_build,
		"locked_targeting_distance": locked_targeting_distance,
		"hazard_states": hazard_states,
		"elite_entity_id": elite_entity_id,
		"elite_rule_ids": elite_rule_ids,
		"elite_barrier_active": elite_barrier_active,
		"reinforcements_summoned": reinforcements_summoned,
		"timed_bonus_available": timed_bonus_available,
		"last_attack_outcome": last_attack_outcome,
		"last_loot_pickup_command_receipt": last_loot_pickup_command_receipt.duplicate(true),
		"proxy_prediction": proxy_prediction,
		"selected_mode": selected_mode,
		"arena_rect": _arena_rect(), "walkable_geometry": _walkable_geometry(14.0),
		"presentation_geometry": _presentation_geometry(),
		"projectiles": projectiles,
		"equipped_parameters": content_registry.preset_equipped_parameters if content_registry != null else {},
		"model": _current_model() if content_registry != null else {},
		"proxy_failure": _proxy_failure_snapshot(),
		"events": combat_event_stream.events_after(presentation.feedback.presentation_event_cursor) if combat_event_stream != null else [],
	}, true)
	return PresentationSnapshot.capture(values)


func refresh_presentation(delta: float = 0.0) -> void:
	var snapshot := gameplay_snapshot()
	if delta > 0.0:
		presentation.advance_time(snapshot, delta)
	presentation.commit(snapshot, input_adapter.view_state(snapshot), delta)


func ranger_animation_report() -> Dictionary:
	return presentation.animations.ranger_animation_report(gameplay_snapshot())


func enemy_animation_report() -> Dictionary:
	return presentation.animations.enemy_animation_report(gameplay_snapshot())


func combat_feedback_report() -> Dictionary:
	return presentation.feedback.report()


func defeat_hold_reason() -> String:
	return presentation.animations.defeat_hold_reason(gameplay_snapshot())


func defeat_route_ready() -> bool:
	return defeat_hold_reason().is_empty()


func defeat_skip_presentation(reason: String = "skipped") -> void:
	presentation.animations.defeat_skip_presentation(reason)


func defeat_presentation_report() -> Dictionary:
	return presentation.animations.defeat_presentation_report(gameplay_snapshot())


## Typed combat-system composition owned by Main.  The production ranged
## coordinator receives this object once and never receives a callback bag.
## Player-domain retention/sequence state and encounter admission remain room
## owned, while the coordinator only invokes these typed operations.
class MainCombatRoomPort extends "res://src/runtime/combat/combat_system_room_port.gd":

	var _owner: MainArena = null

	func bind(owner: MainArena) -> Dictionary:
		if owner == null or not is_instance_valid(owner):
			return {"ok": false, "error": "combat_room_owner_unavailable"}
		if owner.player_combat_rules == null or owner.encounter_director == null:
			return {"ok": false, "error": "combat_room_dependencies_unavailable"}
		_owner = owner
		return {"ok": true, "error": ""}

	func is_ready() -> bool:
		return _owner != null and is_instance_valid(_owner)

	func target_by_id(entity_id: int) -> CombatEnemyState:
		return _owner._enemy_by_entity_id(entity_id)

	func aim_candidate(target: CombatEnemyState) -> Dictionary:
		return _owner._manual_aim_candidate(target)

	func current_model() -> Dictionary:
		return _owner._current_model()

	func target_blocked(target: CombatEnemyState) -> Dictionary:
		if target == null or _owner.encounter_director == null:
			return {"ok": false, "error": "target_blocked_port_unavailable"}
		return {"ok": true, "error": "", "blocked": _owner.encounter_director.is_target_blocked(target)}

	func maybe_summon(target: CombatEnemyState) -> void:
		_owner._maybe_summon_reinforcements(target)

	func remove_target(target: CombatEnemyState) -> void:
		_owner._remove_combat_target(target)

	func cancel_buffered_target(entity_id: int) -> int:
		return _owner._cancel_buffered_target(entity_id)

	func update_mark() -> void:
		_owner._refresh_player_mark()

	func advance_sequence(skill_id: String) -> void:
		_owner.player_combat_rules.advance_three_skill_sequence(skill_id)

	func reset_sequence() -> void:
		_owner.player_combat_rules.reset_three_skill_sequence()

	func erase_attack_request(request_id: int) -> void:
		_owner._erase_attack_request(request_id)

	func consume_first_critical_bonus() -> int:
		return _owner.player_combat_rules.consume_first_critical_bonus()

	func retain_missed_arrow(aggregate: BigValue, ordinary: float) -> bool:
		_owner.player_combat_rules.retain_missed_arrow(aggregate, ordinary)
		return true

	func take_retained_arrow() -> Dictionary:
		return _owner.player_combat_rules.take_retained_arrow()

	func is_normal_kernel_projectile(projectile) -> bool:
		return _owner._is_normal_kernel_projectile(projectile)

	func is_boss_kernel_projectile(projectile) -> bool:
		return _owner._is_boss_kernel_projectile(projectile)

	func sync_kernel_target_record(projectile) -> void:
		_owner._sync_kernel_target_record(projectile)

	func sync_boss_kernel_target(projectile) -> Variant:
		return _owner._sync_boss_kernel_target(projectile)


class MainHitAdmissionPort extends "res://src/runtime/combat/room_hit_admission_port.gd":

	var _owner: MainArena = null

	func bind(owner: MainArena) -> Dictionary:
		if owner == null or not is_instance_valid(owner):
			return {"ok": false, "error": "hit_admission_owner_unavailable"}
		_owner = owner
		return {"ok": true, "error": ""}

	func admit(hit: Dictionary) -> Dictionary:
		if _owner == null or not is_instance_valid(_owner):
			return {"allowed": false, "reason": "hit_admission_owner_unavailable"}
		return _owner._admit_kernel_hit(hit)


class MainRewardPort extends "res://src/runtime/world/room_reward_port.gd":

	var _owner: MainArena = null

	func bind(owner: MainArena) -> Dictionary:
		if owner == null or not is_instance_valid(owner):
			return {"ok": false, "error": "reward_owner_unavailable"}
		_owner = owner
		return {"ok": true, "error": ""}

	func commit(reward: Dictionary) -> Dictionary:
		if _owner == null or not is_instance_valid(_owner):
			return {"ok": false, "error": "reward_owner_unavailable"}
		_owner._commit_legacy_room_reward(reward)
		return {"ok": true, "error": ""}


class MainMovementPolicyPort extends "res://src/runtime/world/room_movement_policy_port.gd":

	var _owner: MainArena = null

	func bind(owner: MainArena) -> Dictionary:
		if owner == null or not is_instance_valid(owner):
			return {"ok": false, "error": "movement_policy_owner_unavailable"}
		_owner = owner
		return {"ok": true, "error": ""}

	func resolve(actor_id: String) -> Variant:
		if _owner == null or not is_instance_valid(_owner):
			return null
		return _owner._resolve_ranger_movement_policy(actor_id)


## Typed production phase domain for the fixed combat tick.
##
## This is the room-domain side of the CombatSimulation authority seam. It is
## a CombatPhasePort subclass declared by the room owner itself, and every
## phase dispatches through a typed owner reference. There is deliberately no
## has_method protocol, no string .call() indirection and no separate adapter
## script. When the remaining Main-owned phases migrate into the runtime room
## domain, this class shrinks with them.
class RoomPhaseDomain extends "res://src/runtime/combat/combat_phase_port.gd":

	var _owner: MainArena = null

	func bind(owner: MainArena) -> Dictionary:
		if owner == null or not is_instance_valid(owner):
			return {"ok": false, "error": "combat_phase_room_unavailable"}
		_owner = owner
		return {"ok": true, "error": ""}

	func is_ready() -> bool:
		return _owner != null and is_instance_valid(_owner)

	func read_only_targets() -> Array[Dictionary]:
		return _owner._read_only_targets()

	func set_elapsed(value: float) -> void:
		_owner._simulation_set_elapsed(value)

	func consume_player_events(result: Dictionary) -> void:
		_owner._consume_player_events(result)

	func update_room_rules() -> void:
		_owner._update_room_rules_tick()

	func refresh_hazard_states() -> void:
		_owner._refresh_hazard_states_tick()

	func collect_commands() -> Array[Dictionary]:
		return _owner._simulation_collect_commands()

	func route_commands(commands: Array[Dictionary]) -> Dictionary:
		return _owner._route_commands(commands)

	func update_enemies() -> void:
		_owner._update_enemies_tick()

	func advance_projectiles() -> void:
		_owner._advance_piercing_projectiles_tick()

	func resolve_hazard_hits() -> void:
		_owner._resolve_hazard_hits_tick()

	func check_battle_end() -> void:
		_owner._check_battle_end()

	func check_timeout() -> void:
		_owner._simulation_check_timeout()


## Typed EncounterDirector composition owned by Main.  The director receives
## this object once at construction and never receives a callback dictionary;
## each operation dispatches directly to the room owner through a typed method.
class MainEncounterRoomPort extends "res://src/game/encounter_room_port.gd":

	var _owner: MainArena = null

	func bind(owner: MainArena, rules: RefCounted, outcome: RefCounted) -> Dictionary:
		if owner == null or not is_instance_valid(owner):
			return {"ok": false, "error": "encounter_room_owner_unavailable"}
		if rules == null or not rules.has_method("apply_damage"):
			return {"ok": false, "error": "player_rule_port_unavailable"}
		if outcome == null or not outcome.has_method("outcome_snapshot"):
			return {"ok": false, "error": "combat_outcome_port_unavailable"}
		_owner = owner
		player_rule_port = rules
		combat_outcome_port = outcome
		return {"ok": true, "error": ""}

	func move_enemy(enemy: CombatEnemyState, displacement: Vector2) -> Dictionary:
		if not _ready():
			return {"ok": false, "error": "encounter_room_owner_unavailable"}
		return _owner._move_enemy_actor(enemy, displacement)

	func set_enemy_collision_class(enemy: CombatEnemyState, collision_class: StringName) -> bool:
		return _ready() and _owner._set_enemy_collision_class(enemy, collision_class)

	func register_enemy(enemy: CombatEnemyState) -> Dictionary:
		if not _ready():
			return {"ok": false, "error": "encounter_room_owner_unavailable"}
		var accepted: bool = _owner._register_enemy_actor(enemy)
		return {"ok": accepted, "error": "" if accepted else "register_enemy_rejected"}

	func collision_geometry(padding: float) -> Dictionary:
		if not _ready():
			return {}
		return _owner._collision_geometry(padding)

	func static_blocker_bounds() -> Array[Dictionary]:
		if not _ready():
			return []
		return _owner._static_blocker_bounds()

	func layout_spawn_offsets(layout_id: String, count: int) -> Array[Vector2]:
		if not _ready():
			return []
		return _owner._layout_spawn_offsets(layout_id, count)

	func clamp_to_arena(value: Vector2, padding: float) -> Vector2:
		if not _ready():
			return Vector2(INF, INF)
		return _owner._clamp_to_arena(value, padding)

	func quantize_position(value: Vector2) -> Vector2:
		if not _ready():
			return Vector2(INF, INF)
		return _owner._quantize_position(value)

	func queue_player_hazard_hit(tick: int, amount: float, source_id: String, source_position: Vector2) -> Dictionary:
		if not _ready():
			return {"ok": false, "error": "encounter_room_owner_unavailable"}
		return _owner._queue_kernel_player_hit(tick, amount, source_id, source_position)

	func _ready() -> bool:
		return _owner != null and is_instance_valid(_owner)


class MainEncounterSpawnPort extends "res://src/runtime/world/room_encounter_spawn_port.gd":

	var _owner: MainArena = null

	func bind(owner: MainArena) -> Dictionary:
		if owner == null or not is_instance_valid(owner):
			return {"ok": false, "error": "encounter_spawn_owner_unavailable"}
		_owner = owner
		return {"ok": true, "error": ""}

	func spawn(request: EncounterSpawnRequest, context: Dictionary) -> Variant:
		if _owner == null or not is_instance_valid(_owner):
			return EncounterSpawnResultScript.failed(request, "encounter_spawn_owner_unavailable")
		return _owner.reconcile_encounter_spawn(request, context)
