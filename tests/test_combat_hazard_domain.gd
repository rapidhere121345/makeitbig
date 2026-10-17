extends SceneTree

const DomainScript := preload("res://src/runtime/combat/combat_hazard_domain.gd")


class FakeRoomPort:
	extends "res://src/game/encounter_room_port.gd"

	var queue_calls: Array[Dictionary] = []
	var reject_quantize := false

	func quantize_position(value: Vector2) -> Vector2:
		return Vector2(INF, INF) if reject_quantize else Vector2(roundf(value.x), roundf(value.y))

	func queue_player_hazard_hit(tick: int, amount: float, source_id: String, source_position: Vector2) -> Dictionary:
		queue_calls.append({
			"tick": tick,
			"amount": amount,
			"source_id": source_id,
			"source_position": source_position,
		})
		return {"ok": true, "error": ""}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	_test_typed_binding(failures)
	_test_cycle_suppression_and_contact_fact(failures)
	_test_moving_fireline_quantization(failures)
	if failures.is_empty():
		print("PASS test_combat_hazard_domain.gd")
		quit(0)
		return
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _test_typed_binding(failures: Array[String]) -> void:
	var domain = DomainScript.new()
	var rejected: Dictionary = domain.configure(RefCounted.new(), Rect2(Vector2.ZERO, Vector2(400.0, 300.0)), [])
	_expect(not bool(rejected.get("ok", false)) and String(rejected.get("error", "")) == "hazard_room_port_unavailable", "hazard domain accepted an untyped room dependency", failures)


func _test_cycle_suppression_and_contact_fact(failures: Array[String]) -> void:
	var port := FakeRoomPort.new()
	var domain = DomainScript.new()
	var authored := [{"id": "exposed_ground_zone", "origin": Vector2(150.0, 200.0), "phase": "warning", "cycle": 0, "cycle_tick": 0, "last_hit_cycle": -1, "direction": Vector2.ZERO, "length": 0.0, "width": 0.0, "radius": 82.0}]
	var configured: Dictionary = domain.configure(port, Rect2(Vector2(40.0, 190.0), Vector2(400.0, 400.0)), authored)
	_expect(bool(configured.get("ok", false)), "ground hazard domain did not configure", failures)
	var refreshed: Dictionary = domain.refresh(30)
	_expect(bool(refreshed.get("ok", false)) and String(domain.snapshots()[0].get("phase", "")) == "active", "ground hazard did not enter active phase at tick 30", failures)
	var first: Dictionary = domain.resolve(30, Vector2(150.0, 200.0))
	var second: Dictionary = domain.resolve(30, Vector2(150.0, 200.0))
	_expect(bool(first.get("ok", false)) and (first.get("contacts", []) as Array).size() == 1, "ground hazard did not emit one typed contact fact", failures)
	_expect(bool(second.get("ok", false)) and (second.get("contacts", []) as Array).is_empty(), "ground hazard emitted a duplicate contact in one cycle", failures)
	_expect(port.queue_calls.size() == 1 and port.queue_calls[0].source_id == "hazard/exposed_ground_zone" and is_equal_approx(float(port.queue_calls[0].amount), 7.0), "ground hazard contact fact lost source or amount", failures)
	var next_cycle: Dictionary = domain.refresh(120)
	var third: Dictionary = domain.resolve(120, Vector2(150.0, 200.0))
	_expect(bool(next_cycle.get("ok", false)) and bool(third.get("ok", false)) and (third.get("contacts", []) as Array).size() == 1 and port.queue_calls.size() == 2, "ground hazard did not reopen on the next cycle", failures)


func _test_moving_fireline_quantization(failures: Array[String]) -> void:
	var port := FakeRoomPort.new()
	var domain = DomainScript.new()
	var authored := [{"id": "moving_fireline", "origin": Vector2(40.0, 190.0), "phase": "warning", "cycle": 0, "cycle_tick": 0, "last_hit_cycle": -1, "direction": Vector2.DOWN, "length": 400.0, "width": 34.0, "radius": 0.0}]
	var configured: Dictionary = domain.configure(port, Rect2(Vector2(40.0, 190.0), Vector2(400.0, 400.0)), authored)
	_expect(bool(configured.get("ok", false)), "moving fireline domain did not configure", failures)
	var refreshed: Dictionary = domain.refresh(30)
	var state: Dictionary = domain.snapshots()[0]
	_expect(bool(refreshed.get("ok", false)) and (state.origin as Vector2).x == 175.0, "moving fireline did not use typed quantized position", failures)
	port.reject_quantize = true
	var rejected: Dictionary = domain.refresh(31)
	_expect(not bool(rejected.get("ok", false)) and String(rejected.get("error", "")) == "hazard_quantization_rejected", "moving fireline accepted invalid quantization", failures)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
