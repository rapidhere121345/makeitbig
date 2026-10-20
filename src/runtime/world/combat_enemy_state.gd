class_name CombatEnemyState
extends RefCounted

const StatusEffectLedgerScript := preload("res://src/game/status_effect_ledger.gd")

## Mutable room-local enemy state.
##
## Combat systems own transitions that mutate this record. Presentation reads
## it through the room snapshot; the state model has no drawing, input, or
## scene-tree dependency.

var entity_id: int = 0
var kind_id: String = "melee_pursuer"
var position: Vector2
var health: float
var maximum_health: float
var is_boss: bool
var facing: Vector2 = Vector2.RIGHT
var motion_state: String = "idle"
var action_state: String = "none"
var state_started_tick: int = 0
var state_ends_tick: int = 0
var impact_tick: int = -1
var impact_resolved: bool = false
var hit_flash_until_tick: int = 0
var death_started_tick: int = -1
var charge_origin: Vector2 = Vector2.ZERO
var charge_direction: Vector2 = Vector2.RIGHT
var charge_length: float = 0.0
var charge_width: float = 0.0
var fan_origin: Vector2 = Vector2.ZERO
var fan_direction: Vector2 = Vector2.RIGHT
var fan_half_angle: float = 0.0
var fan_radius: float = 0.0
var phase_id: String = "sealed"
var phase_state: String = "stable"
var action_id: String = "none"
var action_instance_id: int = 0
var core_open: bool = false
var core_vulnerable: bool = false
var left_hand_position: Vector2 = Vector2.ZERO
var right_hand_position: Vector2 = Vector2.ZERO
## target_shape is the outgoing hostile attack, never an incoming hurtbox.
var target_shape: Dictionary = {}
## Each pose is a local offset from position. IDs are domain values, not Nodes.
var parts: Array[Dictionary] = []
var _pending_part_changes: Array[Dictionary] = []
var next_action_index: int = 0
var tactic_state: String = "idle"
var tactic_reason: String = "spawned"
var next_action_ready_tick: int = 0
## Consecutive move-intent ticks without ~24u of net progress. The tactic
## planner re-slots a stuck enemy to its own side of the room instead of
## grinding a fixed ring slot that sits behind the hole or a blocker.
var stuck_ticks: int = 0
var stuck_anchor: Vector2 = Vector2.INF
var _status_effects: RefCounted = StatusEffectLedgerScript.new()


func _init(
	spawn_position: Vector2,
	hp: float,
	boss: bool = false,
	stable_id: int = 0,
	enemy_kind: String = "melee_pursuer"
) -> void:
	entity_id = stable_id
	kind_id = enemy_kind
	position = spawn_position
	health = hp
	maximum_health = hp
	is_boss = boss
	_status_effects.reset()
	left_hand_position = spawn_position + Vector2(-34.0, 0.0)
	right_hand_position = spawn_position + Vector2(34.0, 0.0)

	if boss:
		# One shared damage group preserves one payload per arrow for the colossus.
		# The hands follow the same authoritative poses used by encounter/presentation.
		parts = [
			{"part_id": "head", "pose": Vector2(0.0, -74.0), "hurtbox": {"type": "circle", "radius": 56.0}, "damage_group_id": "body", "broken": false, "active": true},
			{"part_id": "left_hand", "pose": Vector2.ZERO, "pose_source": "left_hand", "hurtbox": {"type": "circle", "radius": 24.0}, "damage_group_id": "body", "broken": false, "active": true},
			{"part_id": "right_hand", "pose": Vector2.ZERO, "pose_source": "right_hand", "hurtbox": {"type": "circle", "radius": 24.0}, "damage_group_id": "body", "broken": false, "active": true},
		]


func apply_status_effect(
	tick: int,
	effect_id: String,
	source_id: String,
	duration_ticks: int,
	magnitude: float,
	stack_policy: String = "replace",
	max_stacks: int = 1,
	modifier: Dictionary = {}
) -> Dictionary:
	return _status_effects.apply(tick, effect_id, source_id, duration_ticks, magnitude, stack_policy, max_stacks, modifier)


func advance_status_effects(tick: int) -> Dictionary:
	return _status_effects.advance(tick)


func remove_status_effect(tick: int, effect_id: String) -> Dictionary:
	return _status_effects.remove(tick, effect_id)


func status_effects_snapshot(tick: int = -1) -> Dictionary:
	return _status_effects.snapshot(tick)


func hurtbox_parts() -> Array[Dictionary]:
	var result: Array[Dictionary] = parts.duplicate(true)
	for part: Dictionary in result:
		match String(part.get("pose_source", "")):
			"left_hand":
				part["pose"] = left_hand_position - position
			"right_hand":
				part["pose"] = right_hand_position - position
	return result


## Detached replay observation. Sort independent part IDs, but preserve queued
## transitions within each part: commit applies those changes in request order.
func gameplay_parts_snapshot() -> Dictionary:
	var ordered: Array[Dictionary] = parts.duplicate(true)
	ordered.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return String(left.part_id) < String(right.part_id))
	var resolved: Dictionary = {}
	for part: Dictionary in hurtbox_parts():
		resolved[String(part.part_id)] = part.pose
	for part: Dictionary in ordered:
		part["resolved_pose"] = resolved[String(part.part_id)]
	var by_part: Dictionary = {}
	for change: Dictionary in _pending_part_changes:
		var id := String(change.part_id)
		if not by_part.has(id):
			by_part[id] = []
		by_part[id].append({"active": bool(change.active), "broken": bool(change.broken)})
	var ids: Array = by_part.keys()
	ids.sort()
	var pending: Array[Dictionary] = []
	for id: String in ids:
		pending.append({"part_id": id, "changes": by_part[id].duplicate(true)})
	return {"parts": ordered, "pending_part_transitions": pending}


## Queue transitions during contact iteration; never remove a part mid-query.
func queue_part_state(part_id: String, active: bool, broken: bool) -> Dictionary:
	for part: Dictionary in parts:
		if String(part.get("part_id", "")) == part_id:
			_pending_part_changes.append({"part_id": part_id, "active": active, "broken": broken})
			return {"ok": true, "error": ""}
	return {"ok": false, "error": "unknown_part_id"}


func commit_part_states() -> void:
	for change: Dictionary in _pending_part_changes:
		for part: Dictionary in parts:
			if part.get("part_id") == change.part_id:
				part["active"] = change.active
				part["broken"] = change.broken
	_pending_part_changes.clear()
