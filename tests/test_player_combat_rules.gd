extends SceneTree

const State := preload("res://src/runtime/world/player_combat_state.gd")
const World := preload("res://src/runtime/world/simulation_world.gd")
const RoomSpatialPortScript := preload("res://src/runtime/world/room_spatial_port.gd")
const RoomActorAccessScript := preload("res://src/runtime/world/room_actor_access.gd")
const StaticSpatialIndexScript := preload("res://src/runtime/spatial/static_spatial_index.gd")
const DynamicSpatialIndexScript := preload("res://src/runtime/spatial/dynamic_spatial_index.gd")
const SpatialOverlayScript := preload("res://src/runtime/spatial/spatial_overlay.gd")
const MovementResolverScript := preload("res://src/runtime/spatial/movement_resolver.gd")
const Rules := preload("res://src/systems/player_combat_rules.gd")
const Stream := preload("res://src/systems/combat_event_stream.gd")
const Protocol := preload("res://src/systems/combat_command_protocol.gd")
const Big := preload("res://src/core/big_value.gd")
const Assert := preload("res://tests/helpers/assert.gd")

var failures: Array[String] = []
var spatial_port := RoomSpatialPortScript.new()
var world: SimulationWorld = World.new(spatial_port)
var access := RoomActorAccessScript.new()
var registry
var state := State.new()
var rules := Rules.new()
var stream := Stream.new()
var targets: Array[Dictionary] = [{"entity_id": 7, "kind_id": "grunt", "health": 100.0, "position": Vector2(100, 0), "is_boss": false}]


func _initialize() -> void:
	_reset({"three_skill_rhythm_windup_ticks": 2.0, "lost_mark_candidate_ticks": 3.0, "dodge_cooldown_reduction": 0.2, "first_critical_bonus_generations": 2, "expiry_payload_retention": 0.5})
	var step := _step([Protocol.cast(1, "ranger", 1, "piercing_arrow", 7)])
	var receipt: Dictionary = step.receipts[0]
	_expect(receipt.accepted and receipt.action_instance_id == 1 and receipt.request_id == 1, "attack stable ids changed")
	_expect(step.player.attack_cooldown_ticks == 13 and step.player.action_phase == "windup", "attack timers/phase changed")
	var command_event := stream.latest("command_receipt")
	_expect(command_event.status == "accepted" and command_event.reason == "started", "attack command stream receipt encoding changed")
	var accepted := stream.latest("action_accepted")
	_expect(accepted.action_instance_id == 1 and accepted.target_entity_id == 7 and accepted.impact_tick == 6, "action_accepted contract changed")
	var before := state.snapshot(world.tick)
	var count := stream.latest_event_id()
	_expect(rules.advance_tick(world.tick, {}, targets).error == "duplicate_player_tick", "duplicate real player tick accepted")
	_expect(state.snapshot(world.tick).timeline == before.timeline and stream.latest_event_id() == count, "duplicate tick changed domain/events")
	_expect(rules.advance_tick(world.tick + 1, {}, targets).error == "uncommitted_world_tick", "uncommitted next tick accepted")
	_expect(rules.request_cast(world.tick, "piercing_arrow", 99, Vector2.RIGHT, targets).reason == "target_invalid", "invalid target rejection changed")
	var interrupted := rules.interrupt_action(world.tick, "test")
	_expect(interrupted.action_instance_id == 1 and stream.latest("action_interrupted").action_instance_id == 1, "interruption lost stable action id")
	for index: int in range(9): _step([])
	var buffered := rules.request_cast(world.tick, "piercing_arrow", 7, Vector2.RIGHT, targets)
	_expect(buffered.accepted and buffered.status == "buffered" and buffered.request_id == 2, "attack cooldown buffer window changed")
	for index: int in range(4): step = _step([])
	_expect(step.player.attack_cooldown_ticks == 13 and step.player.timeline.active.action_instance_id == 2, "buffered start did not own cooldown/id")
	var impact_events: Array[Dictionary] = []
	for index: int in range(5):
		step = _step([])
		impact_events.append_array(step.action_events)
	var impacts := impact_events.filter(func(event: Dictionary) -> bool: return event.type == "action_impact")
	_expect(impacts.size() == 1 and impacts[0].action_instance_id == 2, "timeline release was not delivered exactly once")
	_expect(stream.latest("action_impact").is_empty(), "timeline release was incorrectly emitted as world hit")
	var damage := rules.apply_damage(world.tick, 12.3456, "enemy/7/slash", Vector2(50, 0))
	_expect(damage.accepted and state.snapshot(world.tick).player_health == 87.654, "health damage rounding changed")
	_expect(damage.events[0].target_id == "ranger" and damage.events[0].target_entity_id == 0, "damage target identity changed")
	_expect(damage.events[0].event_id > accepted.event_id, "shared stream event ids not monotonic")
	_expect(rules.apply_damage(world.tick - 1, 10, "enemy/7/slash", Vector2.ZERO).reason == "uncommitted_world_tick", "stale damage mutated player")
	step = _step([Protocol.dodge(world.tick + 1, "ranger", 2, 0, -1000)])
	_expect(step.player.dodge_remaining_ticks == 5 and step.player.dodge_cooldown_ticks == 28, "dodge duration/reduction changed")
	_expect(rules.apply_damage(world.tick, 500, "enemy/7/slash", Vector2.ZERO).reason == "dodge_invulnerable", "dodge lost invulnerability")
	_expect(rules.request_cast(world.tick, "dash").reason == "mobility_conflict", "dash/dodge conflict changed")
	for index: int in range(5): _step([])
	_expect(rules.apply_damage(world.tick, 500, "enemy/7/slash", Vector2.ZERO).events.size() == 2, "lethal damage did not emit damage/death")
	_expect(rules.request_cast(world.tick, "hunter_mark", 7, Vector2.ZERO, targets).reason == "player_dead", "dead player cast accepted")
	_reset({"three_skill_rhythm_windup_ticks": 2, "lost_mark_candidate_ticks": 3, "first_critical_bonus_generations": 2, "expiry_payload_retention": 0.5})
	rules.advance_three_skill_sequence("piercing_arrow")
	step = _step([Protocol.cast(1, "ranger", 1, "hunter_mark", 7)])
	_expect(step.player.marked_entity_id == 7 and step.player.hunter_mark_expires_tick == 181, "mark duration changed")
	_expect(rules.request_cast(world.tick, "hunter_mark", 7, Vector2.ZERO, targets).reason == "cooldown_active", "mark cooldown rejection changed")
	step = _step([Protocol.cast(2, "ranger", 2, "dash", 0, 1000, 0)])
	_expect(step.player.three_skill_bonus_ready and step.player.three_skill_sequence_stage == 3, "three-skill rhythm did not advance on mark/dash")
	var rhythm := rules.request_cast(world.tick, "piercing_arrow", 7, Vector2.RIGHT, targets)
	_expect(rhythm.accepted and state.snapshot(world.tick).timeline.active.windup_ticks == 2 and not state.snapshot(world.tick).three_skill_bonus_ready, "rhythm bonus was not consumed into frozen windup")
	_expect(rules.consume_first_critical_bonus() == 2 and rules.consume_first_critical_bonus() == 0, "first critical bonus not consumed once")
	rules.retain_missed_arrow(Big.from_float(40), 20)
	var retained := rules.take_retained_arrow()
	_expect(retained.aggregate.compare(Big.from_float(20)) == 0 and retained.ordinary == 10 and rules.take_retained_arrow().aggregate.is_zero(), "retained payload not owned/consumed by domain")
	targets[0].position = Vector2(1000, 0)
	step = _step([])
	_expect(step.player.marked_entity_id == 0 and step.player.hunter_mark_candidate_entity_id == 7, "lost mark candidate transition changed")
	for index: int in range(4): step = _step([])
	_expect(step.player.hunter_mark_candidate_entity_id == 0, "mark candidate did not expire after window")
	_reset({})
	# Dash started in the routed tick traverses the complete authored 180 units.
	_step([Protocol.cast(1, "ranger", 1, "dash", 0, 1000, 0)])
	for index: int in range(5): _step([])
	_expect(is_equal_approx(state.position().x, 180.0), "dash total displacement changed")
	_step([])
	_expect(stream.latest("displacement_ended").actual_to == Vector2(180, 0), "dash end position changed")
	_reset({})
	_step([Protocol.dodge(1, "ranger", 1, 1000, 0)])
	_step([])
	_step([])
	step = _step([Protocol.cast(4, "ranger", 19, "dash", 0, 0, -1000)])
	_expect(step.receipts[0].status == "buffered" and step.receipts[0].reason == "mobility_buffered", "late mobility conflict was not buffered")
	_step([])
	step = _step([])
	_expect(step.receipts[0].accepted and step.receipts[0].command.sequence == 19 and step.receipts[0].command.tick == world.tick, "buffered mobility changed its stable command id or used a fabricated motor tick")
	_expect(step.player.mobility_input_buffer.is_empty() and step.player.dash_direction == Vector2.UP, "ready mobility buffer was not consumed")
	_reset({})
	var unready := rules.request_cast(world.tick, "dash", 0, Vector2(NAN, 0))
	_expect(unready.reason == "invalid_aim_direction" and state.snapshot(world.tick).dash_remaining_ticks == 0, "invalid mobility aim mutated domain")
	world.step_tick()
	count = stream.latest_event_id()
	_expect(rules.advance_tick(world.tick, {"movement": Vector2(NAN, 0)}, targets).error == "invalid_motion", "invalid routed motion accepted")
	_expect(stream.latest_event_id() == count and access.actor("ranger").last_movement_tick == -1, "invalid routed motion emitted events or committed motor")
	_expect(rules.advance_tick(world.tick, {}, targets).ok, "rejected malformed tick prevented valid retry")
	# Pre-existing registry motion rejects before any counters or events change.
	_reset({})
	world.step_tick()
	access.move_actor("ranger", Vector2.ONE, world.tick)
	count = stream.latest_event_id()
	_expect(rules.advance_tick(world.tick, {}, targets).error == "non_monotonic_motor_tick", "rules bypassed existing registry motor submission")
	_expect(stream.latest_event_id() == count and state.snapshot(world.tick).attack_cooldown_ticks == 0, "rejected motor tick mutated player rules")
	_reset({})
	state.reset_for_room({}, access, "ranger", world.tick)
	rules.configure(state, world, stream)
	_expect(rules.request_cast(world.tick, "dash").reason == "ability_not_equipped" and rules.request_cast(world.tick, "hunter_mark", 7, Vector2.ZERO, targets).reason == "ability_not_equipped", "unequipped skills were accepted")
	targets[0].position = Vector2(1000, 0)
	_expect(rules.request_cast(world.tick, "piercing_arrow", 7, Vector2.RIGHT, targets).reason == "target_out_of_range", "attack range rejection changed")
	_reset({})
	_step([Protocol.cast(1, "ranger", 1, "hunter_mark", 7)])
	for index: int in range(174): _step([])
	_step([Protocol.cast(176, "ranger", 2, "piercing_arrow", 7, 1000, 0)])
	for index: int in range(5): step = _step([])
	_expect(world.tick == 181 and step.player.marked_entity_id == 0, "mark expiry tick changed")
	var boundary_batch: Dictionary = step.action_batches[0]
	_expect(boundary_batch.player.marked_entity_id == 7 and boundary_batch.events[0].type == "action_impact", "release-before-mark-update context was lost at exact expiry tick")
	_test_release_input()
	# Explicit harness teardown: sever the kernel -> port -> access -> registry
	# borrow cycle so the room graph frees at exit.
	if world != null and world.kernel != null:
		world.kernel.shutdown()
	for failure: String in failures: printerr("FAIL: " + failure)
	if failures.is_empty(): print("PLAYER_COMBAT_RULES_PASS")
	quit(0 if failures.is_empty() else 1)


func _test_release_input() -> void:
	var unconfigured := Rules.new().release_input(0)
	_expect(not unconfigured.ok and unconfigured.error == "player_rules_not_configured" and not unconfigured.cleared, "unconfigured input release was accepted")
	for initial_kind: String in ["dodge", "dash"]:
		for release: bool in [false, true]:
			_reset({"mobility_preserves_mark_and_lineage": true})
			_step([Protocol.cast(1, "ranger", 10, "piercing_arrow", 7, 1000, 0)])
			var initial := Protocol.dodge(2, "ranger", 11, 0, 1000) if initial_kind == "dodge" else Protocol.cast(2, "ranger", 11, "dash", 0, 0, 1000)
			_step([initial])
			var duration := 5 if initial_kind == "dodge" else 6
			for index: int in range(duration - 3): _step([])
			var queued_kind := "dash" if initial_kind == "dodge" else "dodge"
			var command := Protocol.cast(world.tick + 1, "ranger", 12, "dash", 0, -1000, 0) if queued_kind == "dash" else Protocol.dodge(world.tick + 1, "ranger", 12, -1000, 0)
			world.step_tick()
			var routed := Protocol.arbitrate([command], world.tick, state.equipped_ability_ids())
			var tail := rules.advance_tick(world.tick, routed, targets)
			_expect(tail.ok and tail.receipts[0].reason == "mobility_buffered", "tail did not buffer " + queued_kind)
			var before := _release_observation()
			var previous_receipts: Array = tail.protocol_receipts.duplicate(true)
			var previous_command := command.duplicate(true)
			_expect(not (before.player.timeline.active as Dictionary).is_empty(), "release fixture lost active attack")
			for invalid_tick: int in [world.tick - 1, world.tick + 1]:
				var invalid := rules.release_input(invalid_tick)
				_expect(not invalid.ok and invalid.error == "uncommitted_world_tick" and not invalid.cleared, "invalid release tick did not explicitly fail")
				_expect(_release_observation() == before, "invalid release changed domain/world/registry/stream")
			if release:
				_expect(rules.release_input(world.tick) == {"ok": true, "error": "", "cleared": true}, "buffered input release failed")
				var expected := before.duplicate(true)
				expected.player.mobility_input_buffer = {}
				_expect(_release_observation() == expected, "release changed state beyond mobility buffer")
				_expect(rules.release_input(world.tick) == {"ok": true, "error": "", "cleared": false}, "repeated release was not idempotent")
				_expect(_release_observation() == expected, "repeated release changed state or generated an event")
				_expect(tail.protocol_receipts == previous_receipts and command == previous_command, "release changed existing protocol receipts or command sequence")
			_step([])
			var consumed := _step([])
			_expect(world.tick == 2 + duration, "buffer consume used a fabricated tick")
			if release:
				_expect(consumed.receipts.is_empty() and consumed.protocol_receipts.is_empty(), "released buffer emitted a command/receipt on consume tick")
				_expect(int(consumed.player[queued_kind + "_remaining_ticks"]) == 0 and int(consumed.player[queued_kind + "_started_tick"]) == -1, "released buffer started " + queued_kind)
			else:
				_expect(consumed.receipts.size() == 1 and consumed.receipts[0].accepted and consumed.receipts[0].command.sequence == 12, "unreleased buffer did not start with original command sequence")
				_expect(int(consumed.player[queued_kind + "_remaining_ticks"]) > 0 and int(consumed.player[queued_kind + "_started_tick"]) == world.tick, "unreleased buffer did not start on real consume tick")
			_expect(consumed.player.timeline.active.action_instance_id == 1, "input release or buffered mobility changed active action identity")
			# A world tick is real but cannot release input before its player phase.
			world.step_tick()
			var unprepared_before := _release_observation()
			var unprepared := rules.release_input(world.tick)
			_expect(not unprepared.ok and unprepared.error == "player_tick_not_prepared" and not unprepared.cleared, "unprepared player tick accepted input release")
			_expect(_release_observation() == unprepared_before, "unprepared release changed state")
			_expect(rules.begin_tick(world.tick, targets).ok, "release fixture could not prepare next real tick")
			var prepared_before := _release_observation()
			_expect(rules.release_input(world.tick) == {"ok": true, "error": "", "cleared": false}, "prepared tick rejected empty input release")
			_expect(_release_observation() == prepared_before, "prepared input release changed executing state")
			_expect(rules.advance_tick(world.tick, {}, targets).ok, "input release prevented prepared tick from completing")


func _release_observation() -> Dictionary:
	var player := state.snapshot(world.tick)
	var retained: Big = player.retained_arrow_damage
	player.retained_arrow_damage = {"layer": retained.layer, "magnitude": retained.magnitude}
	return {"player": player, "world": {"tick": world.tick, "room_instance_id": world.room_instance_id, "world_revision": world.world_revision}, "registry": access.actor_snapshot("ranger"), "stream": stream.snapshot()}


func _reset(capabilities: Dictionary) -> void:
	_expect(world.configure("rules-room", 1, 30).ok, "rules world configuration failed")
	registry = world.actor_registry
	var static_build: Dictionary = StaticSpatialIndexScript.build({
		"schema_version": StaticSpatialIndexScript.SCHEMA_VERSION,
		"asset_id": "test/rules-room",
		"surfaces": [],
		"movement_boundary": {"kind": "rect", "rect": Rect2(-1000.0, -1000.0, 2000.0, 2000.0)},
	})
	_expect(bool(static_build.get("ok", false)), "rules static index configuration failed")
	var dynamic := DynamicSpatialIndexScript.new()
	var overlay := SpatialOverlayScript.new()
	var movement_build: Dictionary = MovementResolverScript.make(static_build.get("value"), overlay, dynamic)
	_expect(bool(movement_build.get("ok", false)), "rules movement resolver configuration failed")
	_expect(bool(access.configure(world, registry, static_build.get("value"), dynamic, movement_build.get("value"), overlay).get("ok", false)), "rules actor access configuration failed")
	spatial_port.bind(access)
	_expect(bool(access.register_actor("ranger", Vector2.ZERO, 14.0).get("ok", false)), "rules player registration failed")
	stream.reset()
	_expect(bool(state.reset_for_room({"final_parameters": {"max_health": 100.0, "d": 225.0}, "skills": ["piercing_arrow", "hunter_mark", "dash"], "talent_capabilities": capabilities}, access, "ranger", world.tick).get("ok", false)), "rules player reset failed")
	_expect(rules.configure(state, world, stream).ok, "rules configure failed")
	targets[0].position = Vector2(100, 0)


func _step(commands: Array) -> Dictionary:
	world.step_tick()
	var result := rules.advance_tick(world.tick, {"commands": commands}, targets)
	_expect(result.ok, "real tick failed: " + str(result.get("error", "")))
	return result


func _expect(condition: bool, message: String) -> void: Assert.expect(condition, message, failures)
