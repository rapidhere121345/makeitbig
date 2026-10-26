class_name SceneRouter
extends RefCounted

signal route_changed(previous_route, current_route, payload)

const ROUTE_BOOT: String = "boot"
const CoreResult := preload("res://src/core/result.gd")
const ROUTE_TITLE: String = "title"
const ROUTE_TUTORIAL: String = "tutorial"
const ROUTE_BASE: String = "base"
const ROUTE_CHARACTER: String = "character"
const ROUTE_STORY: String = "story"
const ROUTE_LOADOUT: String = "loadout"
const ROUTE_FORGE: String = "forge"
const ROUTE_TRAINING: String = "training"
const ROUTE_PROXY: String = "proxy"
const ROUTE_IMMORTALITY: String = "immortality"
const ROUTE_RESEARCH: String = "research"
const ROUTE_CONTRACT: String = "contract"
const ROUTE_ARENA: String = "arena"
const ROUTE_RESULT: String = "result"
const ROUTE_ENDING: String = "ending"

const ERROR_UNKNOWN_ROUTE: String = "unknown_route"
const ERROR_REQUEST_PENDING: String = "request_pending"
const ERROR_TRANSITION_NOT_ALLOWED: String = "transition_not_allowed"
const ERROR_NO_PENDING: String = "no_pending"

const _ALLOWED_TRANSITIONS: Dictionary = {
	ROUTE_BOOT: [ROUTE_TITLE, ROUTE_TUTORIAL, ROUTE_BASE],
	ROUTE_TITLE: [ROUTE_TUTORIAL, ROUTE_BASE],
	ROUTE_TUTORIAL: [ROUTE_BASE, ROUTE_TITLE],
	ROUTE_BASE: [ROUTE_CHARACTER, ROUTE_STORY, ROUTE_CONTRACT, ROUTE_LOADOUT, ROUTE_FORGE, ROUTE_TRAINING, ROUTE_PROXY, ROUTE_IMMORTALITY, ROUTE_TITLE],
	ROUTE_CHARACTER: [ROUTE_BASE],
	ROUTE_STORY: [ROUTE_BASE],
	ROUTE_LOADOUT: [ROUTE_BASE, ROUTE_RESEARCH, ROUTE_RESULT],
	ROUTE_FORGE: [ROUTE_BASE],
	ROUTE_TRAINING: [ROUTE_BASE, ROUTE_RESEARCH],
	ROUTE_PROXY: [ROUTE_BASE],
	ROUTE_IMMORTALITY: [ROUTE_BASE],
	ROUTE_RESEARCH: [ROUTE_BASE, ROUTE_LOADOUT, ROUTE_TRAINING],
	ROUTE_CONTRACT: [ROUTE_ARENA, ROUTE_BASE],
	ROUTE_ARENA: [ROUTE_RESULT],
	ROUTE_RESULT: [ROUTE_BASE, ROUTE_LOADOUT, ROUTE_ENDING],
	ROUTE_ENDING: [ROUTE_BASE, ROUTE_TITLE],
}

var current_route: String = ROUTE_BOOT
var pending_route: String = ""
var pending_payload: Dictionary:
	get:
		return _pending_payload.duplicate(true)
var history: Array:
	get:
		return _history.duplicate(true)

var _pending_payload: Dictionary = {}
var _history: Array[Dictionary] = []


func is_known_route(route: String) -> bool:
	return _ALLOWED_TRANSITIONS.has(route)


func can_transition(from_route: String, to_route: String = "") -> bool:
	if to_route.is_empty():
		to_route = from_route
		from_route = current_route
	if not is_known_route(from_route) or not is_known_route(to_route):
		return false
	return to_route in _ALLOWED_TRANSITIONS[from_route]


func request(route: String, payload: Dictionary = {}) -> Dictionary:
	if not is_known_route(route):
		return CoreResult.failure(ERROR_UNKNOWN_ROUTE)
	if has_pending():
		return CoreResult.failure(ERROR_REQUEST_PENDING)
	if route == current_route:
		return {"ok": true, "noop": true, "route": current_route}
	if not can_transition(current_route, route):
		return CoreResult.failure(ERROR_TRANSITION_NOT_ALLOWED)
	pending_route = route
	_pending_payload = payload.duplicate(true)
	return {"ok": true, "noop": false, "route": route}


func has_pending() -> bool:
	return not pending_route.is_empty()


func commit() -> Dictionary:
	if not has_pending():
		return CoreResult.failure(ERROR_NO_PENDING)

	var previous_route := current_route
	var next_route := pending_route
	var committed_payload: Dictionary = _pending_payload.duplicate(true)
	current_route = next_route
	pending_route = ""
	_pending_payload = {}
	_history.append({
		"previous_route": previous_route,
		"current_route": current_route,
		"payload": committed_payload.duplicate(true),
	})

	var result := {
		"ok": true,
		"previous_route": previous_route,
		"current_route": current_route,
		"payload": committed_payload.duplicate(true),
	}
	route_changed.emit(previous_route, current_route, committed_payload.duplicate(true))
	return result


func cancel() -> void:
	pending_route = ""
	_pending_payload = {}


func reset(initial_route: String = ROUTE_BOOT) -> Dictionary:
	if not is_known_route(initial_route):
		return CoreResult.failure(ERROR_UNKNOWN_ROUTE)
	current_route = initial_route
	pending_route = ""
	_pending_payload = {}
	_history.clear()
	return {"ok": true, "route": current_route}

