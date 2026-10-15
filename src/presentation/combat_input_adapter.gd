class_name CombatInputAdapter
extends RefCounted

## Device intent boundary. Captures GUI ownership/held sources, maps screen
## pointing into gameplay coordinates, and asks a device-free command source
## for commands. Detached snapshots are its only knowledge of combat.
signal report_requested(text: String)

const ManualCombatInputScript := preload("res://src/systems/manual_combat_input.gd")
const ManualAimResolverScript := preload("res://src/systems/manual_aim_resolver.gd")
const Rules := preload("res://src/systems/ranger_skill_rules.gd")
const CommandSource := preload("res://src/systems/combat_command_source.gd")
const ATTACK_SOURCE_ASSISTED := "assisted"
const ATTACK_SOURCE_POINTER := "pointer"
const POINTER_STATUS_NONE := "none"
const POINTER_STATUS_LOCKED := "locked"
const POINTER_STATUS_OUT_OF_RANGE := "out_of_range"
const POINTER_STATUS_LOST := "lost"
const POINTER_STATUS_NO_TARGET := "no_pointer_target"

var manual_combat_input := ManualCombatInputScript.new()
var manual_aim_resolver := ManualAimResolverScript.new()
var command_source
var feedback
var screen_mapper: Callable
var pointer_interface_query: Callable
var loot_pickup_command_factory: Callable
var manual_pointer_target_entity_id := 0
var manual_pointer_gameplay := Vector2.ZERO
var manual_pointer_target_anchor := Vector2.ZERO
var manual_pointer_target_radius := 0.0
var manual_pointer_status := POINTER_STATUS_NONE
var _loot_pickup_requested_id := ""
var _snapshot: Dictionary = {}


func configure(source: RefCounted, command_factories: Dictionary, feedback_owner: Node,
	mapper: Callable, interface_query: Callable) -> void:
	command_source = source
	feedback = feedback_owner
	screen_mapper = mapper
	pointer_interface_query = interface_query
	var callbacks := command_factories.duplicate()
	loot_pickup_command_factory = callbacks.get("make_loot_pickup", Callable())
	callbacks.merge({
		"player_position": Callable(self, "player_position"),
		"player_facing": Callable(self, "player_facing"),
		"locked_targeting_distance": Callable(self, "targeting_distance"),
		"hunter_mark_range": Callable(self, "mark_range"),
		"nearest_target": Callable(self, "nearest_target"),
		"preferred_target": Callable(self, "preferred_target"),
		"target_by_id": Callable(self, "target_by_id"),
		"pointer_target_entity_id": Callable(self, "pointer_target_id"),
		"refresh_pointer_lock": Callable(self, "refresh_pointer_lock"),
		"mark_pointer_lost": Callable(self, "mark_pointer_lost"),
		"mark_pointer_out_of_range": Callable(self, "mark_pointer_out_of_range"),
		"held_attack_window_open": Callable(self, "held_attack_window_open"),
		"register_attack_source": Callable(self, "register_attack_source"),
		"clear_input_feedback": Callable(self, "clear_feedback"),
		"show_assisted_rejection_feedback": Callable(self, "show_assisted_rejection"),
	})
	command_source.configure(callbacks)


func collect_commands(snapshot: Dictionary) -> Array[Dictionary]:
	_snapshot = snapshot
	if not active():
		return []
	var over_interface := pointer_over_interface()
	return command_source.collect_manual_commands({
		"movement": Input.get_vector("move_left", "move_right", "move_up", "move_down"),
		"held_source": manual_combat_input.attack_source(over_interface),
	})


## Loot input is a room command, not a PlayerCombatRules command. Main consumes
## this detached request before routing the ordinary combat commands, so the
## ledger remains the only authority for range, lifecycle and one-shot state.
func collect_loot_pickup_command(snapshot: Dictionary) -> Dictionary:
	_snapshot = snapshot
	if _loot_pickup_requested_id.is_empty() or not loot_input_active(snapshot):
		_loot_pickup_requested_id = "" if not loot_input_active(snapshot) else _loot_pickup_requested_id
		return {}
	var loot_entity_id := _loot_pickup_requested_id
	_loot_pickup_requested_id = ""
	if not loot_pickup_command_factory.is_valid():
		return {}
	var command: Variant = loot_pickup_command_factory.call(loot_entity_id)
	return (command as Dictionary).duplicate(true) if command is Dictionary else {}


func pointer_over_interface() -> bool:
	return bool(pointer_interface_query.call()) if pointer_interface_query.is_valid() else false


func active() -> bool:
	return bool(_snapshot.get("in_arena", false)) and not bool(_snapshot.get("battle_over", false)) and String(_snapshot.get("selected_mode", "")) == "Manual"


func capture_actions(event: InputEvent, snapshot: Dictionary) -> void:
	_snapshot = snapshot
	if event is InputEventKey and event.echo:
		return
	if event.is_action_pressed("loot_pickup"):
		request_loot_pickup(snapshot)
		return
	if not active():
		return
	if event.is_action_pressed("dodge") and (not event is InputEventMouseButton or not pointer_over_interface()):
		command_source.dodge_requested = true
	elif event.is_action_pressed("skill_2"):
		request_skill("hunter_mark", snapshot)
	elif event.is_action_pressed("skill_3"):
		request_skill("dash", snapshot)


func request_skill(ability: String, snapshot: Dictionary) -> void:
	_snapshot = snapshot
	if not active():
		return
	match ability:
		"piercing_arrow": request_assisted_attack()
		"basic_dodge": command_source.dodge_requested = true
		"hunter_mark", "dash":
			var slot := 1 if ability == "hunter_mark" else 2
			var skills: Array = snapshot.get("equipped_skills", [])
			if skills.size() > slot and String(skills[slot]) == ability:
				if ability == "hunter_mark":
					command_source.hunter_mark_requested = true
				else:
					command_source.dash_requested = true
				clear_feedback()
			else:
				show_feedback("猎人印记未装配在本场构筑 · 暂无法施放" if ability == "hunter_mark" else "突袭未装配在本场构筑 · 暂无法施放")


func reset_intent() -> void:
	command_source.reset_intent()
	_loot_pickup_requested_id = ""
	clear_pointer_lock()
	manual_combat_input.reset()
	feedback.reset_input()


func take_continuous_input(mode: String) -> RefCounted:
	if mode != "Manual":
		return null
	manual_combat_input.retain_pressed_assisted_sources()
	if not manual_combat_input.attack_held(false):
		return null
	var carried: RefCounted = manual_combat_input
	manual_combat_input = ManualCombatInputScript.new()
	reset_intent()
	return carried


func resume_continuous_input(carried: RefCounted, snapshot: Dictionary) -> void:
	if String(snapshot.get("selected_mode", "")) != "Manual" or not bool(snapshot.get("in_arena", false)) or bool(snapshot.get("battle_over", false)) or not carried is ManualCombatInputScript:
		return
	carried.retain_pressed_assisted_sources()
	manual_combat_input = carried


func view_state(snapshot: Dictionary) -> Dictionary:
	var manual := String(snapshot.get("selected_mode", "")) == "Manual"
	return {
		"device": manual_combat_input.snapshot() if manual else {},
		"held_source": manual_combat_input.attack_source(pointer_over_interface()) if manual else "",
		"pointer_target_entity_id": manual_pointer_target_entity_id,
		"pointer_status": manual_pointer_status,
		"edge_requested": command_source.attack_requested,
		"edge_source": command_source.attack_requested_source,
		"edge_target_id": command_source.attack_requested_target_entity_id,
		"request_sources": feedback.attack_request_sources.duplicate(true),
		"input_feedback": feedback.active_input_feedback(int(snapshot.get("sim_tick", 0))),
		"loot_pickup_pending_id": _loot_pickup_requested_id,
		"loot_input_active": loot_input_active(snapshot),
	}


func loot_input_active(snapshot: Dictionary) -> bool:
	if not bool(snapshot.get("in_arena", false)):
		return false
	if bool(snapshot.get("battle_over", false)) and not bool(snapshot.get("battle_victory", false)):
		return false
	var room_loot_value: Variant = snapshot.get("room_loot", {})
	if not room_loot_value is Dictionary:
		return false
	for entity_value: Variant in (room_loot_value as Dictionary).get("entities", []):
		if entity_value is Dictionary and String((entity_value as Dictionary).get("state", "")) == "available" \
			and not String((entity_value as Dictionary).get("loot_entity_id", "")).strip_edges().is_empty():
			return true
	return false


func request_loot_pickup(snapshot: Dictionary) -> void:
	_snapshot = snapshot
	if not loot_input_active(snapshot):
		return
	var target := _nearest_available_loot(snapshot)
	if target.is_empty():
		show_feedback("附近没有可拾取掉落")
		return
	_loot_pickup_requested_id = String(target.get("loot_entity_id", ""))
	clear_feedback()


func _nearest_available_loot(snapshot: Dictionary) -> Dictionary:
	var room_loot_value: Variant = snapshot.get("room_loot", {})
	if not room_loot_value is Dictionary:
		return {}
	var player_position_value: Variant = snapshot.get("player_position", Vector2.ZERO)
	var player_position := player_position_value as Vector2 if player_position_value is Vector2 else Vector2.ZERO
	var nearest: Dictionary = {}
	var nearest_distance := INF
	for entity_value: Variant in (room_loot_value as Dictionary).get("entities", []):
		if not entity_value is Dictionary:
			continue
		var entity: Dictionary = entity_value
		var loot_entity_id := String(entity.get("loot_entity_id", "")).strip_edges()
		if String(entity.get("state", "")) != "available" or loot_entity_id.is_empty():
			continue
		var position_value: Variant = entity.get("position", Vector2.ZERO)
		var position := position_value as Vector2 if position_value is Vector2 else Vector2.ZERO
		var distance := player_position.distance_squared_to(position)
		if distance < nearest_distance or (is_equal_approx(distance, nearest_distance) and (nearest.is_empty() or loot_entity_id < String(nearest.get("loot_entity_id", "")))):
			nearest_distance = distance
			nearest = entity.duplicate(true)
	return nearest


func _screen_to_gameplay(point: Vector2) -> Vector2:
	return screen_mapper.call(point, _snapshot) if screen_mapper.is_valid() else point


func player_position() -> Vector2:
	return _snapshot.get("player_position", Vector2.ZERO)


func player_facing() -> Vector2:
	return _snapshot.get("player_facing", Vector2.RIGHT)


func targeting_distance() -> float:
	return float(_snapshot.get("locked_targeting_distance", 0.0))


func mark_range() -> float:
	return targeting_distance() * Rules.HUNTER_MARK_RANGE_MULTIPLIER


func pointer_target_id() -> int:
	return manual_pointer_target_entity_id


func mark_pointer_lost() -> void:
	if manual_pointer_target_entity_id > 0:
		manual_pointer_status = POINTER_STATUS_LOST


func mark_pointer_out_of_range() -> void:
	if manual_pointer_target_entity_id > 0:
		manual_pointer_status = POINTER_STATUS_OUT_OF_RANGE


func target_by_id(id: int) -> Dictionary:
	for target: Dictionary in _manual_aim_candidates():
		if int(target["entity_id"]) == id:
			return target
	return {}


func nearest_target(maximum_distance: float = INF) -> Dictionary:
	var nearest: Dictionary = {}
	var best := maximum_distance * maximum_distance
	for target: Dictionary in _manual_aim_candidates():
		if float(target["health"]) <= 0.0:
			continue
		var distance := player_position().distance_squared_to(target["position"])
		if distance < best or (is_equal_approx(distance, best) and (nearest.is_empty() or int(target["entity_id"]) < int(nearest["entity_id"]))):
			best = distance
			nearest = target
	return nearest


func preferred_target() -> Dictionary:
	for pair in [[int(_snapshot.get("marked_entity_id", 0)), int(_snapshot.get("hunter_mark_expires_tick", 0)), false],
		[int(_snapshot.get("hunter_mark_candidate_entity_id", 0)), int(_snapshot.get("hunter_mark_candidate_expires_tick", 0)), true]]:
		var target := target_by_id(int(pair[0]))
		var tick := int(_snapshot.get("sim_tick", 0))
		var valid_time := tick <= int(pair[1]) if bool(pair[2]) else tick < int(pair[1])
		if not target.is_empty() and float(target["health"]) > 0.0 and valid_time and player_position().distance_to(target["position"]) <= targeting_distance():
			return target
	return nearest_target()


func held_attack_window_open(target: Dictionary) -> bool:
	return not target.is_empty() and player_position().distance_to(target.get("position", Vector2.ZERO)) <= targeting_distance() and CommandSource.request_window_open(int(_snapshot["sim_tick"]), int(_snapshot["attack_cooldown_ticks"]), _snapshot.get("timeline", {}))


func register_attack_source(sequence: int, source: String) -> void:
	feedback.register_command_source(sequence, source)


func show_feedback(text: String) -> void:
	feedback.show_input_feedback(text, int(_snapshot.get("sim_tick", 0)))


func clear_feedback() -> void:
	feedback.clear_input_feedback()


func show_assisted_rejection() -> void:
	show_feedback("暂无目标 · 靠近敌人后按空格")


func capture_attack_event(event: InputEvent, pointer_over_interface: bool, snapshot: Dictionary) -> void:
	_snapshot = snapshot
	if manual_combat_input == null:
		return
	if not _snapshot["in_arena"] or _snapshot["battle_over"] or _snapshot["selected_mode"] != "Manual":
		if _snapshot["selected_mode"] != "Manual":
			manual_combat_input.reset()
		return
	var newly_pressed: bool = manual_combat_input.observe_attack_event(event, pointer_over_interface)
	var pointer_event := event is InputEventMouseButton
	if pointer_event and event.is_action_released(&"attack"):
		clear_pointer_lock()
		return
	if not newly_pressed:
		return
	var source: String = manual_combat_input.attack_source(pointer_over_interface)
	if source == ATTACK_SOURCE_POINTER:
		if pointer_event:
			_capture_pointer_attack((event as InputEventMouseButton).position)
		else:
			_request_pointer_attack()
	else:
		request_assisted_attack()


func _capture_pointer_attack(screen_point: Vector2) -> void:
	clear_attack_edge()
	manual_pointer_gameplay = _screen_to_gameplay(screen_point)
	var resolved: Dictionary = manual_aim_resolver.resolve_pointer(
		manual_pointer_gameplay,
		_snapshot["player_position"],
		_snapshot["locked_targeting_distance"],
		_manual_aim_candidates()
	)
	if not bool(resolved.get("ok", false)):
		clear_pointer_lock(false)
		manual_pointer_gameplay = _screen_to_gameplay(screen_point)
		manual_pointer_status = POINTER_STATUS_NO_TARGET
		report_requested.emit("鼠标未锁定目标；空白点击不会改为自动寻敌。")
		show_feedback("点击敌人射击 · 或按住空格辅助瞄准")
		return
	clear_feedback()
	manual_pointer_target_entity_id = int(resolved.get("target_entity_id", 0))
	manual_pointer_target_anchor = resolved.get("target_anchor", Vector2.ZERO)
	manual_pointer_target_radius = float(resolved.get("target_radius", 0.0))
	manual_pointer_status = POINTER_STATUS_LOCKED if bool(resolved.get("in_range", false)) else POINTER_STATUS_OUT_OF_RANGE
	if manual_pointer_status == POINTER_STATUS_LOCKED:
		_request_pointer_attack()
		report_requested.emit("指针已锁定目标。")
	else:
		report_requested.emit("指针已锁定目标，但目前在射程外。")
		show_feedback("目标在射程外 · 靠近后再射")


func _manual_aim_candidates() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for enemy: CombatEnemyState in _snapshot["enemies"]:
		result.append({
			"entity_id": enemy.entity_id,
			"kind_id": enemy.kind_id,
			"position": enemy.position,
			"health": enemy.health,
			"is_boss": enemy.is_boss,
		})
	return result


func request_assisted_attack() -> void:
	command_source.attack_requested = true
	command_source.attack_requested_source = ATTACK_SOURCE_ASSISTED
	command_source.attack_requested_target_entity_id = 0
	command_source.attack_requested_pointer_gameplay = Vector2.ZERO


func _request_pointer_attack() -> void:
	clear_attack_edge()
	if not refresh_pointer_lock():
		return
	command_source.attack_requested = true
	command_source.attack_requested_source = ATTACK_SOURCE_POINTER
	command_source.attack_requested_target_entity_id = manual_pointer_target_entity_id
	command_source.attack_requested_pointer_gameplay = manual_pointer_gameplay


func refresh_pointer_lock() -> bool:
	if manual_pointer_target_entity_id <= 0:
		if manual_pointer_status != POINTER_STATUS_NO_TARGET:
			manual_pointer_status = POINTER_STATUS_LOST
		return false
	var target := target_by_id(manual_pointer_target_entity_id)
	if target.is_empty() or float(target.get("health", 0.0)) <= 0.0:
		manual_pointer_status = POINTER_STATUS_LOST
		manual_pointer_target_anchor = Vector2.ZERO
		manual_pointer_target_radius = 0.0
		return false
	var candidate := {
		"entity_id": int(target.get("entity_id", 0)),
		"kind_id": String(target.get("kind_id", "")),
		"position": (target.get("position", Vector2.ZERO) as Vector2),
		"health": float(target.get("health", 0.0)),
		"is_boss": bool(target.get("is_boss", false)),
	}
	manual_pointer_target_anchor = manual_aim_resolver.target_anchor(candidate)
	manual_pointer_target_radius = manual_aim_resolver.target_radius(candidate)
	manual_pointer_status = POINTER_STATUS_LOCKED if _snapshot["player_position"].distance_to((target.get("position", Vector2.ZERO) as Vector2)) <= _snapshot["locked_targeting_distance"] else POINTER_STATUS_OUT_OF_RANGE
	return manual_pointer_status == POINTER_STATUS_LOCKED


func clear_attack_edge() -> void:
	command_source.attack_requested = false
	command_source.attack_requested_source = ""
	command_source.attack_requested_target_entity_id = 0
	command_source.attack_requested_pointer_gameplay = Vector2.ZERO


func clear_pointer_lock(clear_status: bool = true) -> void:
	manual_pointer_target_entity_id = 0
	manual_pointer_gameplay = Vector2.ZERO
	manual_pointer_target_anchor = Vector2.ZERO
	manual_pointer_target_radius = 0.0
	if clear_status:
		manual_pointer_status = POINTER_STATUS_NONE
