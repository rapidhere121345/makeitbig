class_name CombatRoomRules
extends RefCounted

## Room terminal decisions and one-shot reward commits. Player and encounter
## storage stay in their domains; inputs here are detached observations.
const Rng := preload("res://src/core/deterministic_rng.gd")
const Forge := preload("res://src/systems/destiny_forge.gd")
const MANUAL_BONUS_CHANCE := 0.35

var _state: Dictionary = {}
var _room: Dictionary = {}
var _embedded := true
var _mode := "Manual"
var _seed := 0
var _legacy: Dictionary = {}
var _commit_legacy: Callable


func _init() -> void:
	reset()


func reset() -> void:
	_state = {"battle_over": false, "battle_victory": false, "report": "", "room_reward_snapshot": empty_reward()}


func reset_for_room(room: Dictionary, embedded: bool, mode: String, seed: int, legacy: Dictionary, commit_legacy: Callable) -> Dictionary:
	if mode not in ["Manual", "Auto"] or not room.get("drop_tags", []) is Array:
		return {"ok": false, "error": "invalid_room_rules_context"}
	if not embedded and (not commit_legacy.is_valid() or (legacy.get("cores", {}) as Dictionary).is_empty()):
		return {"ok": false, "error": "legacy_room_reward_port_unavailable"}
	_room = room.duplicate(true)
	_embedded = embedded
	_mode = mode
	_seed = seed
	_legacy = legacy.duplicate(true)
	_commit_legacy = commit_legacy
	reset()
	return {"ok": true, "error": ""}


func snapshot() -> Dictionary:
	return _state.duplicate(true)


func observe(player: Dictionary, encounter: Dictionary) -> Dictionary:
	if bool(_state.battle_over):
		return {"changed": false, "state": snapshot()}
	var has_boss := bool(encounter.has_boss)
	var empty := int(encounter.enemy_count) == 0
	var victory := has_boss and float(encounter.boss_health) <= 0.0
	if not has_boss and String(_room.get("objective_id", "clear")) == "hunt_elite" and int(encounter.elite_entity_id) > 0 and not bool(encounter.elite_alive):
		victory = empty if "summon_reinforcements" in encounter.elite_rule_ids else true
	if not has_boss and empty:
		victory = true
	# Preserve the legacy same-tick priority: a completed objective wins even if
	# a hostile/hazard impact also reduced player health to zero in this tick.
	if not victory and float(player.player_health) > 0.0:
		return {"changed": false, "state": snapshot()}
	_state.battle_over = true
	_state.battle_victory = victory
	if victory:
		var summary := _victory_reward(bool(encounter.timed_bonus_available))
		_state.report = "VICTORY — Room cleared in %.1fs, %d casts, %d targets. %s" % [float(encounter.elapsed), int(encounter.shots), int(encounter.defeated), summary]
	else:
		_state.report = "DEFEAT — The ranger fell after %.1fs. Refit at base." % float(encounter.elapsed)
	return {"changed": true, "state": snapshot()}


func fail(reason: String) -> void:
	_state.battle_over = true
	_state.battle_victory = false
	_state.report = "AUTOMATION FAILURE — %s" % reason


func _victory_reward(timed_bonus_available: bool) -> String:
	if _embedded:
		var reward := empty_reward()
		var tags: Array = _room.get("drop_tags", [])
		for track: String in ["add", "rewrite", "refine"]:
			reward[track + "_dice_delta"] = 1 if track + "_dice" in tags else 0
		if String(_room.get("objective_id", "clear")) == "timed_break":
			reward.bonus_earned = timed_bonus_available
			reward.bonus_lost = not timed_bonus_available
		_state.room_reward_snapshot = reward
		var bonus := " Timed bonus lost; base room rewards preserved." if bool(reward.bonus_lost) else ""
		return "Room reward: Inscription Tallies %d · Rewrite Tallies %d · Refinement Tallies %d.%s" % [int(reward.add_dice_delta), int(reward.rewrite_dice_delta), int(reward.refine_dice_delta), bonus]
	var wins := int(_legacy.get("contract_wins", 0)) + 1
	var cores: Dictionary = _legacy.cores
	var ids: Array = cores.keys()
	ids.sort()
	var rng = Rng.create(_seed, "contract_drop/%d" % wins)
	var drop_id := String(ids[rng.next_int(ids.size())])
	var drop: Dictionary = cores[drop_id]
	var label := "%s [%s]" % [String(drop.name), String(drop.slot)]
	var dice := 1
	var bonus := ""
	if _mode == "Manual" and rng.next_float() < MANUAL_BONUS_CHANCE:
		dice += 1
		bonus = " Manual Hunter Cache triggered."
	_commit_legacy.call({"contract_wins": wins, "last_drop_id": drop_id, "last_drop": label, "last_loot_rng_state": rng.export_state(), "track": Forge.TRACK_ADD, "dice_awarded": dice, "save_reason": "Contract reward saved"})
	return "Drop: %s; +%d Inscription Tally.%s No timer; no regeneration." % [label, dice, bonus]


static func empty_reward() -> Dictionary:
	return {"add_dice_delta": 0, "rewrite_dice_delta": 0, "refine_dice_delta": 0, "bonus_earned": false, "bonus_lost": false}
