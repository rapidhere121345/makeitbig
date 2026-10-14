extends SceneTree

const ResultScript := preload("res://src/game/combat_room_result.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var config := {
		"contract_id": "contract.result",
		"mode": "Manual",
		"preset_id": "critical",
		"seed": 17,
		"resolved_build": {"build_fingerprint": "a".repeat(64)},
		"room": {
			"room_id": "room.result",
			"objective_id": "timed_break",
			"layout_id": "ring",
			"drop_tags": ["inscribe_tally", "rewrite_tally"],
		},
	}
	var snapshot := {
		"room_reward_snapshot": {
			"add_dice_delta": 2,
			"rewrite_dice_delta": 3,
			"refine_dice_delta": 4,
			"drop_id": "must_not_escape",
			"bonus_earned": true,
		},
		"sim_tick": 31,
		"elapsed": 1.033,
		"shots": 5,
		"arrow_hits": 4,
		"defeated": 2,
		"battle_report": "done",
		"last_damage_source_id": "hazard/fire",
		"last_damage_tick": 29,
		"automation_smoke_failure": "",
	}
	var victory: Dictionary = ResultScript.build(config, snapshot, "victory")
	_expect(victory["room_id"] == "room.result" and victory["objective"] == "timed_break" and victory["layout"] == "ring", "result: room identity was not projected")
	_expect(int(victory["ticks"]) == 31 and int(victory["casts"]) == 5 and int(victory["defeated"]) == 2, "result: room counters were not projected")
	var rewards: Dictionary = victory["rewards"]
	var tallies: Dictionary = rewards["law_tallies_delta"]
	_expect(int(tallies["inscribe"]) == 3 and int(tallies["rewrite"]) == 4 and int(tallies["refine"]) == 4, "result: law tally normalization changed")
	_expect(not rewards.has("add_dice_delta") and not rewards.has("drop_id"), "result: internal reward fields leaked")
	_expect(not victory.has("failure_reason") and not victory.has("death_tick"), "result: victory exposed defeat fields")
	var defeat: Dictionary = ResultScript.build(config, snapshot, "defeat")
	_expect(String(defeat["failure_reason"]) == "hazard/fire" and int(defeat["death_tick"]) == 29, "result: defeat context was not projected")
	for field: String in ["last_damage_source_id", "last_damage_tick"]:
		var missing := snapshot.duplicate(true)
		missing.erase(field)
		var rejected: Dictionary = ResultScript.build(config, missing, "defeat")
		_expect(rejected.get("ok", true) == false and rejected.error == "missing_room_snapshot_field:" + field, "result: missing death field was silently projected: " + field)
		var invalid := snapshot.duplicate(true)
		invalid[field] = null
		rejected = ResultScript.build(config, invalid, "defeat")
		_expect(rejected.get("ok", true) == false and rejected.error == "invalid_room_snapshot_field:" + field, "result: null death field was silently projected: " + field)
	snapshot["room_reward_snapshot"]["add_dice_delta"] = 99
	_expect(int((victory["rewards"] as Dictionary).get("bonus_earned", 0)) == 1, "result: output was not deeply isolated")
	for failure: String in failures:
		printerr(failure)
	print("PASS test_combat_room_result.gd" if failures.is_empty() else "FAIL test_combat_room_result.gd")
	quit(0 if failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
