extends SceneTree

const Protocol := preload("res://src/systems/combat_loot_pickup_protocol.gd")
const Assert := preload("res://tests/helpers/assert.gd")
const TICK := 120
const ACTOR := "ranger"
const LOOT_ID := "drop-007"


func _initialize() -> void:
	var failures: Array[String] = []
	_test_valid_request_shape(failures)
	_test_tick_rejections(failures)
	_test_missing_fields(failures)
	_test_extra_fields(failures)
	_test_bad_types(failures)
	_test_empty_ids(failures)
	_test_arbitrate_duplicates(failures)
	_test_stable_ordering(failures)
	_test_actor_scope(failures)
	_test_detached_returns(failures)
	if failures.is_empty():
		print("PASS  test_combat_loot_pickup_protocol.gd")
		quit(0)
		return
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _test_valid_request_shape(failures: Array[String]) -> void:
	_expect(Protocol.PROTOCOL_VERSION == 1, "protocol version must stay 1", failures)
	_expect(Protocol.KIND_LOOT_PICKUP == "loot_pickup", "kind constant changed", failures)

	var request := Protocol.make_request(TICK, ACTOR, 4, LOOT_ID)
	_expect(request.keys() == ["protocol_version", "tick", "actor_id", "sequence", "kind", "loot_entity_id"], "make_request did not produce the stable field order", failures)
	_expect(Protocol.make_request(TICK, ACTOR, 4, LOOT_ID) == request, "make_request is not stable across calls", failures)

	var receipt := Protocol.validate(request, TICK)
	_expect(receipt.keys() == ["status", "reason", "command"], "validate receipt shape changed", failures)
	_expect(receipt.status == "accepted" and receipt.reason == "ok", "valid loot pickup request was rejected", failures)
	_expect(receipt.command == request, "accepted command value changed", failures)

	var result := Protocol.arbitrate([request], TICK)
	_expect(result.keys() == ["commands", "receipts"], "arbitrate result shape changed", failures)
	_expect(result.commands.size() == 1 and result.commands[0] == request, "single valid request was not accepted", failures)
	_expect(result.receipts.size() == 1 and result.receipts[0].status == "accepted" and result.receipts[0].reason == "ok", "single valid request lost its receipt", failures)


func _test_tick_rejections(failures: Array[String]) -> void:
	_expect(Protocol.validate(Protocol.make_request(TICK - 1, ACTOR, 1, LOOT_ID), TICK).reason == "stale_tick", "stale tick reason changed", failures)
	_expect(Protocol.validate(Protocol.make_request(TICK + 1, ACTOR, 1, LOOT_ID), TICK).reason == "future_tick", "future tick reason changed", failures)
	var float_tick := Protocol.make_request(TICK, ACTOR, 1, LOOT_ID)
	float_tick.tick = 120.0
	_expect(Protocol.validate(float_tick, TICK).reason == "invalid_tick", "float tick was accepted", failures)
	var string_tick := Protocol.make_request(TICK, ACTOR, 1, LOOT_ID)
	string_tick.tick = "120"
	_expect(Protocol.validate(string_tick, TICK).reason == "invalid_tick", "string tick was accepted", failures)


func _test_missing_fields(failures: Array[String]) -> void:
	for field in ["protocol_version", "tick", "actor_id", "sequence", "kind", "loot_entity_id"]:
		var broken := Protocol.make_request(TICK, ACTOR, 1, LOOT_ID)
		broken.erase(field)
		_expect(Protocol.validate(broken, TICK).reason == "missing_field", "missing %s was not reported as missing_field" % field, failures)


func _test_extra_fields(failures: Array[String]) -> void:
	var with_distance := Protocol.make_request(TICK, ACTOR, 1, LOOT_ID)
	with_distance.distance_milli = 250
	_expect(Protocol.validate(with_distance, TICK).reason == "extra_field", "distance field was accepted into the protocol", failures)
	var with_source := Protocol.make_request(TICK, ACTOR, 1, LOOT_ID)
	with_source.source = "Manual"
	_expect(Protocol.validate(with_source, TICK).reason == "extra_field", "source field was accepted into the protocol", failures)


func _test_bad_types(failures: Array[String]) -> void:
	var version_float := Protocol.make_request(TICK, ACTOR, 1, LOOT_ID)
	version_float.protocol_version = 1.0
	_expect(Protocol.validate(version_float, TICK).reason == "wrong_protocol", "float protocol version was accepted", failures)
	var version_string := Protocol.make_request(TICK, ACTOR, 1, LOOT_ID)
	version_string.protocol_version = "1"
	_expect(Protocol.validate(version_string, TICK).reason == "wrong_protocol", "string protocol version was accepted", failures)
	var version_two := Protocol.make_request(TICK, ACTOR, 1, LOOT_ID)
	version_two.protocol_version = 2
	_expect(Protocol.validate(version_two, TICK).reason == "wrong_protocol", "future protocol version was accepted", failures)

	var int_actor := Protocol.make_request(TICK, ACTOR, 1, LOOT_ID)
	int_actor.actor_id = 7
	_expect(Protocol.validate(int_actor, TICK).reason == "invalid_actor", "int actor id was accepted", failures)

	var float_sequence := Protocol.make_request(TICK, ACTOR, 1, LOOT_ID)
	float_sequence.sequence = 1.0
	_expect(Protocol.validate(float_sequence, TICK).reason == "invalid_sequence", "float sequence was accepted", failures)
	var bool_sequence := Protocol.make_request(TICK, ACTOR, 1, LOOT_ID)
	bool_sequence.sequence = true
	_expect(Protocol.validate(bool_sequence, TICK).reason == "invalid_sequence", "bool sequence was accepted", failures)
	var string_sequence := Protocol.make_request(TICK, ACTOR, 1, LOOT_ID)
	string_sequence.sequence = "1"
	_expect(Protocol.validate(string_sequence, TICK).reason == "invalid_sequence", "string sequence was accepted", failures)
	_expect(Protocol.validate(Protocol.make_request(TICK, ACTOR, -1, LOOT_ID), TICK).reason == "invalid_sequence", "negative sequence was accepted", failures)

	var wrong_kind := Protocol.make_request(TICK, ACTOR, 1, LOOT_ID)
	wrong_kind.kind = "pickup"
	_expect(Protocol.validate(wrong_kind, TICK).reason == "invalid_kind", "wrong kind was accepted", failures)
	var int_kind := Protocol.make_request(TICK, ACTOR, 1, LOOT_ID)
	int_kind.kind = 1
	_expect(Protocol.validate(int_kind, TICK).reason == "invalid_kind", "int kind was accepted", failures)

	var int_loot := Protocol.make_request(TICK, ACTOR, 1, LOOT_ID)
	int_loot.loot_entity_id = 42
	_expect(Protocol.validate(int_loot, TICK).reason == "invalid_loot_entity", "int loot entity id was accepted", failures)

	_expect(Protocol.validate("loot_pickup", TICK).reason == "invalid_request", "string payload was accepted", failures)
	_expect(Protocol.validate(null, TICK).reason == "invalid_request", "null payload was accepted", failures)


func _test_empty_ids(failures: Array[String]) -> void:
	_expect(Protocol.validate(Protocol.make_request(TICK, "", 1, LOOT_ID), TICK).reason == "invalid_actor", "empty actor id was accepted", failures)
	_expect(Protocol.validate(Protocol.make_request(TICK, "   ", 1, LOOT_ID), TICK).reason == "invalid_actor", "whitespace actor id was accepted", failures)
	_expect(Protocol.validate(Protocol.make_request(TICK, ACTOR, 1, ""), TICK).reason == "invalid_loot_entity", "empty loot entity id was accepted", failures)
	_expect(Protocol.validate(Protocol.make_request(TICK, ACTOR, 1, "  "), TICK).reason == "invalid_loot_entity", "whitespace loot entity id was accepted", failures)


func _test_arbitrate_duplicates(failures: Array[String]) -> void:
	var result := Protocol.arbitrate([
		Protocol.make_request(TICK, ACTOR, 8, "drop-b"),
		Protocol.make_request(TICK, ACTOR, 3, "drop-a"),
		Protocol.make_request(TICK, ACTOR, 5, "drop-c"),
	], TICK, ACTOR)
	_expect(result.commands.size() == 1, "arbitration accepted more than one pickup for one actor", failures)
	_expect(not result.commands.is_empty() and result.commands[0].sequence == 3 and result.commands[0].loot_entity_id == "drop-a", "lowest sequence did not win the pickup slot", failures)
	_expect(result.receipts.size() == 3, "arbitration did not keep one receipt per request", failures)
	_expect(_reason_count(result.receipts, "duplicate_pickup_request") == 2, "expected two duplicate_pickup_request rejections", failures)
	_expect(_reason_count(result.receipts, "ok") == 1, "expected exactly one accepted receipt", failures)

	var twin := Protocol.make_request(TICK, ACTOR, 3, "drop-a")
	var twin_result := Protocol.arbitrate([twin, twin], TICK, ACTOR)
	_expect(twin_result.commands.size() == 1, "identical duplicate request created two commands", failures)
	_expect(_reason_count(twin_result.receipts, "duplicate_pickup_request") == 1 and _reason_count(twin_result.receipts, "ok") == 1, "identical duplicate request receipts changed", failures)

	var mixed := Protocol.arbitrate([
		Protocol.make_request(TICK, ACTOR, 1, "drop-a"),
		Protocol.make_request(TICK - 1, ACTOR, 0, "drop-stale"),
		Protocol.make_request(TICK + 1, ACTOR, 9, "drop-future"),
	], TICK, ACTOR)
	_expect(mixed.commands.size() == 1 and not mixed.commands.is_empty() and mixed.commands[0].tick == TICK, "stale or future request displaced the current-tick pickup", failures)
	_expect(_reason_count(mixed.receipts, "stale_tick") == 1 and _reason_count(mixed.receipts, "future_tick") == 1, "stale and future receipts were lost", failures)


func _test_stable_ordering(failures: Array[String]) -> void:
	var base := [
		Protocol.make_request(TICK, ACTOR, 5, "drop-b"),
		Protocol.make_request(TICK, ACTOR, 5, "drop-a"),
		Protocol.make_request(TICK, ACTOR, 2, "drop-c"),
	]
	var reversed := base.duplicate()
	reversed.reverse()
	var first := Protocol.arbitrate(base, TICK, ACTOR)
	var second := Protocol.arbitrate(reversed, TICK, ACTOR)
	_expect(first == second, "arbitration changed with input array order", failures)
	_expect(not first.commands.is_empty() and first.commands[0].sequence == 2 and first.commands[0].loot_entity_id == "drop-c", "lowest sequence did not win the pickup slot", failures)
	_expect(first.receipts.size() == 3, "stable ordering lost receipts", failures)
	_expect(first.receipts[0].command.sequence == 2 and first.receipts[1].command.loot_entity_id == "drop-a" and first.receipts[2].command.loot_entity_id == "drop-b", "receipt order did not follow sequence then JSON order", failures)


func _test_actor_scope(failures: Array[String]) -> void:
	_expect(Protocol.validate(Protocol.make_request(TICK, "ranger-1", 1, LOOT_ID), TICK).status == "accepted", "validate must stay actor-agnostic beyond non-empty ids", failures)

	var foreign := Protocol.make_request(TICK, "ranger-1", 1, LOOT_ID)
	var scoped := Protocol.arbitrate([foreign], TICK)
	_expect(scoped.commands.is_empty() and scoped.receipts.size() == 1 and scoped.receipts[0].reason == "actor_mismatch", "arbitration accepted a request outside its actor scope", failures)

	var own := Protocol.make_request(TICK, "ranger-1", 1, LOOT_ID)
	_expect(Protocol.arbitrate([own], TICK, "ranger-1").commands.size() == 1, "explicit actor scope rejected its own request", failures)
	_expect(Protocol.arbitrate([Protocol.make_request(TICK, ACTOR, 1, LOOT_ID)], TICK).commands.size() == 1, "default actor scope is not ranger", failures)


func _test_detached_returns(failures: Array[String]) -> void:
	var request := Protocol.make_request(TICK, ACTOR, 4, LOOT_ID)
	var first := Protocol.validate(request, TICK)
	var second := Protocol.validate(request, TICK)
	first.command.loot_entity_id = "mutated"
	_expect(second.command.loot_entity_id == LOOT_ID, "validate returned shared command storage across calls", failures)
	_expect(request.loot_entity_id == LOOT_ID, "validate receipt mutation leaked into the request", failures)
	request.sequence = 99
	_expect(first.command.sequence == 4 and second.command.sequence == 4, "validate receipts aliased the caller request", failures)

	var extra := Protocol.make_request(TICK, ACTOR, 1, LOOT_ID)
	extra.distance_milli = 250
	var extra_receipt := Protocol.validate(extra, TICK)
	_expect(int(extra_receipt.command.get("distance_milli", 0)) == 250, "rejected receipt dropped the offending command copy", failures)
	extra.distance_milli = 999
	_expect(int(extra_receipt.command.get("distance_milli", 0)) == 250, "rejected receipt aliased the caller request", failures)

	var pickup := Protocol.make_request(TICK, ACTOR, 4, LOOT_ID)
	var arbitrated := Protocol.arbitrate([pickup], TICK, ACTOR)
	arbitrated.commands[0].loot_entity_id = "detached-check"
	_expect(arbitrated.receipts[0].command.loot_entity_id == LOOT_ID, "arbitrate commands aliased receipt storage", failures)
	_expect(pickup.loot_entity_id == LOOT_ID, "arbitrate command mutation leaked into the request", failures)

	var batch := [
		Protocol.make_request(TICK, ACTOR, 6, "drop-b"),
		Protocol.make_request(TICK, ACTOR, 2, "drop-a"),
	]
	var run_one := Protocol.arbitrate(batch, TICK, ACTOR)
	var run_two := Protocol.arbitrate(batch, TICK, ACTOR)
	run_one.receipts[0].command.loot_entity_id = "mutated"
	var run_three := Protocol.arbitrate(batch, TICK, ACTOR)
	_expect(run_two == run_three, "repeat arbitration over unchanged input diverged", failures)
	_expect(run_two.receipts[0].command.loot_entity_id == "drop-a", "arbitrate receipts aliased storage across calls", failures)


func _reason_count(receipts: Array, reason: String) -> int:
	var count := 0
	for receipt in receipts:
		if receipt.reason == reason:
			count += 1
	return count


func _expect(condition: bool, message: String, failures: Array[String]) -> void: Assert.expect(condition, message, failures)
