extends SceneTree

const RoomRules := preload("res://src/game/combat_room_rules.gd")
const Content := preload("res://src/content/content_registry.gd")
const Rng := preload("res://src/core/deterministic_rng.gd")
const RoomRewardPortScript := preload("res://src/runtime/world/room_reward_port.gd")

class CollectRewardPort extends RoomRewardPortScript:
	var commits: Array[Dictionary] = []

	func commit(reward: Dictionary) -> Dictionary:
		commits.append(reward.duplicate(true))
		return {"ok": true, "error": ""}

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_terminal_priorities()
	_test_legacy_rewards()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	if failures.is_empty():
		print("PASS test_combat_room_rules.gd (terminal priority, embedded and legacy rewards)")
	quit(0 if failures.is_empty() else 1)


func _encounter() -> Dictionary:
	return {"has_boss": false, "boss_health": 10.0, "enemy_count": 1, "elite_entity_id": 7, "elite_alive": false, "elite_rule_ids": [], "timed_bonus_available": false, "elapsed": 2.0, "shots": 3, "defeated": 1}


func _test_terminal_priorities() -> void:
	var rules := RoomRules.new()
	var encounter := _encounter()
	rules.reset_for_room({"objective_id": "hunt_elite", "drop_tags": ["add_dice"]}, true, "Manual", 52969, {}, null)
	var terminal := rules.observe({"player_health": 0.0}, encounter)
	_expect(terminal.changed and terminal.state.battle_victory, "elite completion lost same-tick priority over death")
	_expect(terminal.state.room_reward_snapshot.add_dice_delta == 1, "embedded legacy tally tag changed")
	_expect(not rules.observe({"player_health": 0.0}, encounter).changed, "room settled twice")
	var published := rules.snapshot()
	published.room_reward_snapshot.add_dice_delta = 99
	_expect(rules.snapshot().room_reward_snapshot.add_dice_delta == 1, "room reward snapshot exposed mutable authority")
	rules.reset_for_room({"objective_id": "hunt_elite", "drop_tags": []}, true, "Manual", 52969, {}, null)
	encounter.elite_rule_ids = ["summon_reinforcements"]
	_expect(not rules.observe({"player_health": 1.0}, encounter).changed, "elite completion bypassed remaining reinforcements")
	encounter.enemy_count = 0
	_expect(rules.observe({"player_health": 0.0}, encounter).state.battle_victory, "reinforcement clear lost same-tick priority")
	rules.reset_for_room({"objective_id": "clear", "drop_tags": []}, true, "Manual", 52969, {}, null)
	encounter.has_boss = true
	encounter.boss_health = 10.0
	_expect(not rules.observe({"player_health": 1.0}, encounter).changed, "empty adds bypassed a living boss")
	encounter.boss_health = 0.0
	_expect(rules.observe({"player_health": 0.0}, encounter).state.battle_victory, "boss defeat lost same-tick priority")
	rules.reset_for_room({"objective_id": "timed_break", "drop_tags": ["rewrite_dice", "refine_dice"]}, true, "Auto", 52969, {}, null)
	encounter.has_boss = false
	var reward: Dictionary = rules.observe({"player_health": 1.0}, encounter).state.room_reward_snapshot
	_expect(reward.bonus_lost and not reward.bonus_earned and reward.rewrite_dice_delta == 1 and reward.refine_dice_delta == 1, "lost timed bonus changed base rewards")
	rules.reset_for_room({"objective_id": "clear", "drop_tags": []}, true, "Manual", 52969, {}, null)
	encounter.enemy_count = 1
	var defeat := rules.observe({"player_health": 0.0}, encounter)
	_expect(defeat.changed and not defeat.state.battle_victory and defeat.state.room_reward_snapshot == RoomRules.empty_reward(), "ordinary death granted victory rewards")


func _test_legacy_rewards() -> void:
	var content := Content.new()
	_expect(content.load_all().is_empty(), "content fixture failed")
	for mode in ["Manual", "Auto"]:
		var reward_port := CollectRewardPort.new()
		var rules := RoomRules.new()
		var configured := rules.reset_for_room({"objective_id": "clear", "drop_tags": []}, false, mode, 52969, {"contract_wins": 0, "cores": content.cores}, reward_port)
		_expect(configured.ok, "legacy room reward port rejected")
		var encounter := _encounter()
		encounter.enemy_count = 0
		rules.observe({"player_health": 100.0}, encounter)
		rules.observe({"player_health": 100.0}, encounter)
		var expected := _old_reward(content, mode)
		_expect(reward_port.commits.size() == 1 and reward_port.commits[0].last_drop_id == expected.id and reward_port.commits[0].dice_awarded == expected.dice and reward_port.commits[0].last_loot_rng_state == expected.rng, "legacy %s reward RNG/order/once semantics changed" % mode)


func _old_reward(content, mode: String) -> Dictionary:
	var ids: Array = content.core_ids()
	ids.sort()
	var rng = Rng.create(52969, "contract_drop/1")
	var id: String = ids[rng.next_int(ids.size())]
	var dice := 1
	if mode == "Manual" and rng.next_float() < 0.35:
		dice += 1
	return {"id": id, "dice": dice, "rng": rng.export_state()}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
