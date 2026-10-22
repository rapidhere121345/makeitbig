class_name CombatPresentationFrameBuilder
extends RefCounted

## Pure projection of a detached gameplay snapshot plus cosmetic/input values.
## Labels, HUD cells and draw frames cannot issue commands or move actors.

const Snapshot := preload("res://src/presentation/combat_presentation_snapshot.gd")
const RoomCatalog := preload("res://src/runtime/world/room_catalog.gd")
const AimResolver := preload("res://src/systems/manual_aim_resolver.gd")
const RangerSkillRulesScript := preload("res://src/systems/ranger_skill_rules.gd")
const PlayerActionTimelineScript := preload("res://src/systems/player_action_timeline.gd")
const SIM_TICKS_PER_SECOND := RangerSkillRulesScript.TICKS_PER_SECOND
const DODGE_DURATION_TICKS := RangerSkillRulesScript.DODGE_DURATION_TICKS
const DASH_DURATION_TICKS := RangerSkillRulesScript.DASH_DURATION_TICKS
const DASH_TOTAL_DISTANCE := RangerSkillRulesScript.DASH_TOTAL_DISTANCE
const HUNTER_MARK_DURATION_TICKS := RangerSkillRulesScript.HUNTER_MARK_DURATION_TICKS
const HUNTER_MARK_RANGE_MULTIPLIER := RangerSkillRulesScript.HUNTER_MARK_RANGE_MULTIPLIER
const DODGE_COOLDOWN_TICKS := RangerSkillRulesScript.DODGE_COOLDOWN_TICKS

const ATTACK_SOURCE_ASSISTED := "assisted"
const ATTACK_SOURCE_POINTER := "pointer"
const ATTACK_SOURCE_PROXY := "proxy"
const POINTER_STATUS_NONE := "none"
const POINTER_STATUS_LOCKED := "locked"
const POINTER_STATUS_LOST := "lost"
const POINTER_STATUS_NO_TARGET := "no_pointer_target"
const POINTER_STATUS_OUT_OF_RANGE := "out_of_range"
var room_catalog := RoomCatalog.new()
var aim_resolver := AimResolver.new()


func world_frame(snapshot: Dictionary, viewport: Rect2, pending_reason: String) -> Dictionary:
	var presentation_geometry: Dictionary = snapshot.get("presentation_geometry", snapshot["walkable_geometry"]).duplicate(true)
	return {
		"presentation_enabled": true, "in_arena": snapshot["in_arena"],
		"viewport_rect": viewport, "arena_rect": snapshot["arena_rect"],
		"focus_gameplay": snapshot["player_position"],
		"layout_id": snapshot["layout_id"],
		"walkable_geometry": snapshot["walkable_geometry"].duplicate(true),
		"presentation_geometry": presentation_geometry,
		"sim_tick": snapshot["sim_tick"], "pending_reason": pending_reason,
	}


func combat_frame(snapshot: Dictionary, input_view: Dictionary, visual: Dictionary, font: Font) -> Dictionary:
	var presentation_geometry: Dictionary = snapshot.get("presentation_geometry", snapshot["walkable_geometry"]).duplicate(true)
	return {
		"presentation_enabled": true, "in_arena": snapshot["in_arena"],
		"arena_rect": snapshot["arena_rect"], "layout_id": snapshot["layout_id"],
		"walkable_geometry": snapshot["walkable_geometry"], "presentation_geometry": presentation_geometry, "sim_tick": snapshot["sim_tick"],
		"player_position": snapshot["player_position"], "player_facing": snapshot["player_facing"],
		"enemies": snapshot["enemies"], "hazard_states": snapshot["hazard_states"],
		"loot_entities": (snapshot.get("room_loot", {}).get("entities", []) as Array).duplicate(true),
		"projectiles": snapshot["projectiles"], "traces": visual["traces"],
		"combat_feedback_marks": visual["combat_feedback_marks"],
		"player_damage_overlay": visual["player_damage_overlay"],
		"dash_remaining_ticks": snapshot["dash_remaining_ticks"], "dash_direction": snapshot["dash_direction"],
		"dodge_remaining_ticks": snapshot["dodge_remaining_ticks"],
		"dash_step": DASH_TOTAL_DISTANCE / float(scaled_ticks(snapshot, DASH_DURATION_TICKS, "dash_duration_multiplier")) if int(snapshot["dash_remaining_ticks"]) > 0 else 0.0,
		"attack_target_ui": attack_target(snapshot, input_view),
		"marked_enemy": enemy_by_id(snapshot, int(snapshot["marked_entity_id"])),
		"marked_expires_tick": snapshot["hunter_mark_expires_tick"], "font": font,
		"charge_active_ticks": 10,
	}


func actor_frame(snapshot: Dictionary, visual: Dictionary) -> Dictionary:
	var maximum: BigValue = snapshot["boss_maximum"]
	var damage: BigValue = snapshot["boss_damage"]
	var ratio := 1.0
	if damage.layer == 0 and maximum.layer == 0 and maximum.magnitude > 0.0:
		ratio = clampf(1.0 - damage.magnitude / maximum.magnitude, 0.0, 1.0)
	var enemies: Array[CombatEnemyState] = []
	for enemy: CombatEnemyState in snapshot["enemies"]:
		enemies.append(Snapshot.enemy_record(enemy))
	return {
		"presentation_enabled": true, "in_arena": snapshot["in_arena"], "sim_tick": snapshot["sim_tick"],
		"player_position": snapshot["player_position"], "player_facing": snapshot["player_facing"],
		"ranger_visual_time": visual["ranger_visual_time"], "ranger_frame": visual["ranger_frame"].duplicate(true),
		"enemy_frames": visual["enemy_frames"].duplicate(true), "enemies": enemies,
		"enemy_corpses": visual["enemy_corpses"].duplicate(true), "boss_health_ratio": ratio,
		"loot_entities": (snapshot.get("room_loot", {}).get("entities", []) as Array).duplicate(true),
	}


func enemy_by_id(snapshot: Dictionary, id: int) -> CombatEnemyState:
	for enemy: CombatEnemyState in snapshot["enemies"]:
		if enemy.entity_id == id:
			return enemy
	return null


func scaled_ticks(snapshot: Dictionary, base_ticks: int, capability: String) -> int:
	return maxi(1, int(round(float(base_ticks) * (1.0 + clampf(float(snapshot.get("talent_capabilities", {}).get(capability, 0.0)), -1.0, 10.0)))))


func scaled_cooldown(snapshot: Dictionary, ticks: int) -> int:
	return maxi(1, int(round(float(ticks) * (1.0 - clampf(float(snapshot.get("talent_capabilities", {}).get("dodge_cooldown_reduction", 0.0)), 0.0, 0.95)))))


func hud_frame(snapshot: Dictionary, input_view: Dictionary, action_edge_occluded: bool = false) -> Dictionary:
	var model: Dictionary = snapshot["model"]
	var attack_ui := attack_state(snapshot, input_view)
	var attack_held_source: String = String(input_view.get("held_source", ""))
	var attack_held: bool = not attack_held_source.is_empty()
	var attack_target_ui := attack_target(snapshot, input_view, attack_ui)
	var remaining: BigValue = boss_remaining(snapshot)
	var nearest := nearest_target(snapshot)
	var ratio_known: bool = remaining.layer == snapshot["boss_maximum"].layer and remaining.layer == 0
	var ratio := clampf(remaining.magnitude / snapshot["boss_maximum"].magnitude, 0.0, 1.0) if ratio_known and snapshot["boss_maximum"].magnitude > 0.0 else 0.0
	var equipped: Dictionary = snapshot["equipped_parameters"]
	var lifetime := float(snapshot["locked_build"].final_parameters.T) if not snapshot["locked_build"].is_empty() else float(equipped.shared_lifetime)
	var targeting_distance := float(snapshot["locked_build"].final_parameters.d) if not snapshot["locked_build"].is_empty() else float(equipped.distance)
	var mark_target := enemy_by_id(snapshot, snapshot["marked_entity_id"])
	var mark_range: float = snapshot["locked_targeting_distance"] * HUNTER_MARK_RANGE_MULTIPLIER
	var room_presentation := room_info(snapshot)
	var attack_target_enemy := enemy_by_id(snapshot, int(attack_target_ui.get("target_entity_id", 0)))
	var loot_prompt_state := loot_prompt(snapshot)
	return {
		"room_id": snapshot["room_id"],
		"room_index": int(snapshot["framework_room"].get("room_index", 0)),
		"room_count": int(snapshot["framework_room"].get("room_count", 1)),
		"room_elapsed_seconds": snapshot["elapsed"],
		"room_display_name": String(room_presentation.get("display_name", "Arena")),
		"room_concept": String(room_presentation.get("concept", "")),
		"room_landmark": String(room_presentation.get("landmark", "")),
		"room_entry_hint": String(room_presentation.get("entry_hint", "")),
		"room_exit_hint": String(room_presentation.get("exit_hint", "")),
		"player_health": snapshot["player_health"],
		"player_health_max": snapshot["player_maximum_health"],
		"key_status": "Dodging" if snapshot["dodge_remaining_ticks"] > 0 else ("Damage Alert" if snapshot["player_health"] < 35.0 else "Stable"),
		"boss_remaining": remaining.to_short_string(4),
		"boss_maximum": snapshot["boss_maximum"].to_short_string(4),
		"boss_ratio_known": ratio_known,
		"boss_ratio": ratio,
		"has_boss": snapshot["boss"] != null,
		"living_targets": snapshot["enemies"].size(),
		"layout_id": snapshot["layout_id"],
		"objective_id": snapshot["objective_id"],
		"objective_label": objective_label(snapshot),
		"hazard_status": hazard_status(snapshot),
		"elite_status": elite_status(snapshot),
		"selected_mode": snapshot["selected_mode"],
		"battle_over": snapshot["battle_over"],
		"battle_victory": snapshot["battle_victory"],
		"attack_cooldown_seconds": float(snapshot["attack_cooldown_ticks"]) / SIM_TICKS_PER_SECOND,
		"attack_phase": String(attack_ui.get("phase", "idle")),
		"attack_phase_label": String(attack_ui.get("label", "")),
		"attack_phase_tick": int(attack_ui.get("phase_tick", 0)),
		"attack_phase_remaining_ticks": int(attack_ui.get("phase_remaining_ticks", 0)),
		"attack_buffered": bool(attack_ui.get("buffered", false)),
		"attack_held": attack_held,
		"attack_held_source": attack_held_source,
		"attack_request_open": bool(attack_ui.get("request_open", false)),
		"attack_target_source": String(attack_target_ui.get("source", ATTACK_SOURCE_ASSISTED)),
		"attack_target_status": String(attack_target_ui.get("status", POINTER_STATUS_NONE)),
		"attack_target_entity_id": int(attack_target_ui.get("target_entity_id", 0)),
		"attack_has_target": bool(attack_target_ui.get("has_target", false)),
		"attack_target_in_range": bool(attack_target_ui.get("in_range", false)),
		"attack_target_label": enemy_public_label(attack_target_enemy),
		"attack_target_health": attack_target_enemy.health if attack_target_enemy != null else 0.0,
		"attack_target_maximum_health": attack_target_enemy.maximum_health if attack_target_enemy != null else 0.0,
		"hunter_mark_equipped": skill_equipped(snapshot, 1, "hunter_mark"),
		"hunter_mark_cooldown_seconds": float(snapshot["hunter_mark_cooldown_ticks"]) / SIM_TICKS_PER_SECOND,
		"hunter_mark_remaining_seconds": float(maxi(0, snapshot["hunter_mark_expires_tick"] - snapshot["sim_tick"])) / SIM_TICKS_PER_SECOND if mark_target != null else 0.0,
		"marked_entity_id": snapshot["marked_entity_id"],
		"marked_target_label": enemy_public_label(mark_target),
		"dash_equipped": skill_equipped(snapshot, 2, "dash"),
		"dash_cooldown_seconds": float(snapshot["dash_cooldown_ticks"]) / SIM_TICKS_PER_SECOND,
		"dash_active": snapshot["dash_remaining_ticks"] > 0,
		"dodge_cooldown_seconds": float(snapshot["dodge_cooldown_ticks"]) / SIM_TICKS_PER_SECOND,
		"talent_skill_overrides": {
			"hunter_mark": {"duration_ticks": scaled_ticks(snapshot, HUNTER_MARK_DURATION_TICKS, "hunter_mark_duration_multiplier")},
			"dash": {"duration_ticks": scaled_ticks(snapshot, DASH_DURATION_TICKS, "dash_duration_multiplier")},
			"basic_dodge": {"cooldown_ticks": scaled_cooldown(snapshot, DODGE_COOLDOWN_TICKS)},
		},
		"has_target": nearest != null,
		"target_in_range": nearest != null and snapshot["player_position"].distance_to(nearest.position) <= snapshot["locked_targeting_distance"],
		"mark_target_in_range": nearest != null and snapshot["player_position"].distance_to(nearest.position) <= mark_range,
		"damage": snapshot["boss_damage"].to_short_string(4),
		"feedback": hud_feedback(snapshot, input_view),
		"input_feedback": String(input_view.get("input_feedback", "")),
		"p": float(model["p"]),
		"lifetime": lifetime,
		"distance": targeting_distance,
		"g": int(model["g"]),
			"growth_verified": snapshot["shots"] > 0,
			"growth_type": String(model["state"]),
			"growth_snapshot_details": bool(model.get("growth_snapshot_details", false)),
		"growth_generation_time": float(model.get("generation_time", 0.0)),
		"proxy_prediction": snapshot["proxy_prediction"],
		"last_proxy_failure": snapshot.get("proxy_failure", {}),
		"action_edge_occluded": action_edge_occluded,
		"loot_entities": (snapshot.get("room_loot", {}).get("entities", []) as Array).duplicate(true),
		"loot_prompt_state": String(loot_prompt_state.get("state", "none")),
		"loot_prompt_text": String(loot_prompt_state.get("text", "")),
		"loot_prompt_entity_id": String(loot_prompt_state.get("entity_id", "")),
		"loot_prompt_count": int(loot_prompt_state.get("available_count", 0)),
	}


## Project the room-owned loot window into one actionable player cue. The prompt
## is presentation-only: range, lifecycle and pickup acceptance remain owned by
## the room ledger. A queued request stays visible as a short pending state until
## the next authoritative receipt replaces it.
func loot_prompt(snapshot: Dictionary) -> Dictionary:
	var empty := {
		"state": "none", "text": "", "entity_id": "", "available_count": 0,
		"in_range": false, "pending_count": 0,
	}
	if not bool(snapshot.get("in_arena", true)):
		return empty
	var room_value: Variant = snapshot.get("room_loot", {})
	if not room_value is Dictionary:
		return empty
	var room: Dictionary = room_value
	var entities_value: Variant = room.get("entities", [])
	if not entities_value is Array:
		return empty
	var pending_ids: Dictionary = {}
	var pending_value: Variant = room.get("pending_pickup_requests", [])
	if pending_value is Array:
		for pending_value_item: Variant in pending_value:
			if pending_value_item is Dictionary:
				var pending_id := String((pending_value_item as Dictionary).get("loot_entity_id", "")).strip_edges()
				if not pending_id.is_empty():
					pending_ids[pending_id] = true
	var player_value: Variant = snapshot.get("player_position", Vector2.ZERO)
	var player_position := player_value as Vector2 if player_value is Vector2 else Vector2.ZERO
	var nearest_id := ""
	var nearest_distance := INF
	var nearest_radius := 0.0
	var available_count := 0
	var pending_count := 0
	for entity_value: Variant in entities_value:
		if not entity_value is Dictionary:
			continue
		var entity: Dictionary = entity_value
		var loot_id := String(entity.get("loot_entity_id", "")).strip_edges()
		if loot_id.is_empty() or String(entity.get("state", "")) != "available":
			continue
		if pending_ids.has(loot_id):
			pending_count += 1
			continue
		available_count += 1
		var position_value: Variant = entity.get("position", Vector2.ZERO)
		var position := position_value as Vector2 if position_value is Vector2 else Vector2.ZERO
		var radius := maxf(0.0, float(entity.get("pickup_radius", 0.0)))
		var distance := player_position.distance_squared_to(position)
		if distance < nearest_distance or (is_equal_approx(distance, nearest_distance) and (nearest_id.is_empty() or loot_id < nearest_id)):
			nearest_id = loot_id
			nearest_distance = distance
			nearest_radius = radius
	if available_count == 0:
		if pending_count > 0:
			return {
				"state": "pending", "text": "Picking Up Loot...", "entity_id": "",
				"available_count": 0, "in_range": false, "pending_count": pending_count,
			}
		return empty
	var in_range := nearest_distance <= nearest_radius * nearest_radius + 0.000001
	var state := "near" if in_range else "far"
	var victory_prefix := "Combat Won · " if bool(snapshot.get("battle_over", false)) and bool(snapshot.get("battle_victory", false)) else ""
	var count_suffix := " ×%d" % available_count if available_count > 1 else ""
	var action_text := ("Loot Nearby%s · Press F to Pick Up" % count_suffix) if in_range else ("Loot on the Field%s · Move Closer and Press F to Pick Up" % count_suffix)
	return {
		"state": state,
		"text": victory_prefix + action_text,
		"entity_id": nearest_id,
		"available_count": available_count,
		"in_range": in_range,
		"pending_count": pending_count,
	}


func enemy_public_label(enemy: CombatEnemyState) -> String:
	if enemy == null:
		return ""
	if enemy.is_boss:
		return "Threshold Colossus"
	match enemy.kind_id:
		"melee_pursuer": return "Melee Pursuer"
		"charging_raider": return "Charging Raider"
		"fan_ranged": return "Fan-Shot Hunter"
	return "Enemy"


func hud_feedback(snapshot: Dictionary, input_view: Dictionary) -> String:
	if snapshot["battle_over"]:
		if snapshot["battle_victory"]:
			return "Target Defeated · %d Casts · %d Targets" % [snapshot["shots"], snapshot["defeated"]]
		return "Ranger Down · Return to Hub to Adjust Your Build"
	var proxy_failure: Dictionary = snapshot.get("proxy_failure", {})
	if snapshot["selected_mode"] == "Auto" and not proxy_failure.is_empty():
		var reason := String(proxy_failure.get("reason", ""))
		if reason in ["skill is not ready", "skill not ready"]:
			return "Proxy Executing · Piercing Arrow on Cooldown"
		return "Proxy Blocked · %s" % reason
	var action_ui := attack_state(snapshot, input_view)
	var action_label := String(action_ui.get("label", ""))
	var buffered := bool(action_ui.get("buffered", false))
	var attack_target_ui := attack_target(snapshot, input_view, action_ui)
	if snapshot["selected_mode"] == "Manual" and String(attack_target_ui.get("source", "")) == ATTACK_SOURCE_POINTER and action_label.is_empty() and not buffered:
		match String(attack_target_ui.get("status", POINTER_STATUS_NONE)):
			POINTER_STATUS_NO_TARGET:
				return "No Pointer Target · Empty Clicks Do Not Retarget"
			POINTER_STATUS_LOST:
				return "Pointer Lock Expired · Release and Select Again"
			POINTER_STATUS_OUT_OF_RANGE:
				return "Pointer Target Out of Range · Lock Retained"
	if action_label == "Draw":
		return "Drawing Piercing Arrow · Target Locked%s" % (" · Next Shot Buffered" if buffered else "")
	var outcome_text := ""
	match String(snapshot["last_attack_outcome"].get("outcome", "")):
		"blocked": outcome_text = "Sacred Law Barrier Block"
		"miss": outcome_text = "Piercing Arrow Missed"
		"killed": outcome_text = "Piercing Arrow Defeated Target"
		"damage": outcome_text = "Piercing Arrow Hit"
	if action_label == "Release":
		return "Release · %s%s" % [outcome_text if not outcome_text.is_empty() else "Resolving", " · Next Shot Buffered" if buffered else ""]
	if action_label == "Recovery":
		return "Recovery%s%s" % [" · %s" % outcome_text if not outcome_text.is_empty() else "", " · Next Shot Buffered" if buffered else ""]
	if buffered:
		return "Piercing Arrow Buffered · Waiting for an Action Window"
	# Only the latest accepted, still-live mark may replace routine feedback.
	# Reports alone can outlive their target/room; arbitrary domain diagnostics
	# are not player-facing text. Arrow actions and pointer warnings keep priority.
	var marked := enemy_by_id(snapshot, int(snapshot["marked_entity_id"]))
	if marked != null and marked.health > 0.0 and int(snapshot["sim_tick"]) < int(snapshot["hunter_mark_expires_tick"]):
		var mark_report := "Hunter's Mark locked: %s." % enemy_public_label(marked)
		if String(snapshot.get("battle_report", "")) == mark_report:
			return mark_report
	if snapshot["shots"] == 0:
		return "Proxy Approaching First Target" if snapshot["selected_mode"] == "Auto" else "Move Closer, Then Cast Piercing Arrow"
	if outcome_text == "Sacred Law Barrier Block" or outcome_text == "Piercing Arrow Missed":
		return outcome_text
	return "%s · Boss Damage %s · Defeated %d" % [outcome_text, snapshot["boss_damage"].to_short_string(4), snapshot["defeated"]] if snapshot["boss"] != null else "%s · Defeated %d · Remaining %d" % [outcome_text, snapshot["defeated"], snapshot["enemies"].size()]


func attack_state(snapshot: Dictionary, input_view: Dictionary) -> Dictionary:
	if not bool(snapshot.get("has_timeline", false)):
		return {"phase": "idle", "label": "", "phase_tick": 0, "phase_remaining_ticks": 0, "buffered": false, "request_open": snapshot["attack_cooldown_ticks"] <= PlayerActionTimelineScript.INPUT_BUFFER_TICKS, "target_entity_id": 0, "input_source": ""}
	var timeline: Dictionary = snapshot.get("timeline", {})
	var active: Dictionary = timeline.get("active", {})
	var buffered: Dictionary = timeline.get("buffered", {})
	var phase: String = String(snapshot.get("action_phase", "idle"))
	var label := ""
	var phase_tick := 0
	var phase_remaining_ticks := 0
	var lock_clear_tick: int = snapshot["sim_tick"]
	if not active.is_empty():
		var start_tick := int(active.get("start_tick", snapshot["sim_tick"]))
		var impact_tick := start_tick + int(active.get("windup_ticks", PlayerActionTimelineScript.WINDUP_TICKS))
		lock_clear_tick = impact_tick + PlayerActionTimelineScript.RECOVERY_TICKS
		if phase == PlayerActionTimelineScript.PHASE_WINDUP:
			label = "Draw"
			phase_tick = maxi(0, snapshot["sim_tick"] - start_tick)
			phase_remaining_ticks = maxi(0, impact_tick - snapshot["sim_tick"])
		elif phase == PlayerActionTimelineScript.PHASE_RECOVERY:
			label = "Release" if snapshot["sim_tick"] == impact_tick else "Recovery"
			phase_tick = maxi(0, snapshot["sim_tick"] - impact_tick)
			phase_remaining_ticks = maxi(0, lock_clear_tick - snapshot["sim_tick"])
	var ready_tick: int = snapshot["sim_tick"] + snapshot["attack_cooldown_ticks"]
	var eligible_tick := maxi(snapshot["sim_tick"], maxi(ready_tick, lock_clear_tick))
	var visible_request: Dictionary = active if not active.is_empty() else buffered
	var visible_request_id := int(visible_request.get("request_id", 0))
	return {
		"phase": phase,
		"label": label,
		"phase_tick": phase_tick,
		"phase_remaining_ticks": phase_remaining_ticks,
		"buffered": not buffered.is_empty(),
		"request_open": eligible_tick - snapshot["sim_tick"] <= PlayerActionTimelineScript.INPUT_BUFFER_TICKS,
		"target_entity_id": int(visible_request.get("target_entity_id", 0)),
		"request_id": visible_request_id,
		"input_source": String((input_view.get("request_sources", {}) as Dictionary).get(visible_request_id, "")),
	}


func attack_target(snapshot: Dictionary, input_view: Dictionary, attack_ui: Dictionary = {}) -> Dictionary:
	if attack_ui.is_empty():
		attack_ui = attack_state(snapshot, input_view)
	var held_source: String = String(input_view.get("held_source", ""))
	var input_snapshot: Dictionary = input_view.get("device", {})
	var pointer_lock_owned := bool(input_snapshot.get("pointer_world_held", false))
	var source := ATTACK_SOURCE_PROXY if snapshot["selected_mode"] == "Auto" else ATTACK_SOURCE_ASSISTED
	var pointer_target_id := 0
	var pointer_status := POINTER_STATUS_NONE
	if pointer_lock_owned:
		source = ATTACK_SOURCE_POINTER
		pointer_target_id = int(input_view.get("pointer_target_entity_id", 0))
		pointer_status = String(input_view.get("pointer_status", POINTER_STATUS_NONE))
	elif bool(input_view.get("edge_requested", false)) and String(input_view.get("edge_source", "")) == ATTACK_SOURCE_POINTER:
		source = ATTACK_SOURCE_POINTER
		pointer_target_id = int(input_view.get("edge_target_id", 0))
		pointer_status = POINTER_STATUS_LOCKED
	elif String(attack_ui.get("input_source", "")) == ATTACK_SOURCE_POINTER:
		source = ATTACK_SOURCE_POINTER
		pointer_target_id = int(attack_ui.get("target_entity_id", 0))
		pointer_status = POINTER_STATUS_LOCKED
	if source == ATTACK_SOURCE_POINTER:
		return pointer_target(snapshot, input_view, pointer_target_id, pointer_status)
	var target := preferred_target(snapshot)
	return {
		"source": source,
		"status": POINTER_STATUS_NONE if target != null else POINTER_STATUS_NO_TARGET,
		"target_entity_id": target.entity_id if target != null else 0,
		"has_target": target != null,
		"in_range": target != null and snapshot["player_position"].distance_to(target.position) <= snapshot["locked_targeting_distance"],
		"target_anchor": aim_resolver.target_anchor(aim_candidate(target)) if target != null else Vector2.ZERO,
		"target_radius": aim_resolver.target_radius(aim_candidate(target)) if target != null else 0.0,
	}.duplicate(true)


func pointer_target(snapshot: Dictionary, input_view: Dictionary, target_entity_id: int, fallback_status: String) -> Dictionary:
	var target := enemy_by_id(snapshot, target_entity_id)
	if target == null or target.health <= 0.0:
		return {
			"source": ATTACK_SOURCE_POINTER,
			"status": fallback_status if target_entity_id <= 0 else POINTER_STATUS_LOST,
			"target_entity_id": target_entity_id,
			"has_target": false,
			"in_range": false,
			"target_anchor": Vector2.ZERO,
			"target_radius": 0.0,
		}.duplicate(true)
	var candidate := aim_candidate(target)
	var in_range: bool = snapshot["player_position"].distance_to(target.position) <= snapshot["locked_targeting_distance"]
	return {
		"source": ATTACK_SOURCE_POINTER,
		"status": POINTER_STATUS_LOCKED if in_range else POINTER_STATUS_OUT_OF_RANGE,
		"target_entity_id": target.entity_id,
		"has_target": true,
		"in_range": in_range,
		"target_anchor": aim_resolver.target_anchor(candidate),
		"target_radius": aim_resolver.target_radius(candidate),
	}.duplicate(true)


func aim_candidate(enemy: CombatEnemyState) -> Dictionary:
	return {
		"entity_id": enemy.entity_id,
		"kind_id": enemy.kind_id,
		"position": enemy.position,
		"health": enemy.health,
		"is_boss": enemy.is_boss,
	}


func boss_remaining(snapshot: Dictionary) -> BigValue:
	if snapshot["boss"] == null:
		return BigValue.from_float(0.0)
	if snapshot["boss_damage"].compare(snapshot["boss_maximum"]) >= 0:
		return BigValue.from_float(0.0)
	if snapshot["boss_damage"].layer == 0 and snapshot["boss_maximum"].layer == 0:
		return BigValue.from_float(maxf(0.0, snapshot["boss_maximum"].magnitude - snapshot["boss_damage"].magnitude))
	return snapshot["boss_maximum"].duplicate_value()


func objective_label(snapshot: Dictionary) -> String:
	match snapshot["objective_id"]:
		"hunt_elite": return "Hunt Elites"
		"timed_break": return "Timed Defeat (Bonus %s)" % ("Active" if snapshot["timed_bonus_available"] else "Lost")
		_: return "Clear All Targets"


func hazard_status(snapshot: Dictionary) -> String:
	if snapshot["hazard_states"].is_empty():
		return "None"
	var parts: Array[String] = []
	for state in snapshot["hazard_states"]:
		parts.append("%s:%s" % [String(state.id), String(state.phase)])
	return ", ".join(parts)


func elite_status(snapshot: Dictionary) -> String:
	var elite := enemy_by_id(snapshot, snapshot["elite_entity_id"])
	if snapshot["battle_over"] or snapshot["elite_rule_ids"].is_empty() or elite == null or elite.health <= 0.0:
		return "None"
	var parts: Array[String] = []
	for rule in snapshot["elite_rule_ids"]:
		if rule == "periodic_barrier":
			parts.append("periodic_barrier:%s" % ("active" if snapshot["elite_barrier_active"] else "open"))
		elif rule == "summon_reinforcements":
			parts.append("summon_reinforcements:%s" % ("used" if snapshot["reinforcements_summoned"] else "ready"))
	return ", ".join(parts)


func preferred_target(snapshot: Dictionary) -> CombatEnemyState:
	var marked := enemy_by_id(snapshot, snapshot["marked_entity_id"])
	if marked != null and marked.health > 0.0 and snapshot["sim_tick"] < snapshot["hunter_mark_expires_tick"] and snapshot["player_position"].distance_to(marked.position) <= snapshot["locked_targeting_distance"]:
		return marked
	if snapshot["hunter_mark_candidate_entity_id"] > 0 and snapshot["sim_tick"] <= snapshot["hunter_mark_candidate_expires_tick"]:
		var candidate := enemy_by_id(snapshot, snapshot["hunter_mark_candidate_entity_id"])
		if candidate != null and candidate.health > 0.0 and snapshot["player_position"].distance_to(candidate.position) <= snapshot["locked_targeting_distance"]:
			return candidate
	return nearest_target(snapshot)


func nearest_target(snapshot: Dictionary, maximum_distance: float = INF) -> CombatEnemyState:
	var nearest: CombatEnemyState
	var best_distance: float = maximum_distance * maximum_distance
	for enemy: CombatEnemyState in snapshot["enemies"]:
		if enemy.health <= 0.0:
			continue
		var distance: float = snapshot["player_position"].distance_squared_to(enemy.position)
		if distance < best_distance or (is_equal_approx(distance, best_distance) and (nearest == null or enemy.entity_id < nearest.entity_id)):
			best_distance = distance
			nearest = enemy
	return nearest


func skill_equipped(snapshot: Dictionary, slot_index: int, expected_id: String) -> bool:
	var skills: Array = snapshot.get("equipped_skills", [])
	return slot_index >= 0 and slot_index < skills.size() and String(skills[slot_index]) == expected_id



func room_info(snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = room_catalog.presentation(snapshot["layout_id"])
	for key in ["display_name", "concept", "landmark", "entry_hint", "exit_hint"]:
		var authored := String(snapshot["framework_room"].get(key, "")).strip_edges()
		if not authored.is_empty():
			result[key] = authored
	return result
