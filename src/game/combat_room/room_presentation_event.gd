class_name RoomPresentationEvent
extends RefCounted

## One presentation-facing effect produced while the room authority runs a
## fixed tick. The session appends these to its event log in the order they
## happen and the view applies them after the tick, so the authority never
## writes presentation state and never reads it back. Records are plain values;
## use the static constructors below.

enum Kind {
	## Transient input hint text (text, tick).
	INPUT_FEEDBACK,
	## An accepted or refused Piercing Arrow command receipt.
	CAST_RECEIPT,
	## A non-arrow command left the pipeline (sequence).
	COMMAND_DISCARDED,
	## An action instance started consuming a request (action_id, request_id).
	ACTION_REQUEST_BOUND,
	## An action instance ended or was interrupted (action_id).
	ACTION_FORGOTTEN,
	## An attack request was erased (request_id).
	REQUEST_FORGOTTEN,
	## Arrow impact sparks (position, direction, generations).
	IMPACT_TRACE,
	## A killed enemy's detached death visual (visual).
	CORPSE_DETACHED,
}

var kind: Kind = Kind.INPUT_FEEDBACK
var tick: int = 0
var text: String = ""
var sequence: int = -1
## Attack source for a cast receipt. When `resolve_source` is set this is only
## the fallback and the view substitutes the source its input adapter
## registered for `sequence`.
var source: String = ""
var resolve_source: bool = false
var accepted: bool = false
var started: bool = false
## A refused cast that may show the out-of-range hint (Manual mode only).
var out_of_range_hint: bool = false
var request_id: int = 0
var replaced_request_id: int = 0
var action_id: int = 0
var position: Vector2 = Vector2.ZERO
var direction: Vector2 = Vector2.ZERO
var generations: int = 0
var visual: Dictionary = {}


static func input_feedback(feedback_text: String, at_tick: int) -> RoomPresentationEvent:
	var event := RoomPresentationEvent.new()
	event.kind = Kind.INPUT_FEEDBACK
	event.text = feedback_text
	event.tick = at_tick
	return event


static func cast_receipt(at_tick: int, command_sequence: int, attack_source: String, resolve_command_source: bool,
		was_accepted: bool, was_started: bool, hint_out_of_range: bool, accepted_request_id: int,
		replaced_id: int, started_action_id: int) -> RoomPresentationEvent:
	var event := RoomPresentationEvent.new()
	event.kind = Kind.CAST_RECEIPT
	event.tick = at_tick
	event.sequence = command_sequence
	event.source = attack_source
	event.resolve_source = resolve_command_source
	event.accepted = was_accepted
	event.started = was_started
	event.out_of_range_hint = hint_out_of_range
	event.request_id = accepted_request_id
	event.replaced_request_id = replaced_id
	event.action_id = started_action_id
	return event


static func command_discarded(command_sequence: int) -> RoomPresentationEvent:
	var event := RoomPresentationEvent.new()
	event.kind = Kind.COMMAND_DISCARDED
	event.sequence = command_sequence
	return event


static func action_request_bound(bound_action_id: int, bound_request_id: int) -> RoomPresentationEvent:
	var event := RoomPresentationEvent.new()
	event.kind = Kind.ACTION_REQUEST_BOUND
	event.action_id = bound_action_id
	event.request_id = bound_request_id
	return event


static func action_forgotten(ended_action_id: int) -> RoomPresentationEvent:
	var event := RoomPresentationEvent.new()
	event.kind = Kind.ACTION_FORGOTTEN
	event.action_id = ended_action_id
	return event


static func request_forgotten(erased_request_id: int) -> RoomPresentationEvent:
	var event := RoomPresentationEvent.new()
	event.kind = Kind.REQUEST_FORGOTTEN
	event.request_id = erased_request_id
	return event


static func impact_trace(contact_point: Vector2, aim: Vector2, trace_generations: int) -> RoomPresentationEvent:
	var event := RoomPresentationEvent.new()
	event.kind = Kind.IMPACT_TRACE
	event.position = contact_point
	event.direction = aim
	event.generations = trace_generations
	return event


static func corpse_detached(corpse_visual: Dictionary) -> RoomPresentationEvent:
	var event := RoomPresentationEvent.new()
	event.kind = Kind.CORPSE_DETACHED
	event.visual = corpse_visual
	return event
