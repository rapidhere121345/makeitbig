extends Node2D

signal return_requested

const PresentationController := preload("res://src/presentation/combat_presentation_controller.gd")
const PresentationSnapshot := preload("res://src/presentation/combat_presentation_snapshot.gd")
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
const CombatStateSnapshotBuilderScript = preload("res://src/game/combat_state_snapshot_builder.gd")
const CombatEnemyStateScript = preload("res://src/runtime/world/combat_enemy_state.gd")
const RoomCatalogScript = preload("res://src/runtime/world/room_catalog.gd")
const EncounterDirectorScript = preload("res://src/game/encounter_director.gd")
const SmokeInputDriverScript := preload("res://src/game/diagnostics/smoke_input_driver.gd")
const CombatRoomRulesScript := preload("res://src/game/combat_room_rules.gd")
const CombatSystemScript = preload("res://src/systems/combat_system.gd")
const PlayerCombatStateScript := preload("res://src/runtime/world/player_combat_state.gd")
const PlayerCombatRulesScript := preload("res://src/systems/player_combat_rules.gd")
const CombatCommandSourceScript = preload("res://src/systems/combat_command_source.gd")
const CombatSimulationScript = preload("res://src/systems/combat_simulation.gd")

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
		var next_tick := maxi(0, int(value))
		if simulation_world == null:
			_ensure_simulation_world()
		if simulation_world != null:
			simulation_world.set_tick(next_tick)
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
		return bool(room_rules.snapshot().battle_over)
var battle_victory: bool:
	get:
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
var last_attack_outcome: Dictionary:
	get:
		return combat_system.last_attack_outcome
var content_registry
var proxy_runtime
var proxy_intent_system
var manual_aim_resolver
var enemy_tactics
var command_source
var actor_registry
var scene_runtime
var simulation_world
var actor_registry_instance_id := ""
var actor_registry_revision := 0
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
var hazard_states: Array[Dictionary]:
	get:
		return encounter_director.hazard_states
	set(value):
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
	var configured: Dictionary = simulation_world.configure(SIM_TICKS_PER_SECOND, "combat/unmounted", 0)
	if not bool(configured.get("ok", false)):
		push_error("simulation_world_initialization_failed:%s" % String(configured.get("error", "unknown")))


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
	encounter_director.configure({
		"move_enemy": Callable(self, "_move_enemy_actor"),
		"player_rule_port": player_combat_rules,
		"combat_outcome_port": combat_system,
		"register_enemy": Callable(self, "_register_enemy_actor"),
		"walkable_geometry": Callable(self, "_walkable_geometry"),
		"layout_spawn_offsets": Callable(self, "_layout_spawn_offsets"),
		"clamp_to_arena": Callable(self, "_clamp_to_arena"),
		"quantize_position": Callable(self, "_quantize_position"),
	})
	enemy_tactics = encounter_director.enemy_tactics


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
	var configured: Dictionary = combat_simulation.configure(simulation_world, player_combat_rules, {
		"read_only_targets": Callable(self, "_read_only_targets"),
		"set_elapsed": Callable(self, "_simulation_set_elapsed"),
		"consume_player_events": Callable(self, "_consume_player_events"),
		"update_room_rules": Callable(self, "_update_room_rules_tick"),
		"refresh_hazard_states": Callable(self, "_refresh_hazard_states_tick"),
		"collect_commands": Callable(self, "_simulation_collect_commands"),
		"route_commands": Callable(self, "_route_commands"),
		"update_enemies": Callable(self, "_update_enemies_tick"),
		"advance_projectiles": Callable(self, "_advance_piercing_projectiles_tick"),
		"resolve_hazard_hits": Callable(self, "_resolve_hazard_hits_tick"),
		"check_battle_end": Callable(self, "_check_battle_end"),
		"check_timeout": Callable(self, "_simulation_check_timeout"),
	})
	if not bool(configured.get("ok", false)):
		last_save_message = "Deployment blocked: %s" % String(configured.get("error", "combat_simulation_unavailable"))
		return false
	return true


func _configure_combat_ports() -> bool:
	if replay_geometry_profile != CombatSystemScript.QUERY_PROFILE_MULTIPART_V2 and not automation_smoke:
		last_save_message = "Deployment blocked: historical replay profile requires auto smoke"
		return false
	var configured: Dictionary = combat_system.configure({
		"player_rule_port": player_combat_rules,
		"target_by_id": Callable(self, "_enemy_by_entity_id"),
		"aim_candidate": Callable(self, "_manual_aim_candidate"),
		"current_model": Callable(self, "_current_model"),
		"target_blocked": Callable(encounter_director, "is_target_blocked"),
		"maybe_summon": Callable(self, "_maybe_summon_reinforcements"),
		"remove_target": Callable(self, "_remove_combat_target"),
		"cancel_buffered_target": Callable(self, "_cancel_buffered_target"),
		"update_mark": Callable(self, "_refresh_player_mark"),
		"advance_sequence": player_combat_rules.advance_three_skill_sequence,
		"reset_sequence": player_combat_rules.reset_three_skill_sequence,
		"erase_attack_request": Callable(self, "_erase_attack_request"),
		"query_profile": replay_geometry_profile,
	})

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
	return in_arena and not battle_over
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
	if scene_runtime != null and scene_runtime.has_method("is_ready") and bool(scene_runtime.call("is_ready")):
		actor_registry = scene_runtime.get("actor_registry")
		simulation_world = scene_runtime.get("simulation")
	else:
		actor_registry = ActorRegistryScript.new()
		_ensure_simulation_world()
		simulation_world.configure(SIM_TICKS_PER_SECOND, "combat/unmounted", 0)
	content_registry = ContentRegistryScript.new()
	startup_errors = content_registry.load_all()
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
	if scene_runtime != null and (not scene_runtime.is_ready() or _arena_rect().size.x <= 0.0 or _arena_rect().size.y <= 0.0 or _walkable_geometry(14.0).is_empty()):
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
	lab_view.hide_base()
	input_adapter.reset_intent()
	command_sequence = 0
	last_command_receipts.clear()
	presentation.reset_battle()
	combat_event_stream.reset()
	automation_smoke_failure = ""
	sim_tick = 0
	room_entry_start_tick = 0
	elapsed = 0.0
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
	var spawned: Dictionary = encounter_director.spawn_wave(spawn_room, origin)
	if not bool(spawned.get("ok", false)):
		last_save_message = "Deployment blocked: %s" % String(spawned.get("error", "room_spawn_failed"))
		in_arena = false
		return false
	room_id = String(spawned.get("room_id", ""))
	layout_id = String(spawned.get("layout_id", ""))
	objective_id = String(spawned.get("objective_id", "clear"))
	room_drop_tags = (framework_room.get("drop_tags", []) as Array).duplicate(true) if embedded_session else []
	_encounter_context()
	var configured: Dictionary = room_rules.reset_for_room(
		{"objective_id": objective_id, "drop_tags": room_drop_tags}, embedded_session,
		selected_mode, FATE_SEED, {"contract_wins": contract_wins, "cores": content_registry.cores},
		Callable(self, "_commit_legacy_room_reward")
	)
	if not bool(configured.get("ok", false)):
		last_save_message = "Deployment blocked: %s" % String(configured.get("error", "room_rules_unavailable"))
		in_arena = false
		return false
	return true


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
	if actor_registry == null:
		actor_registry = ActorRegistryScript.new()
	var room_key := room_id.strip_edges()
	if room_key.is_empty():
		return false
	var preserved_sim_tick := sim_tick
	if scene_runtime != null and not scene_runtime.is_ready():
		return false
	var injected_runtime: bool = scene_runtime != null
	if injected_runtime:
		actor_registry = scene_runtime.get("actor_registry")
		simulation_world = scene_runtime.get("simulation")
		actor_registry_instance_id = String(scene_runtime.get("room_instance_id"))
		actor_registry_revision = int(scene_runtime.get("world_revision"))
		if actor_registry == null or actor_registry_instance_id.is_empty():
			return false
		if not actor_registry.has_method("reset_actors") or not bool(actor_registry.call("reset_actors")):
			return false
		if simulation_world == null or not bool(simulation_world.configure(SIM_TICKS_PER_SECOND, actor_registry_instance_id, actor_registry_revision).get("ok", false)):
			return false
	else:
		actor_registry_revision += 1
		actor_registry_instance_id = "combat/%s/%d" % [room_key, actor_registry_revision]
		var configured: Dictionary = actor_registry.configure(actor_registry_instance_id, actor_registry_revision)
		if not bool(configured.get("ok", false)):
			actor_registry_instance_id = ""
			return false
		if simulation_world == null or not bool(simulation_world.configure(SIM_TICKS_PER_SECOND, actor_registry_instance_id, actor_registry_revision).get("ok", false)):
			actor_registry_instance_id = ""
			return false
	if not injected_runtime:
		if actor_registry.has_method("clear_geometry"):
			actor_registry.call("clear_geometry")
		var boundary := ArenaGeometryScript.movement_boundary(layout_id, _arena_rect())
		if boundary.is_empty() or not actor_registry.set_boundary(boundary):
			push_error("arena_boundary_registration_failed:%s" % layout_id)
			actor_registry_instance_id = ""
			return false
	elif not actor_registry.has_method("has_movement_boundary") or not bool(actor_registry.call("has_movement_boundary")):
		push_error("manifest_movement_boundary_missing:%s" % layout_id)
		actor_registry_instance_id = ""
		return false
	var spawn_position: Vector2
	if injected_runtime:
		var authored_spawn: Variant = _room_socket("combat/spawn")
		if not authored_spawn is Vector2 or not actor_registry.is_position_clear(authored_spawn, _arena_rect(), 14.0):
			return false
		spawn_position = authored_spawn
	else:
		var projected: Dictionary = _project_actor_spawn_position(_arena_rect().get_center() + Vector2(-220.0, 100.0), 14.0)
		if not bool(projected.get("ok", false)):
			return false
		spawn_position = _quantize_position(projected["position"])
	var player_result: Dictionary = actor_registry.register_actor("ranger", spawn_position, 14.0)
	if not bool(player_result.get("ok", false)):
		actor_registry_instance_id = ""
		return false
	for enemy: CombatEnemyState in enemies:
		if not _register_enemy_actor(enemy):
			actor_registry_instance_id = ""
			return false
	if simulation_world != null and simulation_world.has_method("set_tick"):
		simulation_world.set_tick(preserved_sim_tick)
	if not _configure_player_domain(preserved_sim_tick):
		actor_registry_instance_id = ""
		return false
	return true


func _register_enemy_actor(enemy: CombatEnemyState) -> bool:
	if actor_registry == null or enemy == null:
		return false
	var projected: Dictionary = _project_actor_spawn_position(enemy.position, 16.0)
	if not bool(projected.get("ok", false)):
		return false
	var position: Vector2 = projected["position"]
	if scene_runtime != null and not actor_registry.is_position_clear(position, _arena_rect(), 16.0):
		return false
	var registered: Dictionary = actor_registry.register_actor("enemy/%d" % enemy.entity_id, position, 16.0)
	if bool(registered.get("ok", false)):
		enemy.position = position
	return bool(registered.get("ok", false))


func _ensure_actor_registry_ready() -> bool:
	if actor_registry_instance_id.is_empty():
		if not _configure_actor_registry():
			return false
	return actor_registry != null and actor_registry.actor("ranger") != null


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


func _commit_actor_move(actor_id: String, displacement: Vector2) -> Dictionary:
	if not _ensure_actor_registry_ready():
		return {"ok": false, "error": "actor_registry_not_ready", "position": Vector2.ZERO, "displacement": Vector2.ZERO}
	var state = actor_registry.actor(actor_id)
	if state == null:
		return {"ok": false, "error": "actor_not_registered", "position": Vector2.ZERO, "displacement": Vector2.ZERO}
	var result: Dictionary = actor_registry.move_actor(actor_id, displacement, sim_tick, _arena_rect())
	if not bool(result.get("ok", false)):
		if String(result.get("error", "")) == "non_monotonic_motor_tick":
			return result
		push_error("actor_move_failed:%s:%s" % [actor_id, String(result.get("error", "unknown"))])
		return result
	return result


func _move_enemy_actor(enemy: CombatEnemyState, displacement: Vector2) -> Dictionary:
	var before := enemy.position
	var result := _commit_actor_move("enemy/%d" % enemy.entity_id, displacement)
	if bool(result.get("ok", false)):
		enemy.position = result.get("position", before)
		enemy.facing = result.get("facing", enemy.facing)
	return result


func _simulate_tick() -> void:
	_ensure_combat_simulation()
	var result: Dictionary = combat_simulation.step()
	if not bool(result.get("ok", false)):
		push_error("combat_simulation_step_failed:%s" % String(result.get("error", "unknown")))


func _simulation_set_elapsed(value: float) -> void:
	elapsed = value


func _simulation_collect_commands() -> Array[Dictionary]:
	if embedded_session and automation_smoke and selected_mode == "Manual":
		var result: Dictionary = smoke_input_driver.decide({
			"player": player_combat_state.snapshot(sim_tick), "targets": _read_only_targets(),
			"hazards": hazard_states.duplicate(true), "targeting_distance": locked_targeting_distance,
			"boss": {"impact_tick": boss.impact_tick, "target_shape": boss.target_shape.duplicate(true)} if boss != null else {},
		}, command_sequence)
		command_sequence = int(result.next_sequence)
		return result.commands
	return _auto_commands() if selected_mode == "Auto" else input_adapter.collect_commands(gameplay_snapshot())


func _simulation_check_timeout() -> void:
	if automation_smoke and not battle_over and sim_tick >= SIM_TICKS_PER_SECOND * 180:
		_fail_automation_smoke("timeout ticks=%d casts=%d" % [sim_tick, shots])


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
	var result: Dictionary = proxy_intent_system.decide(_public_proxy_snapshot(), command_sequence)
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
			"targetable": encounter_director.is_targetable(enemy),
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
	combat_system.advance_projectiles_tick()
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


func _cancel_buffered_target(entity_id: int) -> int:
	return player_combat_rules.cancel_buffered_target(entity_id)


func _erase_attack_request(request_id: int) -> void:
	if request_id > 0:
		presentation.feedback.forget_request(request_id)


func _encounter_context() -> void:
	if encounter_director == null:
		return
	encounter_director.set_context(
		sim_tick,
		player_position,
		_arena_rect(),
		combat_event_stream,
		layout_id,
		objective_id
	)


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
	_encounter_context()
	return encounter_director.enemy_tactics_hazards()


func _maybe_summon_reinforcements(elite: CombatEnemyState) -> void:
	_encounter_context()
	var previous_report := String(encounter_director.battle_report)
	encounter_director._maybe_summon_reinforcements(elite)
	_encounter_report(previous_report)


func _update_room_rules_tick() -> void:
	_encounter_context()
	encounter_director.update_room_rules_tick()


func _update_hazards_tick() -> void:
	_encounter_context()
	var previous_report := String(encounter_director.battle_report)
	encounter_director.update_hazards_tick()
	_encounter_report(previous_report)


func _refresh_hazard_states_tick() -> void:
	_encounter_context()
	encounter_director.refresh_hazard_states_tick()


func _resolve_hazard_hits_tick() -> void:
	_encounter_context()
	var previous_report := String(encounter_director.battle_report)
	encounter_director.resolve_hazard_hits_tick()
	_encounter_report(previous_report)


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
	if marked != null and marked.health > 0.0 and sim_tick < player["hunter_mark_expires_tick"] and player_position.distance_to(marked.position) <= locked_targeting_distance:
		return marked
	if player["hunter_mark_candidate_entity_id"] > 0 and sim_tick <= player["hunter_mark_candidate_expires_tick"]:
		var candidate := _enemy_by_entity_id(player["hunter_mark_candidate_entity_id"])
		if candidate != null and candidate.health > 0.0 and player_position.distance_to(candidate.position) <= locked_targeting_distance:
			return candidate
	return _nearest_enemy()


func _nearest_enemy(maximum_distance: float = INF) -> CombatEnemyState:
	var nearest: CombatEnemyState
	var best_distance: float = maximum_distance * maximum_distance
	for enemy: CombatEnemyState in enemies:
		if enemy.health <= 0.0:
			continue
		var distance: float = player_position.distance_squared_to(enemy.position)
		if distance < best_distance or (is_equal_approx(distance, best_distance) and (nearest == null or enemy.entity_id < nearest.entity_id)):
			best_distance = distance
			nearest = enemy
	return nearest


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
	if _walkable_geometry(radius).is_empty():
		return {"ok": false, "error": "spawn_geometry_unavailable"}
	var boundary: Dictionary = {}
	if scene_runtime != null:
		var runtime_boundary: Variant = scene_runtime.get("movement_boundary")
		if runtime_boundary is Dictionary:
			boundary = (runtime_boundary as Dictionary).duplicate(true)
	else:
		boundary = ArenaGeometryScript.movement_boundary(layout_id, _arena_rect())
	var normalized: Dictionary = ArenaGeometryScript.normalize_native_boundary(boundary)
	if not bool(normalized.get("ok", false)):
		return {"ok": false, "error": "spawn_boundary_unavailable"}
	boundary = normalized["value"]
	match String(boundary.get("type", "")):
		"rect":
			var rect: Rect2 = boundary["rect"]
			return {"ok": true, "position": Vector2(
				clampf(value.x, rect.position.x + radius, rect.end.x - radius),
				clampf(value.y, rect.position.y + radius, rect.end.y - radius)
			)}
		"corridor":
			var corridor: Rect2 = boundary["rect"]
			var half_height := float(boundary["half_height"]) - radius
			if half_height <= 0.0:
				return {"ok": false, "error": "spawn_footprint_exceeds_corridor"}
			var center_y := corridor.get_center().y
			return {"ok": true, "position": Vector2(
				clampf(value.x, corridor.position.x + radius, corridor.end.x - radius),
				clampf(value.y, center_y - half_height, center_y + half_height)
			)}
		"ring":
			var center: Vector2 = boundary["center"]
			var offset := value - center
			var distance := offset.length()
			var direction := offset.normalized() if distance > 0.000001 else Vector2.RIGHT
			var inner := float(boundary["inner_radius"]) + radius
			var outer := float(boundary["outer_radius"]) - radius
			if inner >= outer:
				return {"ok": false, "error": "spawn_footprint_exceeds_ring"}
			return {"ok": true, "position": center + direction * clampf(distance, inner, outer)}
	return {"ok": false, "error": "unsupported_spawn_boundary"}


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
	input_adapter.configure(command_source, {
		"make_move": Callable(self, "_move_command"),
		"make_dodge": Callable(self, "_dodge_command"),
		"make_cast": Callable(self, "_cast_command"),
	}, presentation.feedback, presentation.screen_to_gameplay, presentation.is_pointer_over_interface)


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
		"proxy_prediction": proxy_prediction,
		"selected_mode": selected_mode,
		"arena_rect": _arena_rect(), "walkable_geometry": _walkable_geometry(14.0),
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
