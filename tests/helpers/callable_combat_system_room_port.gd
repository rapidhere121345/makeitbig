class_name CallableCombatSystemRoomPort
extends "res://src/runtime/combat/combat_system_room_port.gd"

## Tests-only adapter for constructing isolated CombatSystem fixtures.  The
## production path uses MainCombatRoomPort; keeping these Callables here lets
## unit tests vary malformed room answers without reintroducing a production
## callback ABI.

var player_rule_port: Variant = null
var target_by_id_callback: Variant = Callable()
var aim_candidate_callback: Variant = Callable()
var current_model_callback: Variant = Callable()
var target_blocked_callback: Variant = Callable()
var maybe_summon_callback: Variant = Callable()
var remove_target_callback: Variant = Callable()
var cancel_buffered_target_callback: Variant = Callable()
var update_mark_callback: Variant = Callable()
var advance_sequence_callback: Variant = Callable()
var reset_sequence_callback: Variant = Callable()
var erase_attack_request_callback: Variant = Callable()
var _ready := false


func configure(callbacks: Dictionary) -> Dictionary:
	_ready = false
	player_rule_port = callbacks.get("player_rule_port", null)
	if player_rule_port == null:
		return {"ok": false, "error": "player_rule_port_unavailable"}
	for method: String in ["consume_first_critical_bonus", "retain_missed_arrow", "take_retained_arrow"]:
		if not player_rule_port.has_method(method):
			return {"ok": false, "error": "player_rule_port_unavailable"}
	target_by_id_callback = callbacks.get("target_by_id", Callable())
	aim_candidate_callback = callbacks.get("aim_candidate", Callable())
	current_model_callback = callbacks.get("current_model", Callable())
	target_blocked_callback = callbacks.get("target_blocked", Callable())
	if not target_blocked_callback is Callable or not (target_blocked_callback as Callable).is_valid():
		return {"ok": false, "error": "combat_room_port_unavailable"}
	maybe_summon_callback = callbacks.get("maybe_summon", Callable())
	remove_target_callback = callbacks.get("remove_target", Callable())
	cancel_buffered_target_callback = callbacks.get("cancel_buffered_target", Callable())
	update_mark_callback = callbacks.get("update_mark", Callable())
	advance_sequence_callback = callbacks.get("advance_sequence", Callable())
	reset_sequence_callback = callbacks.get("reset_sequence", Callable())
	erase_attack_request_callback = callbacks.get("erase_attack_request", Callable())
	_ready = true
	return {"ok": true, "error": ""}


func is_ready() -> bool:
	return _ready and player_rule_port != null and is_instance_valid(player_rule_port) and target_blocked_callback is Callable and (target_blocked_callback as Callable).is_valid()


func target_by_id(entity_id: int) -> CombatEnemyState:
	if target_by_id_callback is Callable and (target_by_id_callback as Callable).is_valid():
		var value: Variant = (target_by_id_callback as Callable).call(entity_id)
		return value as CombatEnemyState if value is CombatEnemyState else null
	return null


func aim_candidate(target: CombatEnemyState) -> Dictionary:
	if aim_candidate_callback is Callable and (aim_candidate_callback as Callable).is_valid():
		var value: Variant = (aim_candidate_callback as Callable).call(target)
		return value if value is Dictionary else {}
	return {}


func current_model() -> Dictionary:
	if current_model_callback is Callable and (current_model_callback as Callable).is_valid():
		var value: Variant = (current_model_callback as Callable).call()
		return value if value is Dictionary else {}
	return {}


func target_blocked(target: CombatEnemyState) -> Dictionary:
	if not target_blocked_callback is Callable or not (target_blocked_callback as Callable).is_valid():
		return {"ok": false, "error": "target_blocked_port_unavailable"}
	return {"ok": true, "error": "", "blocked": (target_blocked_callback as Callable).call(target)}


func maybe_summon(target: CombatEnemyState) -> void:
	if maybe_summon_callback is Callable and (maybe_summon_callback as Callable).is_valid():
		(maybe_summon_callback as Callable).call(target)


func remove_target(target: CombatEnemyState) -> void:
	if remove_target_callback is Callable and (remove_target_callback as Callable).is_valid():
		(remove_target_callback as Callable).call(target)


func cancel_buffered_target(entity_id: int) -> int:
	if cancel_buffered_target_callback is Callable and (cancel_buffered_target_callback as Callable).is_valid():
		return int((cancel_buffered_target_callback as Callable).call(entity_id))
	return 0


func update_mark() -> void:
	if update_mark_callback is Callable and (update_mark_callback as Callable).is_valid():
		(update_mark_callback as Callable).call()


func advance_sequence(skill_id: String) -> void:
	if advance_sequence_callback is Callable and (advance_sequence_callback as Callable).is_valid():
		(advance_sequence_callback as Callable).call(skill_id)


func reset_sequence() -> void:
	if reset_sequence_callback is Callable and (reset_sequence_callback as Callable).is_valid():
		(reset_sequence_callback as Callable).call()


func erase_attack_request(request_id: int) -> void:
	if erase_attack_request_callback is Callable and (erase_attack_request_callback as Callable).is_valid():
		(erase_attack_request_callback as Callable).call(request_id)


func consume_first_critical_bonus() -> int:
	return int(player_rule_port.consume_first_critical_bonus())


func retain_missed_arrow(aggregate: BigValue, ordinary: float) -> bool:
	player_rule_port.retain_missed_arrow(aggregate, ordinary)
	return true


func take_retained_arrow() -> Dictionary:
	var value: Variant = player_rule_port.take_retained_arrow()
	return value if value is Dictionary else {}
