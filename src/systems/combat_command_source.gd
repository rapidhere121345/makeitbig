class_name CombatCommandSource
extends RefCounted

## Collects manual player intent for one fixed tick.
##
## This source owns only transient input edges and the translation from those
## edges to the public command schema. It never reads room authority, moves an
## actor, validates commands, or resolves an attack. Target snapshots, command
## factories and presentation feedback are supplied by callbacks so the source
## remains usable by a replay fixture without a scene tree.

const Timeline := preload("res://src/systems/player_action_timeline.gd")

const ATTACK_SOURCE_ASSISTED := "assisted"
const ATTACK_SOURCE_POINTER := "pointer"

var callbacks: Dictionary = {}
var dodge_requested := false
var attack_requested := false
var attack_requested_source := ""
var attack_requested_target_entity_id := 0
var attack_requested_pointer_gameplay := Vector2.ZERO
var hunter_mark_requested := false
var dash_requested := false


func configure(new_callbacks: Dictionary) -> void:
	callbacks = new_callbacks.duplicate()


func collect_manual_commands(intent: Dictionary) -> Array[Dictionary]:
	var commands: Array[Dictionary] = []
	var direction := (intent.get("movement", Vector2.ZERO) as Vector2)
	if direction != Vector2.ZERO:
		var move_command: Variant = _invoke("make_move", [direction, 1.0], {})
		if move_command is Dictionary and not (move_command as Dictionary).is_empty():
			commands.append(move_command as Dictionary)
	if dodge_requested:
		var dodge_command: Variant = _invoke("make_dodge", [direction if direction != Vector2.ZERO else _player_facing()], {})
		if dodge_command is Dictionary and not (dodge_command as Dictionary).is_empty():
			commands.append(dodge_command as Dictionary)
	dodge_requested = false
	if hunter_mark_requested:
		var mark_target := _nearest_target(_hunter_mark_range())
		var mark_id := int(mark_target.get("entity_id", 0)) if not mark_target.is_empty() else 0
		var mark_command: Variant = _invoke("make_cast", ["hunter_mark", mark_id, Vector2.ZERO], {})
		if mark_command is Dictionary and not (mark_command as Dictionary).is_empty():
			commands.append(mark_command as Dictionary)
	hunter_mark_requested = false
	if dash_requested:
		var dash_command: Variant = _invoke("make_cast", ["dash", 0, direction if direction != Vector2.ZERO else _player_facing()], {})
		if dash_command is Dictionary and not (dash_command as Dictionary).is_empty():
			commands.append(dash_command as Dictionary)
	dash_requested = false

	var held_source := String(intent.get("held_source", ""))
	var attack_source := attack_requested_source if attack_requested else held_source
	## A live world pointer owns targeting while it is held. A keyboard edge in
	## the same hold cannot silently replace the explicit entity lock with assist.
	if held_source == ATTACK_SOURCE_POINTER:
		attack_source = ATTACK_SOURCE_POINTER
	elif attack_source.is_empty() and attack_requested:
		attack_source = ATTACK_SOURCE_ASSISTED

	var attack_target := _target_for_attack(attack_source)
	var held_repeat_requested := not held_source.is_empty() \
		and held_source == attack_source \
		and bool(_invoke("held_attack_window_open", [attack_target], false))
	if (attack_requested and not attack_target.is_empty()) or held_repeat_requested:
		var player_position := _player_position()
		var target_position: Vector2 = attack_target.get("position", player_position)
		var attack_direction := player_position.direction_to(target_position)
		var attack_command: Variant = _invoke("make_cast", ["piercing_arrow", int(attack_target.get("entity_id", 0)), attack_direction], {})
		if attack_command is Dictionary and not (attack_command as Dictionary).is_empty():
			var command := attack_command as Dictionary
			_invoke("register_attack_source", [int(command.get("sequence", -1)), attack_source])
			commands.append(command)
		_invoke("clear_input_feedback")
	elif attack_requested and attack_source == ATTACK_SOURCE_ASSISTED:
		## Assisted input keeps its explicit rejected receipt when no legal target
		## exists. Pointer input never falls back to nearest-target aim.
		var rejected_command: Variant = _invoke("make_cast", ["piercing_arrow", 0, _player_facing()], {})
		if rejected_command is Dictionary and not (rejected_command as Dictionary).is_empty():
			var rejected := rejected_command as Dictionary
			_invoke("register_attack_source", [int(rejected.get("sequence", -1)), attack_source])
			commands.append(rejected)
		_invoke("show_assisted_rejection_feedback")
	_clear_attack_edge()
	return commands


func reset_intent() -> void:
	_clear_attack_edge()
	dodge_requested = false
	hunter_mark_requested = false
	dash_requested = false


func _target_for_attack(attack_source: String) -> Dictionary:
	if attack_source == ATTACK_SOURCE_POINTER:
		var requested_id := attack_requested_target_entity_id if attack_requested_source == ATTACK_SOURCE_POINTER else int(_invoke("pointer_target_entity_id", [], 0))
		var target := _target_by_id(requested_id)
		if requested_id == int(_invoke("pointer_target_entity_id", [], 0)) and requested_id > 0:
			_invoke("refresh_pointer_lock")
		if target.is_empty() or float(target.get("health", 0.0)) <= 0.0:
			if int(_invoke("pointer_target_entity_id", [], 0)) > 0:
				_invoke("mark_pointer_lost")
			return {}
		if _player_position().distance_to(target.get("position", Vector2.ZERO)) > _locked_targeting_distance():
			if requested_id == int(_invoke("pointer_target_entity_id", [], 0)):
				_invoke("mark_pointer_out_of_range")
			return {}
		return target
	return _preferred_target()


func _nearest_target(maximum_distance: float) -> Dictionary:
	var value: Variant = _invoke("nearest_target", [maximum_distance], {})
	return value as Dictionary if value is Dictionary else {}


func _preferred_target() -> Dictionary:
	var value: Variant = _invoke("preferred_target", [], {})
	return value as Dictionary if value is Dictionary else {}


func _target_by_id(entity_id: int) -> Dictionary:
	var value: Variant = _invoke("target_by_id", [entity_id], {})
	return value as Dictionary if value is Dictionary else {}


func _player_position() -> Vector2:
	var value: Variant = _invoke("player_position", [], Vector2.ZERO)
	return value as Vector2 if value is Vector2 else Vector2.ZERO


func _player_facing() -> Vector2:
	var value: Variant = _invoke("player_facing", [], Vector2.RIGHT)
	return value as Vector2 if value is Vector2 else Vector2.RIGHT


func _locked_targeting_distance() -> float:
	return float(_invoke("locked_targeting_distance", [], 0.0))


func _hunter_mark_range() -> float:
	return float(_invoke("hunter_mark_range", [], 0.0))


func _clear_attack_edge() -> void:
	attack_requested = false
	attack_requested_source = ""
	attack_requested_target_entity_id = 0
	attack_requested_pointer_gameplay = Vector2.ZERO


func _invoke(name: String, arguments: Array = [], fallback: Variant = null) -> Variant:
	var callback_value: Variant = callbacks.get(name, Callable())
	if callback_value is Callable and (callback_value as Callable).is_valid():
		return (callback_value as Callable).callv(arguments)
	return fallback


## Gameplay eligibility shared by held-device intent. This uses only timeline
## values and never asks the HUD, animation, render clock or scene tree.
static func request_window_open(tick: int, cooldown: int, timeline: Dictionary) -> bool:
	var buffered: Dictionary = timeline.get("buffered", {})
	if not buffered.is_empty():
		return false
	var active: Dictionary = timeline.get("active", {})
	var lock_clear_tick := tick
	if not active.is_empty():
		lock_clear_tick = int(active.get("start_tick", tick)) + int(active.get("windup_ticks", Timeline.WINDUP_TICKS)) + Timeline.RECOVERY_TICKS
	var eligible := maxi(tick, maxi(tick + cooldown, lock_clear_tick))
	return eligible - tick <= Timeline.INPUT_BUFFER_TICKS
