class_name EarlyEnemyProfileRegistry
extends RefCounted

## Read-only content loader for the first enemy definition slice.
##
## JSON owns authored values. The registry validates and resolves them into
## EnemyCombatProfile objects; it never stores room health or action progress.

const ProfileScript := preload("res://src/game/enemy_combat_profile.gd")
const CONTENT_PATH := "res://content/early_enemy_profiles.json"
const SCHEMA_VERSION: int = 1
const TOP_LEVEL_FIELDS: Array[String] = ["schema_version", "profiles"]
const EXPECTED_PROFILE_IDS: Array[String] = ["charging_raider", "fan_ranged", "melee_pursuer"]

var _profiles: Dictionary = {}


func load_all(path: String = CONTENT_PATH) -> Array[String]:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ["enemy_profiles: cannot open '%s'" % path]
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	if parse_error != OK:
		return ["enemy_profiles: invalid JSON at line %d: %s" % [parser.get_error_line(), parser.get_error_message()]]
	if not parser.data is Dictionary:
		return ["enemy_profiles: root must be an object"]
	return load_data(parser.data)


func load_data(candidate: Dictionary) -> Array[String]:
	var failures := validate_data(candidate)
	if not failures.is_empty():
		_profiles.clear()
		return failures
	var staged: Dictionary = {}
	for raw_profile: Dictionary in candidate.profiles:
		var parsed: Dictionary = ProfileScript.from_data(raw_profile)
		if not bool(parsed.get("ok", false)):
			failures.append("profile %s: %s" % [String(raw_profile.get("profile_id", "")), String(parsed.get("error", "invalid_profile"))])
			continue
		staged[String(raw_profile.profile_id)] = parsed.value
	if failures.is_empty():
		_profiles = staged
	return failures


func validate_data(candidate: Variant) -> Array[String]:
	var failures: Array[String] = []
	if not candidate is Dictionary:
		return ["enemy_profiles: root must be an object"]
	var data: Dictionary = candidate
	for key: Variant in data.keys():
		if not key is String or String(key) not in TOP_LEVEL_FIELDS:
			failures.append("enemy_profiles: unknown field '%s'" % String(key))
	if data.get("schema_version", null) != SCHEMA_VERSION:
		failures.append("enemy_profiles: schema_version must be %d" % SCHEMA_VERSION)
	var profiles_value: Variant = data.get("profiles", null)
	if not profiles_value is Array:
		failures.append("enemy_profiles: profiles must be an array")
		return failures
	var profiles: Array = profiles_value
	if profiles.size() != EXPECTED_PROFILE_IDS.size():
		failures.append("enemy_profiles: profiles has %d entries, expected %d" % [profiles.size(), EXPECTED_PROFILE_IDS.size()])
	var ids: Array[String] = []
	for raw_profile: Variant in profiles:
		if not raw_profile is Dictionary:
			failures.append("enemy_profiles: profile entries must be objects")
			continue
		var profile: Dictionary = raw_profile
		var parsed: Dictionary = ProfileScript.from_data(profile)
		if not bool(parsed.get("ok", false)):
			failures.append("profile %s: %s" % [String(profile.get("profile_id", "")), String(parsed.get("error", "invalid_profile"))])
		var id := String(profile.get("profile_id", ""))
		if id in ids:
			failures.append("enemy_profiles: duplicate profile id '%s'" % id)
		ids.append(id)
	ids.sort()
	var expected := EXPECTED_PROFILE_IDS.duplicate()
	expected.sort()
	if ids != expected:
		failures.append("enemy_profiles: profile IDs must be exactly %s" % str(expected))
	return failures


func validate_campaign_roles(role_by_id: Dictionary) -> Array[String]:
	var failures: Array[String] = []
	for profile_id: String in EXPECTED_PROFILE_IDS:
		if not role_by_id.has(profile_id):
			failures.append("enemy_profiles: campaign is missing normal enemy '%s'" % profile_id)
			continue
		var resolved: Dictionary = resolve(profile_id)
		if not bool(resolved.get("ok", false)):
			continue
		var profile: RefCounted = resolved.value
		if String(role_by_id[profile_id]) != String(profile.get("role")):
			failures.append("enemy_profiles: role mismatch for '%s'" % profile_id)
	return failures


func has_profile(profile_id: String) -> bool:
	return _profiles.has(profile_id)


func resolve(profile_id: String) -> Dictionary:
	if not _profiles.has(profile_id):
		return {"ok": false, "error": "unknown_enemy_profile_id", "value": {}}
	var source: RefCounted = _profiles[profile_id]
	var parsed: Dictionary = ProfileScript.from_data(source.snapshot())
	if not bool(parsed.get("ok", false)):
		return {"ok": false, "error": "stored_enemy_profile_invalid", "value": {}}
	return {"ok": true, "error": "", "value": parsed.value}


func snapshot() -> Dictionary:
	var profiles: Array[Dictionary] = []
	var ids: Array[String] = []
	for profile_id: Variant in _profiles.keys():
		ids.append(String(profile_id))
	ids.sort()
	for profile_id: String in ids:
		profiles.append((_profiles[profile_id] as RefCounted).snapshot())
	return {"schema_version": SCHEMA_VERSION, "profiles": profiles}
