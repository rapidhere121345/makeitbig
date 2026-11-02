class_name MainPresentationEvents
extends RefCounted

## View-side consumer of the room session's event log. MainArena drains the
## session after every fixed tick and calls apply(), which replays the events
## into the presentation feedback and animation controllers in the order the
## authority produced them. This is the only place the tick's presentation
## effects are written, and the only place the per-command attack source is
## read from the input adapter's registry.

var _arena: MainArena


func _init(arena: MainArena) -> void:
	_arena = arena


func apply(events: Array[RoomPresentationEvent]) -> void:
	var presentation: Variant = _arena.presentation
	if presentation == null or presentation.feedback == null:
		return
	var feedback: Variant = presentation.feedback
	for event: RoomPresentationEvent in events:
		match event.kind:
			RoomPresentationEvent.Kind.INPUT_FEEDBACK:
				feedback.show_input_feedback(event.text, event.tick)
			RoomPresentationEvent.Kind.CAST_RECEIPT:
				var source := event.source
				if event.resolve_source:
					source = feedback.take_command_source(event.sequence, event.source)
				if event.accepted:
					feedback.remember_request_source(event.request_id, source, event.replaced_request_id)
					if event.started:
						feedback.bind_action_request(event.action_id, event.request_id)
				elif event.out_of_range_hint and source != MainArena.ATTACK_SOURCE_PROXY:
					feedback.show_input_feedback("Target out of range · Move closer to shoot", event.tick)
			RoomPresentationEvent.Kind.COMMAND_DISCARDED:
				feedback.discard_command(event.sequence)
			RoomPresentationEvent.Kind.ACTION_REQUEST_BOUND:
				feedback.bind_action_request(event.action_id, event.request_id)
			RoomPresentationEvent.Kind.ACTION_FORGOTTEN:
				feedback.forget_action(event.action_id)
			RoomPresentationEvent.Kind.REQUEST_FORGOTTEN:
				feedback.forget_request(event.request_id)
