extends SceneTree

const ProfileScript := preload("res://src/game/enemy_combat_profile.gd")
const RegistryScript := preload("res://src/content/early_enemy_profile_registry.gd")
const Assert := preload("res://tests/helpers/assert.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var registry := RegistryScript.new()
	var load_errors: Array[String] = registry.load_all()
	_expect(load_errors.is_empty(), "profile registry: shipped content failed validation: %s" % ";".join(load_errors), failures)
	if load_errors.is_empty():
		var snapshot: Dictionary = registry.snapshot()
		_expect((snapshot.get("profiles", []) as Array).size() == 3, "profile registry: expected three shipped definitions", failures)
		for profile_id: String in ["melee_pursuer", "charging_raider", "fan_ranged"]:
			var resolved: Dictionary = registry.resolve(profile_id)
			_expect(bool(resolved.get("ok", false)), "profile registry: failed to resolve %s" % profile_id, failures)
			if not bool(resolved.get("ok", false)):
				continue
			var profile: RefCounted = resolved.value
			_expect(String(profile.profile_id) == profile_id, "profile registry: resolved identity changed for %s" % profile_id, failures)
			var action_id := "contact" if profile_id == "melee_pursuer" else ("charge" if profile_id == "charging_raider" else "fan")
			var action: Dictionary = profile.action(action_id)
			_expect(not action.is_empty() and int(action.get("windup_ticks", 0)) > 0, "profile registry: action data missing for %s" % profile_id, failures)
			var detached: Dictionary = profile.snapshot()
			(detached.actions as Dictionary)[action_id]["damage"] = -1.0
			_expect(float(profile.action(action_id).get("damage", 0.0)) >= 0.0, "profile registry: snapshot leaked mutable action data for %s" % profile_id, failures)

	var valid := {
		"schema_version": 1, "profile_id": "fixture", "role": "melee_chase",
		"normal_health": 10.0, "elite_health": 20.0, "move_speed": 30.0, "breath_ticks": 1,
		"actions": {"contact": {"windup_ticks": 1, "active_ticks": 1, "recovery_ticks": 1, "damage": 2.0}},
	}
	var parsed: Dictionary = ProfileScript.from_data(valid)
	_expect(bool(parsed.get("ok", false)), "profile schema: valid definition was rejected", failures)
	var bad := valid.duplicate(true)
	bad["role"] = "unknown"
	_expect(not bool(ProfileScript.from_data(bad).get("ok", false)), "profile schema: unknown role was accepted", failures)
	bad = valid.duplicate(true)
	bad.actions.contact.windup_ticks = 1.5
	_expect(not bool(ProfileScript.from_data(bad).get("ok", false)), "profile schema: fractional action tick was accepted", failures)
	bad = valid.duplicate(true)
	(bad["actions"] as Dictionary)["charge"] = ((valid["actions"] as Dictionary)["contact"] as Dictionary).duplicate(true)
	_expect(not bool(ProfileScript.from_data(bad).get("ok", false)), "profile schema: action unrelated to role was accepted", failures)
	bad = valid.duplicate(true)
	(bad["actions"] as Dictionary)["contact"]["future"] = true
	_expect(not bool(ProfileScript.from_data(bad).get("ok", false)), "profile schema: unknown action field was accepted", failures)
	bad = valid.duplicate(true)
	(bad["actions"] as Dictionary)["contact"]["active_ticks"] = 0
	_expect(not bool(ProfileScript.from_data(bad).get("ok", false)), "profile schema: zero active ticks was accepted", failures)

	if failures.is_empty():
		print("PASS test_enemy_combat_profile.gd")
		quit(0)
		return
	for failure: String in failures:
		printerr("- %s" % failure)
	quit(1)


func _expect(condition: bool, message: String, failures: Array[String]) -> void: Assert.expect(condition, message, failures)
