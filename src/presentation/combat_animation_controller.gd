class_name CombatAnimationController
extends RefCounted

## Owns animation readers, event latches, inferred walk clocks, detached corpses
## and the visual defeat window. Every method receives value snapshots; this
## controller has no path back to a gameplay actor or motor.

const RangerAnimationScript := preload("res://src/presentation/ranger_animation.gd")
const EnemyAnimationScript := preload("res://src/presentation/enemy_animation.gd")
const DefeatPresentationScript := preload("res://src/presentation/defeat_presentation.gd")
const RangerSkillRulesScript := preload("res://src/systems/ranger_skill_rules.gd")
const PlayerActionTimelineScript := preload("res://src/systems/player_action_timeline.gd")
const SIM_TICKS_PER_SECOND := RangerSkillRulesScript.TICKS_PER_SECOND
const DODGE_DURATION_TICKS := RangerSkillRulesScript.DODGE_DURATION_TICKS
const DASH_DURATION_TICKS := RangerSkillRulesScript.DASH_DURATION_TICKS
const DASH_TOTAL_DISTANCE := RangerSkillRulesScript.DASH_TOTAL_DISTANCE
const HUNTER_MARK_DURATION_TICKS := RangerSkillRulesScript.HUNTER_MARK_DURATION_TICKS
const HUNTER_MARK_RANGE_MULTIPLIER := RangerSkillRulesScript.HUNTER_MARK_RANGE_MULTIPLIER
const DODGE_COOLDOWN_TICKS := RangerSkillRulesScript.DODGE_COOLDOWN_TICKS

const RANGER_EVENT_SHOT := "ranger/shot"
const RANGER_EVENT_HIT := "ranger/hit"
const RANGER_EVENT_DEATH := "ranger/death"
const ENEMY_HIT_EVENT_KIND := "enemy/%d/hit"
const PLAYER_DAMAGE_OVERLAY_TICKS := 6

var enabled := true
var world_ready := false
var ranger_animation
var enemy_animation
var defeat_presentation
var ranger_action_pending_reason := ""
var enemy_animation_pending_reason := ""
var ranger_visual_time := 0.0
var ranger_death_seconds := 0.0
var ranger_frame: Dictionary = {}
var enemy_frames: Dictionary = {}
var enemy_watch: Dictionary = {}
var enemy_corpses: Array[Dictionary] = []


func load_assets() -> void:
	if not enabled:
		return
	ranger_animation = RangerAnimationScript.new()
	ranger_action_pending_reason = ranger_animation.pending_reason() if not ranger_animation.has_real_art() else ""
	enemy_animation = EnemyAnimationScript.new()
	enemy_animation_pending_reason = enemy_animation.pending_reason() if not enemy_animation.has_real_art() else ""
	defeat_presentation = DefeatPresentationScript.new(_death_clip_timing())


func reset() -> void:
	ranger_visual_time = 0.0
	ranger_death_seconds = 0.0
	ranger_frame.clear()
	_reset_enemy_animation()
	if ranger_animation != null:
		ranger_animation.clear_events()
	if defeat_presentation != null:
		defeat_presentation.reset()


func advance_time(snapshot: Dictionary, delta: float) -> void:
	if not enabled:
		return
	var step := maxf(0.0, delta)
	ranger_visual_time = fmod(ranger_visual_time + step, 10000.0)
	_advance_enemy_corpses(step)
	if float(snapshot["player_health"]) <= 0.0:
		if bool(snapshot["in_arena"]):
			ranger_death_seconds += step
		if ranger_animation != null and ranger_animation.latched_event_id(RANGER_EVENT_DEATH).is_empty():
			ranger_animation.latch_event(RANGER_EVENT_DEATH, "ranger:death:fallback", int(snapshot["sim_tick"]))
	else:
		ranger_death_seconds = 0.0
		if defeat_presentation != null:
			defeat_presentation.reset()


func commit(snapshot: Dictionary) -> void:
	if not enabled:
		return
	_refresh_ranger_frame(snapshot)
	_observe_enemy_animation(snapshot, 0.0)
	_refresh_enemy_frames(snapshot)


func observe_frame(delta: float) -> void:
	if defeat_presentation != null:
		defeat_presentation.observe_frame(ranger_frame, delta)


func handle_event(event: Dictionary, tick: int) -> void:
	var event_tick := int(event.get("tick", tick))
	var token := "combat:%d" % int(event.get("event_id", 0))
	match String(event.get("type", "")):
		"action_accepted":
			if ranger_animation != null and String(event.get("actor_id", "")) == "ranger" and String(event.get("action_id", "")) == "piercing_arrow":
				ranger_animation.latch_event(RANGER_EVENT_SHOT, token, event_tick)
		"damage_applied":
			if String(event.get("target_id", "")) == "ranger":
				if ranger_animation != null:
					ranger_animation.latch_event(RANGER_EVENT_HIT, token, event_tick)
			elif enemy_animation != null and int(event.get("target_entity_id", 0)) > 0:
				enemy_animation.latch_event(_enemy_hit_event_kind(int(event["target_entity_id"])), token, event_tick)
		"death_applied":
			if ranger_animation != null and String(event.get("target_id", "")) == "ranger":
				ranger_animation.latch_event(RANGER_EVENT_DEATH, token, event_tick)


func detach_corpse(visual: Dictionary) -> void:
	if not enabled or not world_ready or enemy_animation == null or bool(visual.get("is_boss", false)):
		return
	var corpse := visual.duplicate(true)
	corpse["role"] = "charger" if String(visual.get("kind_id", "")) == "charging_raider" else ("fan" if String(visual.get("kind_id", "")) == "fan_ranged" else "melee")
	corpse["seconds"] = 0.0
	corpse["frame"] = {}
	enemy_corpses.append(corpse)
	enemy_watch.erase(int(visual.get("entity_id", 0)))


func scaled_ticks(snapshot: Dictionary, base_ticks: int, capability: String) -> int:
	return maxi(1, int(round(float(base_ticks) * (1.0 + clampf(float(snapshot.get("talent_capabilities", {}).get(capability, 0.0)), -1.0, 10.0)))))


func _death_clip_timing() -> Dictionary:
	if ranger_animation == null:
		return {}
	for facing: String in RangerAnimationScript.FACINGS:
		var info: Dictionary = ranger_animation.clip_info(RangerAnimationScript.clip_id(facing, DefeatPresentationScript.ACTION_DEATH))
		var frames: Array = info.get("frames", [])
		if frames.is_empty():
			continue
		return {
			"frames": frames.size(),
			"fps": maxi(1, int(info.get("fps", DefeatPresentationScript.CLIP_FPS))),
		}
	return {}


func _refresh_ranger_frame(snapshot: Dictionary) -> void:
	if ranger_animation == null:
		ranger_frame = {}
		return
	var frame: Dictionary = ranger_animation.resolve(ranger_state(snapshot))
	ranger_frame = {} if bool(frame.get("fallback", true)) else frame


func _observe_enemy_animation(snapshot: Dictionary, delta: float) -> void:
	_advance_enemy_corpses(delta)
	if enemy_animation == null or not world_ready:
		return
	var live := {}
	for enemy: CombatEnemyState in snapshot["enemies"]:
		if enemy.is_boss:
			continue
		live[enemy.entity_id] = true
		var record: Dictionary = enemy_watch.get(enemy.entity_id, {})
		if record.is_empty():
			enemy_watch[enemy.entity_id] = {"position": enemy.position, "health": enemy.health, "moving": false, "walk_ticks": 0, "tick": snapshot["sim_tick"]}
			continue
		var advanced: int = snapshot["sim_tick"] - int(record.get("tick", snapshot["sim_tick"]))
		if advanced <= 0:
			continue
		var moved: bool = enemy.position != (record["position"] as Vector2)
		record["health"] = enemy.health
		record["position"] = enemy.position
		record["moving"] = moved
		record["walk_ticks"] = int(record.get("walk_ticks", 0)) + advanced if moved else 0
		record["tick"] = snapshot["sim_tick"]
	for entity_id: int in enemy_watch.keys():
		if not live.has(entity_id):
			enemy_watch.erase(entity_id)


func _enemy_hit_event_kind(entity_id: int) -> String:
	return ENEMY_HIT_EVENT_KIND % entity_id


func _advance_enemy_corpses(delta: float) -> void:
	if enemy_corpses.is_empty():
		return
	var kept: Array[Dictionary] = []
	for corpse: Dictionary in enemy_corpses:
		corpse["seconds"] = maxf(0.0, float(corpse.get("seconds", 0.0))) + delta
		if _corpse_ticks(corpse) <= corpse_window_ticks(corpse):
			kept.append(corpse)
	enemy_corpses = kept


func _corpse_ticks(corpse: Dictionary) -> int:
	return roundi(maxf(0.0, float(corpse.get("seconds", 0.0))) * float(EnemyAnimationScript.SIM_TICKS_PER_SECOND))


func corpse_window_ticks(corpse: Dictionary) -> int:
	var death_ticks := EnemyAnimationScript.agreed_duration_ticks("death")
	if enemy_animation != null:
		death_ticks = enemy_animation.clip_duration_ticks(String(corpse.get("role", "melee")), "death")
	return death_ticks + EnemyAnimationScript.CORPSE_HOLD_TICKS


func _reset_enemy_animation() -> void:
	enemy_watch.clear()
	enemy_corpses.clear()
	enemy_frames.clear()
	if enemy_animation != null:
		enemy_animation.clear_events()


func _refresh_enemy_frames(snapshot: Dictionary) -> void:
	enemy_frames = {}
	if enemy_animation == null or not world_ready:
		return
	for enemy: CombatEnemyState in snapshot["enemies"]:
		if enemy.is_boss:
			continue
		enemy_frames[enemy.entity_id] = enemy_animation.resolve(enemy_state(snapshot, enemy))
	for corpse: Dictionary in enemy_corpses:
		corpse["frame"] = enemy_animation.resolve(_corpse_animation_state(snapshot, corpse))


func enemy_state(snapshot: Dictionary, enemy: CombatEnemyState) -> Dictionary:
	var record: Dictionary = enemy_watch.get(enemy.entity_id, {})
	return {
		"role": _enemy_role_id(enemy),
		"facing": enemy.facing,
		"action_state": enemy.action_state,
		"state_started_tick": enemy.state_started_tick,
		"state_ends_tick": enemy.state_ends_tick,
		"moving": bool(record.get("moving", false)),
		"phase_ticks": _enemy_walk_phase_ticks(record),
		"hit_ticks": enemy_animation.latched_ticks(_enemy_hit_event_kind(enemy.entity_id), snapshot["sim_tick"]),
		"dead": false,
		"death_ticks": 0,
		"tick": snapshot["sim_tick"],
	}


func _enemy_walk_phase_ticks(record: Dictionary) -> int:
	return maxi(0, int(record.get("walk_ticks", 0)))


func _corpse_animation_state(snapshot: Dictionary, corpse: Dictionary) -> Dictionary:
	return {
		"role": String(corpse.get("role", "melee")),
		"facing": corpse.get("facing", Vector2.RIGHT),
		"action_state": "none",
		"moving": false,
		"phase_ticks": 0,
		"hit_ticks": -1,
		"dead": true,
		"death_ticks": _corpse_ticks(corpse),
		"tick": snapshot["sim_tick"],
	}


func enemy_animation_report(snapshot: Dictionary) -> Dictionary:
	var live: Array[Dictionary] = []
	for enemy: CombatEnemyState in snapshot["enemies"]:
		if enemy.is_boss:
			continue
		var frame: Dictionary = enemy_frames.get(enemy.entity_id, {})
		live.append({
			"entity_id": enemy.entity_id,
			"role": _enemy_role_id(enemy),
			"action_state": enemy.action_state,
			"action": String(frame.get("action", "")),
			"clip": String(frame.get("clip", "")),
			"frame": int(frame.get("frame", -1)),
			"rect": frame.get("rect", Rect2i()),
			"anchor": frame.get("anchor", Vector2i.ZERO),
			"flip_x": bool(frame.get("flip_x", false)),
			"fallback": bool(frame.get("fallback", true)),
			"reason": String(frame.get("reason", "")),
		})
	var corpses: Array[Dictionary] = []
	for corpse: Dictionary in enemy_corpses:
		corpses.append({
			"entity_id": int(corpse.get("entity_id", 0)),
			"role": String(corpse.get("role", "")),
			"ticks": _corpse_ticks(corpse),
			"window_ticks": corpse_window_ticks(corpse),
			"frame": int((corpse.get("frame", {}) as Dictionary).get("frame", -1)),
		})
	var report := {
		"pending_reason": enemy_animation_pending_reason,
		"asset_state": enemy_animation.asset_state() if enemy_animation != null else "",
		"production": enemy_animation.production_report() if enemy_animation != null else {},
		"live": live,
		"corpses": corpses,
	}
	if enemy_animation != null:
		report["reader"] = enemy_animation.integration_report()
	return report


func ranger_state(snapshot: Dictionary) -> Dictionary:
	var timeline_snapshot: Dictionary = snapshot.get("timeline", {})
	var active_action: Dictionary = timeline_snapshot.get("active", {})
	var shoot_ticks := -1
	if not active_action.is_empty():
		var action_elapsed := maxi(0, snapshot["sim_tick"] - int(active_action.get("start_tick", snapshot["sim_tick"])))
		var windup := maxi(1, int(active_action.get("windup_ticks", PlayerActionTimelineScript.WINDUP_TICKS)))
		shoot_ticks = floori(float(action_elapsed * PlayerActionTimelineScript.WINDUP_TICKS) / float(windup)) if action_elapsed < windup else PlayerActionTimelineScript.WINDUP_TICKS + action_elapsed - windup
	var state := {
		"facing": snapshot["player_facing"],
		"dead": snapshot["player_health"] <= 0.0,
		"death_ticks": roundi(ranger_death_seconds * float(RangerAnimationScript.SIM_TICKS_PER_SECOND)),
		"hit_ticks": -1,
		"dodge_ticks": maxi(0, snapshot["sim_tick"] - snapshot["dodge_started_tick"]) if snapshot["dodge_remaining_ticks"] > 0 and snapshot["dodge_started_tick"] >= 0 else -1,
		"dodge_window_ticks": DODGE_DURATION_TICKS,
		"dash_ticks": maxi(0, snapshot["sim_tick"] - snapshot["dash_started_tick"]) if snapshot["dash_remaining_ticks"] > 0 and snapshot["dash_started_tick"] >= 0 else -1,
		"dash_window_ticks": scaled_ticks(snapshot, DASH_DURATION_TICKS, "dash_duration_multiplier"),
		"shoot_ticks": shoot_ticks,
		"shoot_window_ticks": PlayerActionTimelineScript.WINDUP_TICKS + PlayerActionTimelineScript.RECOVERY_TICKS,
		"moving": (snapshot["player_last_displacement"] as Vector2).length_squared() > 0.000001,
		"phase_ticks": snapshot["sim_tick"],
		"tick": snapshot["sim_tick"],
	}
	if ranger_animation != null:
		state["hit_ticks"] = ranger_animation.latched_ticks(RANGER_EVENT_HIT, snapshot["sim_tick"])
	return state


func ranger_animation_report(snapshot: Dictionary) -> Dictionary:
	var report := {
		"pending_reason": ranger_action_pending_reason,
		"state": ranger_state(snapshot),
		"frame": ranger_frame,
		"death_clip_visible": snapshot["in_arena"] and snapshot["player_health"] <= 0.0 and clip_drawable(),
	}
	if ranger_animation != null:
		report["reader"] = ranger_animation.integration_report()
	return report


func defeat_hold_reason(snapshot: Dictionary) -> String:
	if not enabled:
		return ""
	if not snapshot["in_arena"]:
		return ""
	if snapshot["battle_victory"]:
		return ""
	if snapshot["player_health"] > 0.0:
		return ""
	if defeat_presentation == null:
		return ""
	if not clip_drawable():
		return ""
	if defeat_presentation.route_ready():
		return ""
	return DefeatPresentationScript.HOLD_REASON


func defeat_route_ready(snapshot: Dictionary) -> bool:
	return defeat_hold_reason(snapshot).is_empty()


func clip_drawable() -> bool:
	return world_ready and ranger_animation != null and ranger_animation.has_real_art()


func defeat_skip_presentation(reason: String = "skipped") -> void:
	if defeat_presentation == null:
		return
	defeat_presentation.skip(reason)


func defeat_presentation_report(snapshot: Dictionary) -> Dictionary:
	var window_report: Dictionary = defeat_presentation.report() if defeat_presentation != null else {}
	return {
		"route_ready": defeat_route_ready(snapshot),
		"hold_reason": defeat_hold_reason(snapshot),
		"clip_drawable": clip_drawable(),
		"presentation_enabled": enabled,
		"battle_over": snapshot["battle_over"],
		"battle_victory": snapshot["battle_victory"],
		"dead": snapshot["player_health"] <= 0.0,
		"death_seconds": ranger_death_seconds,
		"death_ticks": roundi(ranger_death_seconds * float(RangerAnimationScript.SIM_TICKS_PER_SECOND)),
		"sim_tick": snapshot["sim_tick"],
		"window": window_report,
	}


func _player_damage_overlay_state(snapshot: Dictionary) -> Dictionary:
	if ranger_animation == null or snapshot["player_health"] <= 0.0:
		return {}
	var age_ticks: int = ranger_animation.latched_ticks(RANGER_EVENT_HIT, snapshot["sim_tick"])
	if age_ticks < 0 or age_ticks >= PLAYER_DAMAGE_OVERLAY_TICKS:
		return {}
	var alpha := clampf(0.92 - 0.10 * float(age_ticks), 0.32, 0.92)
	return {
		"event_id": ranger_animation.latched_event_id(RANGER_EVENT_HIT),
		"age_ticks": age_ticks,
		"duration_ticks": PLAYER_DAMAGE_OVERLAY_TICKS,
		"alpha": alpha,
		"offset": Vector2(1.0 if age_ticks % 2 == 0 else -1.0, 0.0),
	}


func _enemy_role_id(enemy: CombatEnemyState) -> String:
	match enemy.kind_id:
		"charging_raider": return "charger"
		"fan_ranged": return "ranged"
		_: return "melee"
