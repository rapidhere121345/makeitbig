extends SceneTree

const Ledger := preload("res://src/game/status_effect_ledger.gd")
const Enemy := preload("res://src/runtime/world/combat_enemy_state.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ledger := Ledger.new()
	_expect(bool(ledger.reset().get("ok", false)), "ledger reset failed")
	var applied := ledger.apply(10, "exposed", "hazard/1", 3, 1.25, "replace", 1, {"parameter": "damage_taken", "operation": "multiply_bonus", "value": 0.25})
	_expect(bool(applied.get("ok", false)) and bool(applied.get("changed", false)), "valid status was not applied")
	var at_start: Dictionary = ledger.snapshot(10)
	var start_effects: Array = at_start.get("effects", [])
	_expect(start_effects.size() == 1 and int((start_effects[0] as Dictionary).get("expires_tick", -1)) == 13, "status active interval changed")
	var detached: Dictionary = at_start.duplicate(true)
	var detached_effects: Array = detached.get("effects", [])
	if not detached_effects.is_empty():
		(detached_effects[0] as Dictionary)["source_id"] = "mutated"
	_expect(start_effects.size() == 1 and String(((ledger.snapshot(10).get("effects", []) as Array)[0] as Dictionary).get("source_id", "")) == "hazard/1", "status snapshot leaked mutable state")
	_expect(ledger.has_active(12, "exposed") and not ledger.has_active(13, "exposed"), "status expiry boundary changed")
	var expired := ledger.advance(13)
	_expect(bool(expired.get("ok", false)) and (expired.get("expired", []) as Array).size() == 1 and (expired.get("snapshot", {}).get("effects", []) as Array).is_empty(), "status advance did not expire exactly once")
	_expect(String(ledger.advance(12).get("error", "")) == "stale_status_tick", "stale status tick was accepted")

	var refresh := ledger.apply(20, "mark", "skill/hunter_mark", 5, 1.25, "refresh")
	_expect(bool(refresh.get("ok", false)), "refresh status was rejected")
	var refreshed := ledger.apply(22, "mark", "skill/hunter_mark", 8, 1.5, "refresh")
	var refreshed_snapshot: Dictionary = refreshed.get("snapshot", {})
	_expect(bool(refreshed.get("ok", false)) and (refreshed_snapshot.get("effects", []) as Array).size() == 1 and int(((refreshed_snapshot.get("effects", []) as Array)[0] as Dictionary).get("expires_tick", -1)) == 30, "refresh policy did not replace expiry and magnitude")
	var ignored := ledger.apply(23, "mark", "other/source", 4, 2.0, "ignore")
	_expect(bool(ignored.get("ok", false)) and not bool(ignored.get("changed", true)) and String(ignored.get("reason", "")) == "already_active", "ignore policy changed an active status")

	var stacked := ledger.apply(23, "bleed", "enemy/1", 4, 1.0, "stack", 2)
	var stacked_again := ledger.apply(23, "bleed", "enemy/2", 4, 2.0, "stack", 2)
	var capped := ledger.apply(23, "bleed", "enemy/3", 4, 3.0, "stack", 2)
	_expect(bool(stacked.ok) and bool(stacked_again.ok) and bool(capped.ok), "stack policy rejected valid applications")
	var bleed_effects: Array = []
	for effect: Dictionary in (ledger.snapshot(23).get("effects", []) as Array):
		if String(effect.get("effect_id", "")) == "bleed":
			bleed_effects.append(effect)
	var has_replaced_magnitude := false
	for effect: Dictionary in bleed_effects:
		has_replaced_magnitude = has_replaced_magnitude or is_equal_approx(float(effect.get("magnitude", 0.0)), 3.0)
	_expect(bleed_effects.size() == 2 and has_replaced_magnitude, "stack cap did not replace the oldest instance")

	_expect(String(ledger.apply(24, "bad id", "source", 1, 1.0).get("error", "")) == "invalid_effect_id", "untrimmed effect id was accepted")
	_expect(String(ledger.apply(24, "bad", "source", 0, 1.0).get("error", "")) == "invalid_duration_ticks", "zero duration was accepted")
	_expect(String(ledger.apply(24, "bad", "source", 1, 1.0, "replace", 1, {"operation": "add"}).get("error", "")) == "missing_modifier_field:parameter", "partial modifier was accepted")

	var enemy := Enemy.new(Vector2(20.0, 20.0), 10.0, false, 1, "melee_pursuer")
	var enemy_applied := enemy.apply_status_effect(0, "slow", "test", 2, 0.5, "replace", 1, {"parameter": "move_speed", "operation": "multiply", "value": 0.5})
	_expect(bool(enemy_applied.get("ok", false)) and (enemy.status_effects_snapshot(0).get("effects", []) as Array).size() == 1, "enemy did not expose status ledger snapshot")
	_expect(bool(enemy.advance_status_effects(2).get("ok", false)) and (enemy.status_effects_snapshot(2).get("effects", []) as Array).is_empty(), "enemy status ledger did not expire on room tick")
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	for failure: String in _failures:
		printerr("- %s" % failure)
	print("PASS test_status_effect_ledger.gd" if _failures.is_empty() else "FAIL test_status_effect_ledger.gd")
	quit(0 if _failures.is_empty() else 1)
