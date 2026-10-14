class_name CombatFeedbackController
extends Node

## Cosmetic journal consumer. Only stable event ids are cursors; no node identity
## enters replay state. Notices, source labels, audio and traces live here and
## have no authority over commands, damage, positions or rewards.

const Audio := preload("res://src/presentation/combat_feedback_audio.gd")
const Trace := preload("res://src/runtime/world/combat_arrow_trace.gd")
const COMBAT_FEEDBACK_LIFETIME_SECONDS := 0.72
const COMBAT_FEEDBACK_LIMIT := 24
const INPUT_FEEDBACK_DURATION_TICKS := 54
const COMBAT_FEEDBACK_TEXT_LANES := {
	"enemy_damage": 0, "player_damage": 0,
	"blocked": 1, "miss": 1, "avoided": 1, "death": 2,
}

var enabled := true
var presentation_event_cursor := 0
var combat_feedback_marks: Array[Dictionary] = []
var traces: Array[CombatArrowTrace] = []
var combat_feedback_audio: Node
var attack_command_sources: Dictionary = {}
var attack_request_sources: Dictionary = {}
var attack_action_request_ids: Dictionary = {}
var _input_feedback_text := ""
var _input_feedback_expires_tick := -1


func load_assets() -> void:
	if enabled:
		combat_feedback_audio = Audio.new()
		add_child(combat_feedback_audio)


func reset() -> void:
	presentation_event_cursor = 0
	combat_feedback_marks.clear()
	traces.clear()
	reset_input()
	if combat_feedback_audio != null:
		combat_feedback_audio.reset_audio()


func reset_input() -> void:
	attack_command_sources.clear()
	attack_request_sources.clear()
	attack_action_request_ids.clear()
	clear_input_feedback()


func set_effects_volume(value: float) -> void:
	if combat_feedback_audio != null:
		combat_feedback_audio.set_volume(value)


func show_input_feedback(text: String, tick: int) -> void:
	_input_feedback_text = text
	_input_feedback_expires_tick = tick + INPUT_FEEDBACK_DURATION_TICKS


func active_input_feedback(tick: int) -> String:
	if _input_feedback_expires_tick >= 0 and tick >= _input_feedback_expires_tick:
		clear_input_feedback()
	return _input_feedback_text


func clear_input_feedback() -> void:
	_input_feedback_text = ""
	_input_feedback_expires_tick = -1


func consume(events: Array, animations: RefCounted, tick: int) -> void:
	if not enabled:
		return
	for event: Dictionary in events:
		var event_id := int(event.get("event_id", 0))
		if event_id <= presentation_event_cursor:
			continue
		presentation_event_cursor = event_id
		animations.handle_event(event, tick)
		if combat_feedback_audio != null:
			combat_feedback_audio.handle_event(event)
		match String(event.get("type", "")):
			"damage_applied":
				if String(event.get("target_id", "")) == "ranger":
					_append_mark(event, "player_damage", "−%s" % String(event.get("amount", "0")))
				elif int(event.get("target_entity_id", 0)) > 0:
					_append_mark(event, "enemy_damage", String(event.get("amount", "0")))
			"attack_resolved":
				var outcome := String(event.get("outcome", ""))
				if outcome == "blocked":
					_append_mark(event, "blocked", "圣律屏障")
				elif outcome == "miss" and String(event.get("source_id", "")).begins_with("ranger/"):
					_append_mark(event, "miss", "落空")
				elif outcome == "avoided" and String(event.get("target_id", "")) == "ranger":
					_append_mark(event, "avoided", "闪避")
			"death_applied":
				if String(event.get("target_id", "")) != "ranger":
					_append_mark(event, "death", "击破")


func add_impact_traces(position: Vector2, aim: Vector2, generations: int) -> void:
	if not enabled:
		return
	var representatives := mini(4, maxi(2, generations))
	for index in representatives:
		var angle := -1.15 + 0.76 * float(index)
		traces.append(Trace.new(position, position + aim.rotated(angle) * (14.0 + 4.0 * index)))


func advance(delta: float) -> void:
	if not enabled or not is_finite(delta) or delta <= 0.0:
		return
	advance_marks(delta)
	for index in range(traces.size() - 1, -1, -1):
		traces[index].remaining -= delta
		if traces[index].remaining <= 0.0:
			traces.remove_at(index)


func forget_action(action_id: int) -> void:
	var request_id := int(attack_action_request_ids.get(action_id, 0))
	attack_action_request_ids.erase(action_id)
	forget_request(request_id)


func register_command_source(sequence: int, source: String) -> void:
	attack_command_sources[sequence] = source


func discard_command(sequence: int) -> void:
	attack_command_sources.erase(sequence)


func remember_request_source(request_id: int, source: String, replaced_request_id: int = 0) -> void:
	attack_request_sources[request_id] = source if source in ["pointer", "proxy"] else "assisted"
	if replaced_request_id > 0:
		forget_request(replaced_request_id)


func bind_action_request(action_id: int, request_id: int) -> void:
	if action_id > 0 and request_id > 0:
		attack_action_request_ids[action_id] = request_id


func forget_request(request_id: int) -> void:
	attack_request_sources.erase(request_id)


func take_command_source(sequence: int, fallback: String) -> String:
	var source := String(attack_command_sources.get(sequence, fallback))
	attack_command_sources.erase(sequence)
	return source


func report() -> Dictionary:
	return {
		"mark_count": combat_feedback_marks.size(),
		"mark_limit": COMBAT_FEEDBACK_LIMIT,
		"presentation_event_cursor": presentation_event_cursor,
		"audio": combat_feedback_audio.report() if combat_feedback_audio != null else {},
	}


func _append_mark(event: Dictionary, kind: String, text: String) -> void:
	var position_value: Variant = event.get("contact_point", event.get("position", Vector2.ZERO))
	if not position_value is Vector2:
		return
	var feedback_key := _combat_feedback_key(event, kind)
	if kind == "enemy_damage" or kind == "player_damage":
		for index: int in range(combat_feedback_marks.size() - 1, -1, -1):
			var current: Dictionary = combat_feedback_marks[index]
			if String(current.get("feedback_key", "")) != feedback_key:
				continue
			current["event_id"] = int(event.get("event_id", 0))
			current["position"] = position_value
			current["text"] = text
			if event.has("incoming_direction"):
				current["incoming_direction"] = event.get("incoming_direction")
			current["remaining"] = COMBAT_FEEDBACK_LIFETIME_SECONDS
			current["duration"] = COMBAT_FEEDBACK_LIFETIME_SECONDS
			combat_feedback_marks[index] = current
			return
	combat_feedback_marks.append({
		"event_id": int(event.get("event_id", 0)),
		"kind": kind,
		"feedback_key": feedback_key,
		"position": position_value,
		"incoming_direction": event.get("incoming_direction", Vector2.RIGHT),
		"text": text,
		"text_lane": int(COMBAT_FEEDBACK_TEXT_LANES.get(kind, 0)),
		"remaining": COMBAT_FEEDBACK_LIFETIME_SECONDS,
		"duration": COMBAT_FEEDBACK_LIFETIME_SECONDS,
	})
	while combat_feedback_marks.size() > COMBAT_FEEDBACK_LIMIT:
		combat_feedback_marks.pop_front()


func _combat_feedback_key(event: Dictionary, kind: String) -> String:
	var target_entity_id := int(event.get("target_entity_id", 0))
	if target_entity_id > 0:
		return "%s:enemy/%d" % [kind, target_entity_id]
	var target_id := String(event.get("target_id", ""))
	if not target_id.is_empty():
		return "%s:%s" % [kind, target_id]
	return "%s:event/%d" % [kind, int(event.get("event_id", 0))]


func advance_marks(delta: float) -> void:
	for index: int in range(combat_feedback_marks.size() - 1, -1, -1):
		combat_feedback_marks[index]["remaining"] = maxf(0.0, float(combat_feedback_marks[index].get("remaining", 0.0)) - maxf(0.0, delta))
		if float(combat_feedback_marks[index]["remaining"]) <= 0.0:
			combat_feedback_marks.remove_at(index)
