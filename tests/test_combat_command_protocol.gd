extends SceneTree

const Protocol := preload("res://src/systems/combat_command_protocol.gd")
const Assert := preload("res://tests/helpers/assert.gd")
const TICK := 42
const ACTOR := "ranger-1"
const EQUIPPED := ["piercing_arrow", "hunter_mark", "dash"]


func _initialize() -> void:
	var failures: Array[String] = []
	_test_strict_fields_and_normalization(failures)
	_test_tick_and_legality_rejections(failures)
	_test_source_independence(failures)
	_test_array_order_invariance(failures)
	_test_dodge_dash_overlap(failures)
	_test_mark_before_arrow(failures)
	_test_dash_arrow_conflict(failures)
	_test_duplicate_move(failures)
	_test_deterministic_receipts(failures)
	if failures.is_empty():
		print("PASS  test_combat_command_protocol.gd")
		quit(0)
		return
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _test_strict_fields_and_normalization(failures: Array[String]) -> void:
	var command := Protocol.move(TICK, ACTOR, 7, 1000, -250, 600)
	var receipt := Protocol.validate(command, TICK, EQUIPPED)
	_expect(receipt.status == "accepted" and receipt.reason == "ok", "valid move was rejected", failures)
	_expect(receipt.command.keys() == ["protocol_version", "tick", "actor_id", "sequence", "kind", "direction_x_milli", "direction_y_milli", "speed_milli"], "move normalization did not produce stable field order", failures)
	_expect(receipt.command == command, "normalized command value changed", failures)

	var missing := command.duplicate()
	missing.erase("speed_milli")
	_expect(Protocol.validate(missing, TICK, EQUIPPED).reason == "missing_field", "missing field reason changed", failures)
	var extra := command.duplicate()
	extra.source = "Manual"
	_expect(Protocol.validate(extra, TICK, EQUIPPED).reason == "extra_field", "extra field was accepted", failures)
	var bad_direction := Protocol.dodge(TICK, ACTOR, 1, 1001, 0)
	_expect(Protocol.validate(bad_direction, TICK, EQUIPPED).reason == "invalid_direction", "out-of-range direction was accepted", failures)
	var bad_speed := Protocol.move(TICK, ACTOR, 1, 1, 0, -1)
	_expect(Protocol.validate(bad_speed, TICK, EQUIPPED).reason == "invalid_speed", "out-of-range speed was accepted", failures)


func _test_tick_and_legality_rejections(failures: Array[String]) -> void:
	_expect(Protocol.validate(Protocol.stop_move(TICK - 1, ACTOR, 1), TICK, EQUIPPED).reason == "stale_tick", "stale tick reason changed", failures)
	_expect(Protocol.validate(Protocol.stop_move(TICK + 1, ACTOR, 1), TICK, EQUIPPED).reason == "future_tick", "future tick reason changed", failures)
	var wrong_protocol := Protocol.stop_move(TICK, ACTOR, 1)
	wrong_protocol.protocol_version = 1
	_expect(Protocol.validate(wrong_protocol, TICK, EQUIPPED).reason == "wrong_protocol", "wrong protocol was accepted", failures)
	_expect(Protocol.validate(Protocol.cast(TICK, ACTOR, 1, "unknown", 9), TICK, EQUIPPED).reason == "unknown_ability", "unknown cast reason changed", failures)
	_expect(Protocol.validate(Protocol.cast(TICK, ACTOR, 1, "dash", 0, 1000, 0), TICK, ["piercing_arrow"]).reason == "ability_not_equipped", "unequipped ability was accepted", failures)
	_expect(Protocol.validate(Protocol.cast(TICK, ACTOR, 1, "piercing_arrow", 0, 1000, 0), TICK, EQUIPPED).reason == "invalid_target", "invalid target was accepted", failures)
	_expect(Protocol.validate(Protocol.cast(TICK, ACTOR, 1, "piercing_arrow", 9), TICK, EQUIPPED).reason == "missing_field", "arrow without explicit aim was accepted", failures)
	_expect(Protocol.validate(Protocol.cast(TICK, ACTOR, 1, "dash", 0, 1000, 0), TICK, EQUIPPED).status == "accepted", "directional dash required a target", failures)
	_expect(Protocol.validate(Protocol.cast(TICK, ACTOR, 1, "dash", 0), TICK, EQUIPPED).reason == "missing_field", "dash without explicit direction was accepted", failures)
	_expect(Protocol.validate(Protocol.dodge(TICK, ACTOR, 1, 0, 1000), TICK, EQUIPPED, false).reason == "dodge_not_allowed", "disabled dodge was accepted", failures)


func _test_source_independence(failures: Array[String]) -> void:
	var manual := Protocol.cast(TICK, ACTOR, 4, "piercing_arrow", 11, 1000, 0)
	var auto := Protocol.cast(TICK, ACTOR, 4, "piercing_arrow", 11, 1000, 0)
	_expect(Protocol.validate(manual, TICK, EQUIPPED) == Protocol.validate(auto, TICK, EQUIPPED), "identical Manual and Auto public commands produced different receipts", failures)
	_expect(not manual.has("source") and not auto.has("source"), "constructors leaked source into authority schema", failures)


func _test_array_order_invariance(failures: Array[String]) -> void:
	var commands := [
		Protocol.move(TICK, "ranger-b", 9, 1000, 0, 500),
		Protocol.cast(TICK, ACTOR, 4, "piercing_arrow", 11, 1000, 0),
		Protocol.cast(TICK, ACTOR, 2, "hunter_mark", 11),
		Protocol.move(TICK, ACTOR, 8, 0, 1000, 700),
	]
	var reversed := commands.duplicate()
	reversed.reverse()
	_expect(Protocol.arbitrate(commands, TICK, EQUIPPED) == Protocol.arbitrate(reversed, TICK, EQUIPPED), "arbitration changed with input array order", failures)


func _test_dodge_dash_overlap(failures: Array[String]) -> void:
	var result := Protocol.arbitrate([
		Protocol.cast(TICK, ACTOR, 1, "dash", 11, 1000, 0),
		Protocol.dodge(TICK, ACTOR, 99, 0, -1000),
	], TICK, EQUIPPED)
	_expect(result.commands.size() == 1 and result.commands[0].kind == "dodge", "dodge did not win fixed mobility priority over dash", failures)
	_expect(_reason_for(result.receipts, "cast", "dash", 1) == "action_conflict", "losing dash receipt reason changed", failures)


func _test_mark_before_arrow(failures: Array[String]) -> void:
	var result := Protocol.arbitrate([
		Protocol.cast(TICK, ACTOR, 1, "piercing_arrow", 12, 1000, 0),
		Protocol.cast(TICK, ACTOR, 20, "hunter_mark", 12),
	], TICK, EQUIPPED)
	_expect(result.commands.size() == 2, "compatible mark and arrow were not both accepted", failures)
	_expect(result.commands[0].ability_id == "hunter_mark" and result.commands[1].ability_id == "piercing_arrow", "hunter mark was not ordered before piercing arrow", failures)


func _test_dash_arrow_conflict(failures: Array[String]) -> void:
	var result := Protocol.arbitrate([
		Protocol.cast(TICK, ACTOR, 1, "piercing_arrow", 13, 1000, 0),
		Protocol.cast(TICK, ACTOR, 20, "dash", 0, 1000, 0),
	], TICK, EQUIPPED)
	_expect(result.commands.size() == 1 and result.commands[0].ability_id == "dash", "dash did not win fixed action priority over arrow", failures)
	_expect(_reason_for(result.receipts, "cast", "piercing_arrow", 1) == "action_conflict", "losing arrow receipt reason changed", failures)


func _test_duplicate_move(failures: Array[String]) -> void:
	var result := Protocol.arbitrate([
		Protocol.move(TICK, ACTOR, 8, 1000, 0, 900),
		Protocol.stop_move(TICK, ACTOR, 3),
		Protocol.cast(TICK, ACTOR, 1, "hunter_mark", 14),
	], TICK, EQUIPPED)
	_expect(result.commands.size() == 2 and result.commands[-1].kind == "stop_move" and result.commands[-1].sequence == 3, "duplicate movement commands did not keep the lowest sequence after actions", failures)
	_expect(_reason_for(result.receipts, "move", "", 8) == "duplicate_move", "duplicate move receipt reason changed", failures)


func _test_deterministic_receipts(failures: Array[String]) -> void:
	var malformed := Protocol.stop_move(TICK, "", 5)
	var commands := [
		Protocol.move(TICK, ACTOR, 8, 1000, 0, 500),
		Protocol.move(TICK, ACTOR, 3, 0, 1000, 500),
		Protocol.cast(TICK, ACTOR, 2, "unknown", 1),
		malformed,
	]
	var first := Protocol.arbitrate(commands, TICK, EQUIPPED)
	var permuted := [commands[2], commands[0], commands[3], commands[1]]
	var second := Protocol.arbitrate(permuted, TICK, EQUIPPED)
	_expect(first == second, "receipt order or content depended on input order", failures)
	_expect(first.receipts.size() == commands.size(), "arbitration did not return one receipt per input", failures)
	_expect(_reason_for(first.receipts, "cast", "unknown", 2) == "unknown_ability", "validation receipt was lost during arbitration", failures)


func _reason_for(receipts: Array, kind: String, ability_id: String, sequence: int) -> String:
	for receipt in receipts:
		var command: Dictionary = receipt.command
		if command.get("kind") == kind and int(command.get("sequence", -1)) == sequence:
			if ability_id.is_empty() or command.get("ability_id") == ability_id:
				return String(receipt.reason)
	return "missing_receipt"


func _expect(condition: bool, message: String, failures: Array[String]) -> void: Assert.expect(condition, message, failures)
