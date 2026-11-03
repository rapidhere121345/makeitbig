class_name RoomSession
extends RefCounted

## Authoritative state and logic of one combat room. MainArena (the room view)
## creates and holds the session and keeps every historical property name as a
## forwarding property, so the state hash builder, the room helpers, the ports
## and the tests keep reading `arena.<name>`. The session is never a Node, imports
## no presentation code and holds no MainArena reference. It owns the simulation
## lifecycle, the combat and encounter context syncs, the player-event
## consumption, target and enemy queries, the contract start/idle resets, the
## build freeze (through its ClassKit), room loot and the presentation event
## log. The fixed-tick phase hooks stay on MainArena (RoomPhaseDomain dispatches
## to them) and delegate here or to the combat_room collaborators that still
## take MainArena (see docs/rebuild/ROOM_SESSION_DESIGN.md, migration items 3 to
## 6).

const CombatRoomLootScript := preload("res://src/game/combat_room_loot.gd")
const CombatRoomRulesScript := preload("res://src/game/combat_room_rules.gd")
const KernelBindingsScript := preload("res://src/game/combat_room/kernel_bindings.gd")
const PlayerCombatStateScript := preload("res://src/runtime/world/player_combat_state.gd")
const PlayerCombatRulesScript := preload("res://src/runtime/combat/player_combat_rules.gd")
const SmokeInputDriverScript := preload("res://src/game/diagnostics/smoke_input_driver.gd")
const CombatSystemScript := preload("res://src/runtime/combat/combat_system.gd")
const CombatSimulationScript := preload("res://src/runtime/combat/combat_simulation.gd")
const ContentRegistryScript := preload("res://src/content/content_registry.gd")
const JsonIO := preload("res://src/core/json_io.gd")
const SimulationWorldScript := preload("res://src/runtime/world/simulation_world.gd")
const CombatStatsSnapshotScript := preload("res://src/systems/combat_stats_snapshot.gd")
const EncounterDirectorScript := preload("res://src/game/encounter_director.gd")
const MainLootPlacementPortScript := preload("res://src/game/main_loot_placement_port.gd")
const RoomCatalogScript := preload("res://src/runtime/world/room_catalog.gd")
const CombatCommandProtocolScript := preload("res://src/systems/combat_command_protocol.gd")
const RangerSkillRulesScript := preload("res://src/content/ranger_skill_rules.gd")
const RangerKitScript := preload("res://src/game/classes/ranger/ranger_kit.gd")

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
## Stability prediction of the proxy build for this contract ("manual" in
## Manual mode, "unknown" before a contract starts).
var proxy_prediction: String = "unknown"
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
## The room half of the player class (docs/rebuild/ROOM_SESSION_DESIGN.md,
## "ClassKit"): the class-specific rules the session routes receipts, action
## events and combat reports to. Owns no session reference; every kit call
## passes the session.
var kit: ClassKit = RangerKitScript.new()

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
## locked), as the combat system consumes it. Class-specific; lives on the kit.
func current_model() -> Dictionary:
	return kit.growth_model(self)


## Authority half of the player domain's tick result: cast receipts and the
## report text, the command receipts, and the combat context pushes around the
## action events. Presentation effects are only logged (record_event). Both the
## pre-command and post-command timelines have their own pre-motor context, so
## later mark expiry or movement never alters an arrow release.
func consume_player_events(result: Dictionary) -> void:
	var player: Dictionary = result["player"]
	var action_player: Dictionary = result.get("action_player", player)
	for receipt: Dictionary in result.get("receipts", []):
		if kit.handle_receipt(self, receipt, player):
			continue
		var command: Dictionary = receipt.get("command", {})
		record_event(RoomPresentationEvent.command_discarded(int(command.get("sequence", -1))))
	if result.has("protocol_receipts"):
		last_command_receipts.assign((result["protocol_receipts"] as Array).duplicate(true))
	sync_combat_context(action_player)
	process_player_action_events(result.get("action_events", []), action_player)
	sync_combat_context(player)


## Explicit diagnostic cast: enters the same domain as device and replay
## commands. The caller applies the logged presentation events afterwards.
func process_player_action_events(events: Array, action_player: Dictionary) -> void:
	for event: Dictionary in events:
		var action_id := int(event.get("action_instance_id", 0))
		match String(event.get("type", "")):
			"buffered_started", "action_started":
				record_event(RoomPresentationEvent.action_request_bound(action_id, int(event.get("request_id", 0))))
			"action_impact":
				kit.resolve_action_impact(self, event, action_player)
			"action_ended", "action_interrupted":
				record_event(RoomPresentationEvent.action_forgotten(action_id))


## Explicit diagnostic cast: enters the same domain as device and replay
## commands. The caller applies the logged presentation events afterwards.
func request_player_cast(ability_id: String, target_entity_id: int, direction: Vector2, source: String) -> Dictionary:
	var receipt: Dictionary = player_combat_rules.request_cast(sim_tick, ability_id, target_entity_id, direction, read_only_targets())
	kit.handle_diagnostic_receipt(self, ability_id, receipt, source)
	process_player_action_events(receipt.get("action_events", []), player_combat_state.snapshot(sim_tick))
	return receipt


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


## Creates the standalone simulation world on first use. A mounted room
## replaces it with the SceneRuntime's world.
func ensure_simulation_world() -> void:
	if simulation_world != null:
		return
	simulation_world = SimulationWorldScript.new()
	var configured = simulation_world.configure("combat/unmounted", 0, SIM_TICKS_PER_SECOND)
	if not configured.ok:
		push_error("simulation_world_initialization_failed:%s" % String(configured.error))


## Digest of the authored combat content, consumed by CombatStateSnapshotBuilder
## so a replay hash is tied to the content it ran against.
func content_hash() -> String:
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


func preset_display_name(preset_id: String) -> String:
	if not content_registry.presets.has(preset_id):
		return preset_id
	return "%s / %s" % [preset_id.capitalize(), String(content_registry.presets[preset_id].name)]


## Fixture room used when a test session has no authored framework room.
func load_test_room_fixture() -> Dictionary:
	const FIXTURE_PATH := "res://content/rooms/combat/test_fixture.json"
	return JsonIO.read_object(FIXTURE_PATH)


## Creates the room catalog on first use.
func ensure_room_catalog() -> void:
	if room_catalog == null:
		room_catalog = RoomCatalogScript.new()


## Authored-room validation error for the framework room ("" when valid).
func framework_room_error() -> String:
	if framework_room.is_empty():
		return ""
	ensure_room_catalog()
	return EncounterDirectorScript.validate_room(framework_room, room_catalog)


## Freezes the rule inputs of the contract: the resolved build (or the
## calibrated preset model), its payload, probability and targeting range.
## Class-specific; lives on the kit.
func freeze_room_build() -> void:
	kit.freeze_build(self)


## Applies the room's combat-stat overlay to the frozen build.
func apply_room_combat_stats() -> Dictionary:
	if not framework_room.has("combat_stats"):
		return {"ok": true, "error": "", "enabled": false}
	var authored_room_id := room_id if not room_id.is_empty() else String(framework_room.get("room_id", framework_room.get("id", "")))
	var result := CombatStatsSnapshotScript.from_room_overlay(locked_build, framework_room.get("combat_stats"), authored_room_id)
	if not bool(result.get("ok", false)):
		return result
	var stats: Variant = result.get("value", null)
	if not stats is CombatStatsSnapshot:
		return {"ok": false, "error": "invalid_room_combat_stats_snapshot"}
	locked_build["combat_stats"] = stats.snapshot()
	return {"ok": true, "error": "", "enabled": true, "combat_stats": locked_build["combat_stats"].duplicate(true)}


## Installs the Auto proxy build (or resets the proxy for Manual) and starts
## the proxy contract. Returns the "Deployment blocked" reason, or "" on
## success; `proxy_prediction` receives the stability prediction.
func begin_proxy_contract() -> String:
	proxy_runtime.end_contract()
	if selected_mode == "Auto":
		var proxy_install: Dictionary = proxy_runtime.install_resolved(
			framework_resolved_proxy_build,
			"nearest_enemy"
		)
		if not bool(proxy_install.get("ok", false)):
			return "Deployment blocked: proxy_%s" % String(proxy_install.get("error", "invalid_build"))
		var proxy_start: Dictionary = proxy_intent_system.begin_contract(framework_resolved_proxy_build)
		if not bool(proxy_start.get("ok", false)):
			proxy_runtime.end_contract()
			return "Deployment blocked: proxy_%s" % String(proxy_start.get("error", "invalid_initial_state"))
	else:
		proxy_intent_system.reset()
	var contract_start: Dictionary = proxy_runtime.begin_contract(selected_mode.to_lower())
	if not bool(contract_start.get("ok", false)):
		return "Deployment blocked: %s" % String(contract_start.get("error", "unknown error"))
	var requirements := {
		"perception": {"target_count": 1},
		"movement": {"pathing": 1.0, "range_control": 1.0},
		"execution": {"skill_count": 1, "timing": 1.0},
		"memory": {"target_memory": 1, "rotation_steps": 1},
	}
	proxy_prediction = proxy_runtime.predict(requirements) if selected_mode == "Auto" else "manual"
	return ""


## Authority resets of a contract start: the live flag, room rules, loot, command
## receipts, event stream, run clock, and any presentation events still pending
## from before the reset.
func reset_for_contract() -> void:
	in_arena = true
	room_rules.reset()
	room_loot.reset()
	command_sequence = 0
	last_command_receipts.clear()
	last_loot_pickup_command_receipt.clear()
	combat_event_stream.reset()
	automation_smoke_failure = ""
	room_entry_start_tick = 0
	elapsed = 0.0
	clear_events()


## Idle room: no contract running, room rules and loot cleared.
func reset_idle() -> void:
	in_arena = false
	room_rules.reset()
	room_loot.reset()
	clear_events()


## Ends the proxy contract and clears the proxy intent state.
func end_proxy_contract() -> void:
	if proxy_runtime != null:
		proxy_runtime.end_contract()
	if proxy_intent_system != null:
		proxy_intent_system.reset()


## Starts a new wave: the actor registry identity is re-derived and the combat
## event stream starts over.
func begin_wave_reset() -> void:
	actor_registry_instance_id = ""
	if combat_event_stream != null:
		combat_event_stream.reset()


## Configures the room's loot slots against the mounted room's (or the actor
## registry's) spatial placement.
func configure_room_loot(room: Dictionary) -> Dictionary:
	if content_registry == null or content_registry.early_item_registry == null:
		room_loot.reset()
		return {"ok": false, "error": "loot_item_registry_unavailable"} if room.has("loot_slots") else {"ok": true, "error": "", "enabled": false}
	var placement_room: Variant = scene_runtime if scene_runtime != null and scene_runtime.is_ready() else actor_registry
	var placement_port := MainLootPlacementPortScript.new()
	var placement_bound: Dictionary = placement_port.configure(placement_room)
	if not bool(placement_bound.get("ok", false)):
		room_loot.reset()
		return placement_bound
	return room_loot.configure(room, room_id, framework_seed, content_registry.early_item_registry, placement_port)


func spawn_room_loot_for_source(source: String, source_entity_id: int, position: Vector2) -> Dictionary:
	return room_loot.spawn_for_source(sim_tick, source, source_entity_id, position)


func request_loot_pickup(loot_entity_id: String) -> Dictionary:
	return room_loot.request_pickup(sim_tick, in_arena, is_battle_over(), is_battle_victory(), loot_entity_id)


## Commits the queued pickups at the post-movement phase and logs the player
## feedback for the newest receipt.
func process_room_loot_pickups_tick() -> void:
	var player := player_combat_state.snapshot(sim_tick)
	var receipts_before: Array = (room_loot.snapshot().get("pickup_receipts", []) as Array).duplicate(true)
	room_loot.process_pickups(sim_tick, float(player.get("player_health", 0.0)), player.player_position, is_battle_over(), is_battle_victory())
	var receipts_after: Array = room_loot.snapshot().get("pickup_receipts", [])
	if receipts_after.size() > receipts_before.size():
		var receipt_value: Variant = receipts_after[receipts_after.size() - 1]
		if receipt_value is Dictionary and bool((receipt_value as Dictionary).get("ok", false)):
			record_event(RoomPresentationEvent.input_feedback("Loot picked up · Added to rewards on exit", sim_tick))
		elif receipt_value is Dictionary:
			record_event(RoomPresentationEvent.input_feedback("Loot not picked up · %s" % String({"loot_out_of_range": "Too far away; move closer and press F", "loot_pickup_already_queued": "Pickup requested", "loot_pickup_window_closed": "Pickup window closed"}.get(String((receipt_value as Dictionary).get("error", "")), "Request expired")), sim_tick))


func settle_room_loot(outcome: String) -> Dictionary:
	if outcome not in ["victory", "defeat", "abandoned"]:
		return {"ok": false, "error": "invalid_loot_outcome"}
	return room_loot.settle(outcome)


## Creates the combat system on first use.
func ensure_combat_system() -> void:
	if combat_system == null:
		combat_system = CombatSystemScript.new()


## Projectile speed the Ranger's arrows fly at: the frozen build's, else the
## calibrated preset's. Never zero or non-finite. Class-specific; lives on the
## kit.
func current_projectile_speed() -> float:
	return kit.projectile_speed(self)


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
		if String(event.get("type", "")) == "projectile_spawned" or kit.owns_attack_event(event):
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
## order. The authority only appends.
##
## Drain contract: the session never drains itself. Whoever runs step() owns the
## log and calls drain_events() after every step. MainArena (the room view)
## drains after each fixed tick, before every presentation refresh and after a
## diagnostic cast, whether or not presentation is enabled: with presentation
## off the events are still drained and the view-side applier hands them to a
## disabled feedback controller (or drops them when there is none), so the log
## stays empty between ticks. A host that steps a session with no view must call
## drain_events() and discard the result, or clear_events(). As a safety net the
## log is bounded: past MAX_PENDING_EVENTS the oldest half is discarded and
## counted in dropped_events, so a session stepped directly never grows without
## bound. Dropping affects presentation only, never authority or the state hash.
## Contract start and idle reset clear the log, since the view resets its own
## feedback state at the same moments.
const MAX_PENDING_EVENTS: int = 4096
var _presentation_events: Array[RoomPresentationEvent] = []
## Events discarded by the bound since the session was created (diagnostic).
var dropped_events: int = 0


## Appends one presentation effect to the event log.
func record_event(event: RoomPresentationEvent) -> void:
	if _presentation_events.size() >= MAX_PENDING_EVENTS:
		var kept: Array[RoomPresentationEvent] = []
		kept.assign(_presentation_events.slice(MAX_PENDING_EVENTS / 2))
		dropped_events += _presentation_events.size() - kept.size()
		_presentation_events = kept
	_presentation_events.append(event)


## Returns the pending presentation events in emission order and clears the log.
func drain_events() -> Array[RoomPresentationEvent]:
	var drained := _presentation_events
	_presentation_events = []
	return drained


## Discards the pending presentation events without applying them.
func clear_events() -> void:
	_presentation_events = []


## Number of presentation events waiting for a drain.
func pending_event_count() -> int:
	return _presentation_events.size()


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
