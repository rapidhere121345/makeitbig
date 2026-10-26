class_name MainArena
extends Node2D

signal return_requested

const PresentationController := preload("res://src/presentation/combat_presentation_controller.gd")
const PresentationSnapshot := preload("res://src/presentation/combat_presentation_snapshot.gd")
const InputAdapter := preload("res://src/presentation/combat_input_adapter.gd")
const CombatInterfaceTheme := preload("res://src/presentation/combat_interface_theme.gd")

const ContentRegistryScript = preload("res://src/content/content_registry.gd")
const ProxyRuntimeScript = preload("res://src/systems/proxy_runtime.gd")
const ProxyIntentSystemScript = preload("res://src/systems/proxy_intent_system.gd")
const CombatCommandProtocolScript = preload("res://src/systems/combat_command_protocol.gd")
const ManualAimResolverScript = preload("res://src/systems/manual_aim_resolver.gd")
const EnemyTacticsScript = preload("res://src/systems/enemy_tactics.gd")
const CombatEventStreamScript = preload("res://src/systems/combat_event_stream.gd")
const RangerSkillRulesScript = preload("res://src/systems/ranger_skill_rules.gd")
const PiercingArrowModelScript = preload("res://src/systems/piercing_arrow_model.gd")
const ActorRegistryScript = preload("res://src/runtime/world/actor_registry.gd")
const SimulationWorldScript = preload("res://src/runtime/world/simulation_world.gd")
const SimOutcomeScript = preload("res://src/runtime/simulation/sim_outcome.gd")
const CombatStateSnapshotBuilderScript = preload("res://src/game/combat_state_snapshot_builder.gd")
const CombatEnemyStateScript = preload("res://src/runtime/world/combat_enemy_state.gd")
const RoomCatalogScript = preload("res://src/runtime/world/room_catalog.gd")
const EncounterDirectorScript = preload("res://src/game/encounter_director.gd")
const EncounterSpawnRequestScript := preload("res://src/runtime/encounter/encounter_spawn_request.gd")
const EncounterSpawnResultScript := preload("res://src/runtime/encounter/encounter_spawn_result.gd")
const SmokeInputDriverScript := preload("res://src/game/diagnostics/smoke_input_driver.gd")
const CombatRoomRulesScript := preload("res://src/game/combat_room_rules.gd")
const CombatSystemScript = preload("res://src/systems/combat_system.gd")
const PlayerCombatStateScript := preload("res://src/runtime/world/player_combat_state.gd")
const PlayerCombatRulesScript := preload("res://src/systems/player_combat_rules.gd")
const CombatCommandSourceScript = preload("res://src/systems/combat_command_source.gd")
const MainCombatCommandSourcePortScript: Script = preload("res://src/game/main_combat_command_source_port.gd")
const CombatSimulationScript = preload("res://src/systems/combat_simulation.gd")
const RangerArrowFlightScript := preload("res://src/runtime/combat/ranger_arrow_flight.gd")
const BossArrowFlightScript := preload("res://src/runtime/combat/boss_arrow_flight.gd")
const CombatRoomLootScript := preload("res://src/game/combat_room_loot.gd")
const MainLootPlacementPortScript := preload("res://src/game/main_loot_placement_port.gd")
const CombatStatsSnapshotScript := preload("res://src/game/combat_stats_snapshot.gd")
const JsonIO := preload("res://src/core/json_io.gd")
const MainCombatRoomPortScript := preload("res://src/game/ports/main_combat_room_port.gd")
const RoomPhaseDomainScript := preload("res://src/game/ports/room_phase_domain.gd")
const MainEncounterRoomPortScript := preload("res://src/game/ports/main_encounter_room_port.gd")
const MainEncounterSpawnPortScript := preload("res://src/game/ports/main_encounter_spawn_port.gd")
const KernelReconcilerScript := preload("res://src/game/combat_room/kernel_reconciler.gd")
const RoomHazardsScript := preload("res://src/game/combat_room/room_hazards.gd")
const PiercingArrowsScript := preload("res://src/game/combat_room/piercing_arrows.gd")
const EnemyAiTicksScript := preload("res://src/game/combat_room/enemy_ai_ticks.gd")
const RoomActorSetupScript := preload("res://src/game/combat_room/actor_setup.gd")
const RoomPlayerCommandsScript := preload("res://src/game/combat_room/player_commands.gd")
const RoomTerminalScript := preload("res://src/game/combat_room/room_terminal.gd")
const RoomGeometryScript := preload("res://src/game/combat_room/room_geometry.gd")

const ARENA_MARGIN: float = 42.0
const AUTHORITY_VIEWPORT_SIZE: Vector2 = Vector2(1280.0, 720.0)
const SIM_TICKS_PER_SECOND: int = RangerSkillRulesScript.TICKS_PER_SECOND
const SIM_STEP_SECONDS: float = 1.0 / float(SIM_TICKS_PER_SECOND)
const AUTO_RANGE: float = 225.0
const BASE_PAYLOAD: float = 160.0
const FATE_SEED: int = 52969
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
var startup_errors: Array[String] = []
var proxy_prediction: String = "unknown"
var last_save_message: String = ""
var test_session: bool = false
var presentation_enabled: bool = true
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
var automation_smoke_failure: String = ""
var presentation
var input_adapter
## Production fixed-tick phase owner. CombatSimulation never receives Main as a
## callback bag; it receives the typed RoomPhaseDomain from
## src/game/ports/room_phase_domain.gd. Phase dispatch is typed virtual calls only.
var room_phase_owner: CombatPhasePort = null

## These read-only input relays are used by CombatStateSnapshotBuilder; the
## device adapter is their sole state owner. No physical source ids are replay ids.
var manual_combat_input: RefCounted:
	get:
		return input_adapter.manual_combat_input if input_adapter != null else null
var manual_pointer_target_entity_id: int:
	get:
		return input_adapter.manual_pointer_target_entity_id if input_adapter != null else 0

## Room collaborators live in src/game/combat_room/; they hold no state of their
## own and reach the room state through the typed owner reference.
var _kernel_reconciler := KernelReconcilerScript.new(self)
var _hazards := RoomHazardsScript.new(self)
var _arrows := PiercingArrowsScript.new(self)
var _enemy_ai := EnemyAiTicksScript.new(self)
var _actor_setup := RoomActorSetupScript.new(self)
var _player_commands := RoomPlayerCommandsScript.new(self)
var _terminal := RoomTerminalScript.new(self)
var _geometry := RoomGeometryScript.new(self)


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
	var room_port := MainEncounterRoomPortScript.new()
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
	var port := MainEncounterSpawnPortScript.new()
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
	var phase_domain := RoomPhaseDomainScript.new()
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
	var room_port := MainCombatRoomPortScript.new()
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
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--replay-geometry-profile="):
			replay_geometry_profile = argument.trim_prefix("--replay-geometry-profile=")
	_initialize_runtime()
	startup_errors.append_array(presentation.load_assets(presentation_enabled, CombatInterfaceTheme.create()))
	_reset_idle_state()
	get_viewport().size_changed.connect(refresh_presentation)


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
	# Before a room is started there is no configured player. Once a room owns
	# the player, Rules clears queued mobility on the current tick without
	# producing a command.
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


## Digest of the authored combat content, consumed by CombatStateSnapshotBuilder
## so a replay hash is tied to the content it ran against.
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


func _preset_display_name(preset_id: String) -> String:
	if not content_registry.presets.has(preset_id):
		return preset_id
	return "%s / %s" % [preset_id.capitalize(), String(content_registry.presets[preset_id].name)]


## Puts a freshly constructed room into its idle state: no contract running,
## room rules and loot cleared, and no held manual input.
func _reset_idle_state() -> void:
	in_arena = false
	room_rules.reset()
	_reset_room_loot()
	presentation.leave_arena()
	release_manual_controls()
	if proxy_runtime != null:
		proxy_runtime.end_contract()
	if proxy_intent_system != null:
		proxy_intent_system.reset()
	refresh_presentation()


func start_room() -> void:
	if scene_runtime != null and (not scene_runtime.is_ready() or _arena_rect().size.x <= 0.0 or _arena_rect().size.y <= 0.0 or _collision_geometry(14.0).is_empty()):
		last_save_message = "Deployment blocked: native_room_geometry_unavailable"
		return
	if not startup_errors.is_empty():
		last_save_message = "Deployment blocked by content validation"
		return
	if not _resolved_build_is_valid(framework_resolved_build):
		last_save_message = "Deployment blocked: invalid_resolved_build"
		return
	var room_error := _framework_room_error()
	if not room_error.is_empty():
		last_save_message = "Deployment blocked: %s" % room_error
		return
	_freeze_room_build()
	var room_stats := _apply_room_combat_stats()
	if not bool(room_stats.get("ok", false)):
		last_save_message = "Deployment blocked: %s" % String(room_stats.get("error", "invalid_room_combat_stats"))
		return
	proxy_runtime.end_contract()
	if selected_mode == "Auto":
		var proxy_install: Dictionary = proxy_runtime.install_resolved(
			framework_resolved_proxy_build,
			"nearest_enemy"
		)
		if not bool(proxy_install.get("ok", false)):
			last_save_message = "Deployment blocked: proxy_%s" % String(proxy_install.get("error", "invalid_build"))
			return
		var proxy_start: Dictionary = proxy_intent_system.begin_contract(framework_resolved_proxy_build)
		if not bool(proxy_start.get("ok", false)):
			last_save_message = "Deployment blocked: proxy_%s" % String(proxy_start.get("error", "invalid_initial_state"))
			proxy_runtime.end_contract()
			return
	else:
		proxy_intent_system.reset()
	var contract_start: Dictionary = proxy_runtime.begin_contract(selected_mode.to_lower())
	if not bool(contract_start.get("ok", false)):
		last_save_message = "Deployment blocked: %s" % String(contract_start.get("error", "unknown error"))
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
	if not _actor_setup._configure_actor_registry():
		if not last_save_message.begins_with("Deployment blocked:"):
			last_save_message = "Deployment blocked: actor_registry_configuration_failed"
		in_arena = false
		return
	var loot_room: Dictionary = framework_room.duplicate(true)
	if loot_room.is_empty() and test_session:
		loot_room = _load_test_room_fixture()
	var loot_configured: Dictionary = _configure_room_loot(loot_room)
	if not bool(loot_configured.get("ok", false)):
		last_save_message = "Deployment blocked: %s" % String(loot_configured.get("error", "room_loot_unavailable"))
		in_arena = false
		return
	if not _actor_setup._start_mounted_encounter():
		in_arena = false
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
	var hazard_configured: Dictionary = _hazards._configure_hazard_domain(spawn_room.get("hazard_ids", []), origin)
	if not bool(hazard_configured.get("ok", false)):
		last_save_message = "Deployment blocked: %s" % String(hazard_configured.get("error", "hazard_domain_failed"))
		in_arena = false
		return false
	room_id = String(spawned.get("room_id", ""))
	layout_id = String(spawned.get("layout_id", ""))
	objective_id = String(spawned.get("objective_id", "clear"))
	room_drop_tags = (framework_room.get("drop_tags", []) as Array).duplicate(true)
	_encounter_context()
	var configured: Dictionary = room_rules.reset_for_room(
		{"objective_id": objective_id, "drop_tags": room_drop_tags}, true,
		selected_mode, FATE_SEED, {}
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
			presentation.feedback.show_input_feedback("Loot picked up · Added to rewards on exit", sim_tick)
		elif receipt_value is Dictionary:
			presentation.feedback.show_input_feedback("Loot not picked up · %s" % String({"loot_out_of_range": "Too far away; move closer and press F", "loot_pickup_already_queued": "Pickup requested", "loot_pickup_window_closed": "Pickup window closed"}.get(String((receipt_value as Dictionary).get("error", "")), "Request expired")), sim_tick)


func _settle_room_loot(outcome: String) -> void:
	_room_loot.settle(outcome)


func settle_room_loot(outcome: String) -> Dictionary:
	if outcome not in ["victory", "defeat", "abandoned"]:
		return {"ok": false, "error": "invalid_loot_outcome"}
	return _room_loot.settle(outcome)


func _load_test_room_fixture() -> Dictionary:
	const FIXTURE_PATH := "res://content/rooms/combat/test_fixture.json"
	return JsonIO.read_object(FIXTURE_PATH)


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
	if enemy == null or not _actor_setup._register_enemy_actor(enemy):
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
	if not _actor_setup._ensure_actor_registry_ready() or not position.is_finite():
		return {"ok": false, "error": "actor_registry_not_ready_or_invalid_position"}
	var result: Dictionary = actor_registry.teleport_actor(normalized_id, position)
	if not bool(result.get("ok", false)):
		return result
	if normalized_id == "ranger":
		return result
	enemy.position = position
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


func _simulation_check_timeout() -> void:
	if automation_smoke and not battle_over and sim_tick >= SIM_TICKS_PER_SECOND * 180:
		_terminal._fail_automation_smoke("timeout ticks=%d casts=%d" % [sim_tick, shots])


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
		battle_report = "Piercing Arrow buffered; waiting for an action window." if String(receipt.get("status", "")) in ["buffered", "replaced"] else "Drawing Piercing Arrow."
	elif String(receipt.get("reason", "")) == "target_out_of_range" and selected_mode == "Manual" and source != ATTACK_SOURCE_PROXY:
		presentation.feedback.show_input_feedback("Target out of range · Move closer to shoot", sim_tick)


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
		battle_report = "Hunter's Mark locked: %s." % presentation.frame_builder.enemy_public_label(target)


func interrupt_player_action(reason: String) -> Dictionary:
	var result: Dictionary = player_combat_rules.interrupt_action(sim_tick, reason)
	presentation.feedback.forget_request(int(result.get("cleared_request_id", 0)))
	_process_player_action_events(result.get("events", []), player_combat_state.snapshot(sim_tick))
	return result


func _process_player_action_events(events: Array, action_player: Dictionary) -> void:
	for event: Dictionary in events:
		var action_id := int(event.get("action_instance_id", 0))
		match String(event.get("type", "")):
			"buffered_started", "action_started":
				presentation.feedback.bind_action_request(action_id, int(event.get("request_id", 0)))
			"action_impact":
				_arrows._resolve_piercing_arrow(event, action_player)
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
		_arrows._current_projectile_speed(),
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
	_kernel_reconciler._consume_kernel_room_combat()
	_encounter_context()
	encounter_director.update_room_rules_tick()


func _enemy_by_entity_id(id: int) -> CombatEnemyState:
	_encounter_context()
	return encounter_director._enemy_by_entity_id(id)


func _allocate_entity_id() -> int:
	_encounter_context()
	return encounter_director._allocate_entity_id()


func _framework_room_error() -> String:
	if framework_room.is_empty():
		return ""
	_ensure_room_catalog()
	return EncounterDirectorScript.validate_room(framework_room, room_catalog)


func _semantic_state_hash(result: String) -> String:
	return CombatStateSnapshotBuilderScript.hash_runtime(self, result)


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
	return _geometry._arena_rect()


func _walkable_geometry(padding: float) -> Dictionary:
	return _geometry._walkable_geometry(padding)


func _collision_geometry(radius: float) -> Dictionary:
	return _geometry._collision_geometry(radius)


func _room_socket(binding: String) -> Variant:
	return _geometry._room_socket(binding)


func _clamp_to_arena(value: Vector2, padding: float) -> Vector2:
	return _geometry._clamp_to_arena(value, padding)


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
	return_requested.emit()


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
		"presentation_geometry": _geometry._presentation_geometry(),
		"projectiles": projectiles,
		"equipped_parameters": content_registry.preset_equipped_parameters if content_registry != null else {},
		"model": _current_model() if content_registry != null else {},
		"proxy_failure": _player_commands._proxy_failure_snapshot(),
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
