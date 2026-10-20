class_name CombatSimulation
extends RefCounted

## Fixed-tick authority seam.
##
## CombatSimulation owns the one production submission of a room's fixed tick.
## SimulationWorld/SimKernel owns the kernel pipeline and publishes one detached
## snapshot. The room-domain owner consumes that snapshot and runs its room
## phases after publication. It may stage work for the next kernel tick, but it
## never submits a second authority tick.
const Rules := preload("res://src/systems/player_combat_rules.gd")
const CombatPhasePortScript := preload("res://src/runtime/combat/combat_phase_port.gd")

## This is the typed method boundary between the kernel tick and the mounted
## room domain. It is deliberately an object contract, rather than a Dictionary
## of Callables: production cannot silently add or replace a phase callback.
const KERNEL_AUTHORITY_ID: StringName = &"combat_simulation"

## Names used by the seam trace. The kernel's own exact ten-phase trace remains
## on SimSnapshot.phase_trace; this trace records the cross-domain ordering.
const AUTHORITY_PHASES: Array[String] = [
	"kernel.tick.begin",
	"kernel.tick.submitted",
	"kernel.snapshot.published",
	"room.elapsed",
	"room.targets.pre",
	"player.begin",
	"room.player.pre",
	"room.reconcile",
	"room.hazard.refresh",
	"room.commands.collect",
	"room.commands.route",
	"room.targets.post",
	"player.advance",
	"room.player.post",
	"room.encounter",
	"room.projectiles",
	"room.hazard.resolve",
	"room.battle.end",
	"room.timeout",
]

var _world
var _rules: Rules
var phase_owner: CombatPhasePort = null

## Public seam evidence consumed by mounted production tests and diagnostics.
var last_authority_trace: Array[String] = []
var last_kernel_snapshot = null
var last_kernel_tick_submissions: int = 0
var total_kernel_tick_submissions: int = 0
var last_kernel_tick: int = -1
var last_room_reconcile_tick: int = -1

var _last_authority_tick: int = -1
var _step_in_progress: bool = false


func configure(world, player_rules: Rules, room_domain) -> Dictionary:
	if world == null or player_rules == null or int(world.tick_rate) != 30:
		return {"ok": false, "error": "simulation_dependencies_unavailable"}
	if not world.has_method("step_tick") or not world.has_method("latest_snapshot"):
		return {"ok": false, "error": "kernel_tick_authority_unavailable"}
	if room_domain == null or not room_domain is CombatPhasePortScript or not is_instance_valid(room_domain):
		return {"ok": false, "error": "room_phase_owner_unavailable"}
	var typed_phase_port: CombatPhasePort = room_domain
	if not bool(typed_phase_port.is_ready()):
		return {"ok": false, "error": "room_phase_owner_unavailable"}
	_world = world
	_rules = player_rules
	phase_owner = typed_phase_port
	_last_authority_tick = int(_world.tick)
	last_authority_trace.clear()
	last_kernel_snapshot = _world.latest_snapshot()
	last_kernel_tick_submissions = 0
	total_kernel_tick_submissions = 0
	last_kernel_tick = int(_world.tick)
	last_room_reconcile_tick = -1
	_step_in_progress = false
	return {"ok": true, "error": ""}


func is_configured() -> bool:
	return _world != null and _rules != null and phase_owner != null


func phase_owner_id() -> StringName:
	return &"room_domain"


## Runs exactly one authority tick. The kernel submission is intentionally the
## first operation; every room phase below observes its published snapshot and
## can only stage work for a later kernel submission.
func step() -> Dictionary:
	if not is_configured():
		return {"ok": false, "error": "simulation_not_configured"}
	if not phase_owner.is_ready():
		return {"ok": false, "error": "room_phase_owner_unavailable"}
	if _step_in_progress:
		return {"ok": false, "error": "fixed_tick_reentrant"}
	# A direct production call to SimulationWorld.step_tick() would move the
	# clock past our last completed authority. Fail closed instead of submitting
	# a second tick or reconciling a tick we did not own.
	if int(_world.tick) != _last_authority_tick:
		return {"ok": false, "error": "kernel_tick_advanced_outside_authority", "tick": int(_world.tick)}

	_step_in_progress = true
	last_authority_trace.clear()
	last_kernel_tick_submissions = 0
	_trace("kernel.tick.begin")
	var expected_tick := int(_world.tick) + 1
	var world_step = _world.step_tick()
	last_kernel_tick_submissions += 1
	total_kernel_tick_submissions += 1
	if world_step == null or not bool(world_step.ok):
		_step_in_progress = false
		return {
			"ok": false,
			"error": String(world_step.error) if world_step != null else "kernel_tick_failed",
			"tick": int(_world.tick),
			"phase_trace": last_authority_trace.duplicate(),
		}
	if int(_world.tick) != expected_tick:
		_step_in_progress = false
		return _authority_failure("kernel_tick_commit_mismatch", int(_world.tick))

	var tick := int(_world.tick)
	var snapshot = world_step.value if world_step.value != null else _world.latest_snapshot()
	if snapshot == null or not snapshot.has_method("sha256_hex") or int(snapshot.tick) != tick:
		_step_in_progress = false
		return _authority_failure("kernel_snapshot_unavailable", tick)
	last_kernel_snapshot = snapshot
	last_kernel_tick = tick
	_last_authority_tick = tick
	_trace("kernel.tick.submitted")
	_trace("kernel.snapshot.published")

	_trace("room.elapsed")
	phase_owner.set_elapsed(float(tick) / float(_world.tick_rate))
	_trace("room.targets.pre")
	var targets: Array[Dictionary] = _targets()
	_trace("player.begin")
	var prepared := _rules.begin_tick(tick, targets)
	if not bool(prepared.get("ok", false)):
		return _finish_failure(prepared)
	_trace("room.player.pre")
	phase_owner.consume_player_events(prepared)
	_trace("room.reconcile")
	phase_owner.update_room_rules()
	_trace("room.hazard.refresh")
	phase_owner.refresh_hazard_states()
	_trace("room.commands.collect")
	var commands: Array[Dictionary] = phase_owner.collect_commands()
	_trace("room.commands.route")
	var routed_value: Dictionary = phase_owner.route_commands(commands)
	if routed_value.is_empty():
		return _finish_failure({"ok": false, "error": "command_route_invalid", "tick": tick})
	_trace("room.targets.post")
	var post_targets: Array[Dictionary] = _targets()
	_trace("player.advance")
	var advanced := _rules.advance_tick(tick, routed_value, post_targets)
	if not bool(advanced.get("ok", false)):
		return _finish_failure(advanced)
	_trace("room.player.post")
	phase_owner.consume_player_events(advanced)
	_trace("room.encounter")
	## A finished room only keeps ticking for its loot window; survivors of a
	## victorious hunt must not keep fighting a locked-out ranger.
	if not phase_owner.room_terminal_locked():
		phase_owner.update_enemies()
	_trace("room.projectiles")
	phase_owner.advance_projectiles()
	_trace("room.hazard.resolve")
	phase_owner.resolve_hazard_hits()
	_trace("room.battle.end")
	phase_owner.check_battle_end()
	_trace("room.timeout")
	phase_owner.check_timeout()
	last_room_reconcile_tick = tick
	_step_in_progress = false
	return {
		"ok": true,
		"error": "",
		"tick": tick,
		"authority": KERNEL_AUTHORITY_ID,
		"phase_owner": phase_owner_id(),
		"kernel_tick_submissions": last_kernel_tick_submissions,
		"kernel_snapshot": snapshot,
		"world_step": {
			"tick": tick,
			"snapshot": snapshot,
			"phase_trace": snapshot.phase_trace.duplicate(),
		},
		"room_reconcile": {
			"tick": last_room_reconcile_tick,
			"after_kernel_snapshot": last_authority_trace.find("kernel.snapshot.published") < last_authority_trace.find("room.reconcile"),
		},
		"phase_trace": last_authority_trace.duplicate(),
		"player_step": advanced,
	}


func _targets() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for target: Dictionary in phase_owner.read_only_targets():
		result.append(target.duplicate(true))
	return result


func _trace(phase: String) -> void:
	last_authority_trace.append(phase)


func _finish_failure(result: Dictionary) -> Dictionary:
	_step_in_progress = false
	var value := result.duplicate(true)
	value["authority"] = KERNEL_AUTHORITY_ID
	value["kernel_tick_submissions"] = last_kernel_tick_submissions
	value["phase_trace"] = last_authority_trace.duplicate()
	return value


func _authority_failure(error: String, tick: int) -> Dictionary:
	return _finish_failure({
		"ok": false,
		"error": error,
		"tick": tick,
	})
