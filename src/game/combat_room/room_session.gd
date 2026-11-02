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
const CombatCommandProtocolScript := preload("res://src/systems/combat_command_protocol.gd")
const RangerSkillRulesScript := preload("res://src/systems/ranger_skill_rules.gd")

## Frozen gameplay constants of the Ranger's first chapter. MainArena re-exports
## them under the same names.
const AUTO_RANGE: float = 225.0
const BASE_PAYLOAD: float = 160.0
const FATE_SEED: int = 52969
## Authority viewport and arena margin used when no mounted room supplies the
## authored arena rectangle.
const ARENA_MARGIN: float = 42.0
const AUTHORITY_VIEWPORT_SIZE: Vector2 = Vector2(1280.0, 720.0)
const SIM_TICKS_PER_SECOND: int = RangerSkillRulesScript.TICKS_PER_SECOND
## Attack sources a cast request can carry (feedback bookkeeping only).
const ATTACK_SOURCE_ASSISTED: String = "assisted"
const ATTACK_SOURCE_POINTER: String = "pointer"
const ATTACK_SOURCE_PROXY: String = "proxy"

## Build lock: the rule inputs frozen when a contract starts.
var selected_preset: String = "convergent"
var selected_mode: String = "Manual"
var locked_p: float = PiercingArrowModel.BASE_P
var locked_payload: float = BASE_PAYLOAD
var locked_targeting_distance: float = AUTO_RANGE
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
## Device-command source the view hands in (null: no external commands).
var command_intake: RoomCommandIntake = null
var combat_event_stream
var kernel_bindings := KernelBindingsScript.new()
var room_loot := CombatRoomLootScript.new()

## Mounted-room authorities adopted from SceneRuntime (or the standalone room
## assembly) and the typed ports built over them.
var actor_registry
var simulation_world
## SceneRuntime the room is mounted in (null for a standalone room).
var scene_runtime
## Authored content the room validates against (loaded by the view's runtime
## initialization).
var content_registry
## Authority tick committed by the simulation world (0 before one exists).
## Ticks are only ever committed by SimulationWorld.step_tick().
var sim_tick: int:
	get:
		return int(simulation_world.tick) if simulation_world != null else 0
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
## Art boxes (world pixels) of the actor visuals the room binds into the
## presentation projector, captured by the view when the room is configured so
## spawning during a tick never queries the presentation. Keyed by visual id.
var actor_art_boxes: Dictionary = {}
var framework_seed: int = FATE_SEED


## Authored arena rectangle: the mounted room's, or the fixed authority
## viewport rectangle for a standalone room.
func arena_rect() -> Rect2:
	if scene_runtime != null:
		var authored: Variant = scene_runtime.get("authored_arena_rect")
		return authored as Rect2 if authored is Rect2 else Rect2()
	return Rect2(Vector2(ARENA_MARGIN, 190.0), Vector2(
		AUTHORITY_VIEWPORT_SIZE.x - ARENA_MARGIN * 2.0,
		AUTHORITY_VIEWPORT_SIZE.y - 190.0 - ARENA_MARGIN))


## True once the mounted encounter or the room rules report victory or defeat.
func is_battle_over() -> bool:
	if room_encounter_port != null and room_encounter_port.encounter is RoomEncounter:
		var terminal: Dictionary = room_encounter_port.snapshot().get("terminal", {})
		if String(terminal.get("phase", "")) in ["victory", "defeat"]:
			return true
	return bool(room_rules.snapshot().battle_over)


func is_battle_victory() -> bool:
	if room_encounter_port != null and room_encounter_port.encounter is RoomEncounter:
		var terminal: Dictionary = room_encounter_port.snapshot().get("terminal", {})
		if String(terminal.get("phase", "")) in ["victory", "defeat"]:
			return bool(terminal.get("victory", false))
	return bool(room_rules.snapshot().battle_victory)


## Player position at the current authority tick.
func player_position() -> Vector2:
	return player_combat_state.snapshot(sim_tick)["player_position"]


## Arbitrates the collected commands for this tick against the equipped skills.
func route_commands(commands: Array[Dictionary]) -> Dictionary:
	return CombatCommandProtocolScript.arbitrate(commands, sim_tick, player_combat_state.equipped_ability_ids(), true)


## Read-only copies of the live enemies the player rules aim and mark against.
func read_only_targets() -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	for enemy: CombatEnemyState in encounter_director.enemies:
		targets.append(manual_aim_candidate(enemy))
	return targets


func manual_aim_candidate(enemy: CombatEnemyState) -> Dictionary:
	return {
		"entity_id": enemy.entity_id,
		"kind_id": enemy.kind_id,
		"position": enemy.position,
		"health": enemy.health,
		"is_boss": enemy.is_boss,
	}


func refresh_player_mark() -> void:
	player_combat_rules.update_mark(sim_tick, read_only_targets())


func enemy_by_entity_id(id: int) -> CombatEnemyState:
	sync_encounter_context()
	return encounter_director._enemy_by_entity_id(id)


func allocate_entity_id() -> int:
	sync_encounter_context()
	return encounter_director._allocate_entity_id()


## False for an enemy whose registry actor is inactive; true when the registry
## cannot say (standalone room).
func is_enemy_actor_active(enemy: CombatEnemyState) -> bool:
	if enemy == null:
		return false
	if actor_registry is RoomActorAccess:
		return bool(actor_registry.is_actor_active("enemy/%d" % enemy.entity_id))
	return true


## The hunter-marked target, else the pending mark candidate, else the nearest
## active enemy.
func preferred_skill_one_target() -> CombatEnemyState:
	var player := player_combat_state.snapshot(sim_tick)
	var marked := enemy_by_entity_id(player["marked_entity_id"])
	if marked != null and is_enemy_actor_active(marked) and marked.health > 0.0 and sim_tick < player["hunter_mark_expires_tick"] and player_position().distance_to(marked.position) <= locked_targeting_distance:
		return marked
	if player["hunter_mark_candidate_entity_id"] > 0 and sim_tick <= player["hunter_mark_candidate_expires_tick"]:
		var candidate := enemy_by_entity_id(player["hunter_mark_candidate_entity_id"])
		if candidate != null and is_enemy_actor_active(candidate) and candidate.health > 0.0 and player_position().distance_to(candidate.position) <= locked_targeting_distance:
			return candidate
	return nearest_enemy()


func nearest_enemy(maximum_distance: float = INF) -> CombatEnemyState:
	var nearest: CombatEnemyState
	var best_distance: float = maximum_distance * maximum_distance
	for enemy: CombatEnemyState in encounter_director.enemies:
		if enemy.health <= 0.0 or not is_enemy_actor_active(enemy):
			continue
		var distance: float = player_position().distance_squared_to(enemy.position)
		if distance < best_distance or (is_equal_approx(distance, best_distance) and (nearest == null or enemy.entity_id < nearest.entity_id)):
			best_distance = distance
			nearest = enemy
	return nearest


func is_skill_equipped(slot_index: int, expected_id: String) -> bool:
	var skills: Array = player_combat_state.snapshot(sim_tick).get("equipped_skills", [])
	return slot_index >= 0 and slot_index < skills.size() and String(skills[slot_index]) == expected_id


## Growth model of the frozen build (or the calibrated preset when no build is
## locked), as the combat system consumes it.
func current_model() -> Dictionary:
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


## Fails an automation-smoke run that outlives three simulated minutes.
func check_timeout() -> void:
	if automation_smoke and not is_battle_over() and sim_tick >= SIM_TICKS_PER_SECOND * 180:
		fail_automation_smoke("timeout ticks=%d casts=%d" % [sim_tick, int(combat_system.outcome_snapshot().shots)])


## Records an automation-smoke failure on the room rules and the report. The
## host decides whether the process exits.
func fail_automation_smoke(reason: String) -> void:
	automation_smoke_failure = reason
	room_rules.fail(reason)
	battle_report = String(room_rules.snapshot().report)


## Creates the combat system on first use.
func ensure_combat_system() -> void:
	if combat_system == null:
		combat_system = CombatSystemScript.new()


## Projectile speed the Ranger's arrows fly at: the frozen build's, else the
## calibrated preset's. Never zero or non-finite.
func current_projectile_speed() -> float:
	var speed := 0.0
	if not locked_build.is_empty():
		speed = float((locked_build.get("final_parameters", {}) as Dictionary).get("v", 0.0))
	elif content_registry != null:
		speed = float(content_registry.preset_equipped_parameters.get("speed", 0.0))
	if not is_finite(speed) or speed <= 0.0:
		return 1.0
	return speed


## Pushes the player's pre-motor context into the combat system. The order of
## these pushes relative to the tick phases is part of the replay contract.
func sync_combat_context(player: Dictionary = {}) -> void:
	if player.is_empty():
		player = player_combat_state.snapshot(sim_tick)
	ensure_combat_system()
	combat_system.set_context(
		sim_tick,
		player["player_position"],
		player["player_facing"],
		locked_payload,
		locked_targeting_distance,
		current_projectile_speed(),
		player["marked_entity_id"],
		player["talent_capabilities"],
		combat_event_stream,
		manual_aim_resolver,
		encounter_director.enemies
	)
	combat_system.attack_origins = (player.get("attack_origins", {}) as Dictionary).duplicate(true)


## Adopts the combat system's report when this resolution produced a new one.
func adopt_combat_report(previous_report: String, previous_event_id: int) -> void:
	var report := String(combat_system.battle_report)
	if report.is_empty():
		return
	var fresh := report != previous_report
	for event: Dictionary in combat_event_stream.events_after(previous_event_id):
		if String(event.get("type", "")) == "projectile_spawned" or (String(event.get("type", "")) == "attack_resolved" and String(event.get("source_id", "")) == "ranger/piercing_arrow"):
			fresh = true
	if fresh:
		battle_report = report


## Pushes the room context (tick, player position, arena, layout, objective)
## into the encounter director.
func sync_encounter_context() -> void:
	if encounter_director == null:
		return
	sync_encounter_active_state()
	encounter_director.set_context(
		sim_tick,
		player_combat_state.snapshot(sim_tick)["player_position"],
		arena_rect(),
		combat_event_stream,
		layout_id,
		objective_id
	)


## Tells the director which of its enemies are active actors in the registry.
func sync_encounter_active_state() -> void:
	if encounter_director == null or room_encounter_port == null or room_encounter_port.encounter == null:
		return
	if not actor_registry is RoomActorAccess:
		return
	var active_ids: Array[int] = []
	for enemy: CombatEnemyState in encounter_director.enemies:
		var actor_id := "enemy/%d" % enemy.entity_id
		if actor_registry.has_actor(actor_id) and actor_registry.is_actor_active(actor_id):
			active_ids.append(enemy.entity_id)
	encounter_director.set_active_entity_ids(active_ids)


## Drains the kernel's pending encounter spawn requests into the mounted
## room (a no-op for a standalone room).
func materialize_encounter_spawns() -> void:
	if scene_runtime != null and scene_runtime.is_ready():
		scene_runtime.materialize_encounter_spawns()


## Runs the encounter director's rule tick after refreshing its context.
func update_encounter_rules() -> void:
	sync_encounter_context()
	encounter_director.update_room_rules_tick()


func adopt_encounter_report(previous_report: String) -> void:
	var report := String(encounter_director.battle_report)
	if not report.is_empty() and report != previous_report:
		battle_report = report


## Replaces the battle report text. The view calls this for status lines the
## player's input produces outside the fixed tick (pointer lock messages).
func set_status_report(text: String) -> void:
	battle_report = text


## Presentation events produced by the ticks since the last drain, in emission
## order. The authority only appends; the view drains after each step().
var _presentation_events: Array[RoomPresentationEvent] = []


## Appends one presentation effect to the event log.
func record_event(event: RoomPresentationEvent) -> void:
	_presentation_events.append(event)


## Returns the pending presentation events in emission order and clears the log.
func drain_events() -> Array[RoomPresentationEvent]:
	var drained := _presentation_events
	_presentation_events = []
	return drained


## Routes the combat system's impact-trace and corpse signals into the event
## log. Call once after the combat system exists.
func record_combat_system_events() -> void:
	if combat_system == null:
		return
	combat_system.impact_trace_requested.connect(_record_impact_trace)
	combat_system.corpse_requested.connect(_record_corpse)


func _record_impact_trace(position: Vector2, direction: Vector2, generations: int) -> void:
	record_event(RoomPresentationEvent.impact_trace(position, direction, generations))


func _record_corpse(visual: Dictionary) -> void:
	record_event(RoomPresentationEvent.corpse_detached(visual))


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
