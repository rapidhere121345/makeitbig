extends SceneTree

const RegistryScript = preload("res://src/content/early_skill_registry.gd")
const RulesScript = preload("res://src/systems/ranger_skill_rules.gd")
const Assert := preload("res://tests/helpers/assert.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var registry = RegistryScript.new()
	var errors: Array[String] = registry.load_all()
	_expect(errors.is_empty(), "early skill registry failed to load: %s" % str(errors), failures)
	if not errors.is_empty():
		_finish(failures)
		return
	_expect(registry.ticks_per_second == 30 and registry.skills.size() == 4, "skill registry must expose four skills at 30Hz", failures)
	_expect(RegistryScript.REQUIRED_FACTS == RulesScript.CONTENT_FACTS,
		"skill descriptions are no longer validated against the combat rules source", failures)
	_expect(registry.skills.keys() == RegistryScript.SKILL_IDS, "skill order or ids changed", failures)
	var arrow: Dictionary = registry.get_skill("piercing_arrow")
	_expect(int(arrow.cooldown_ticks) == 13 and int(arrow.duration_ticks) == 10 and "valid Hunter's Mark" in String(arrow.target_rule) and "nearest" in String(arrow.target_rule), "piercing arrow target/cooldown/action facts changed", failures)
	_expect("real arrow" in String(arrow.full_effect) and "bow hand" in String(arrow.full_effect) and "projectile speed v" in String(arrow.full_effect)
		and "first intersection" in String(arrow.full_effect) and "carrier damage x this shot's arrow event count" in String(arrow.full_effect)
		and "1.25" in String(arrow.full_effect) and "current targeting distance" in String(arrow.range_rule),
		"piercing arrow projectile/damage/range facts changed", failures)
	var arrow_limitations := "\n".join(arrow.limitations)
	_expect("Direction" in arrow_limitations and "projectile speed, and damage" in arrow_limitations
		and "never home or turn" in arrow_limitations and "hit area" in arrow_limitations and "Moving out of that path or range" in arrow_limitations,
		"piercing arrow frozen-path miss rule is no longer explained to the player", failures)
	var mark: Dictionary = registry.get_skill("hunter_mark")
	_expect(int(mark.cooldown_ticks) == 240 and int(mark.duration_ticks) == 180 and "1.5x" in String(mark.range_rule), "hunter mark facts changed", failures)
	var dash: Dictionary = registry.get_skill("dash")
	_expect(int(dash.cooldown_ticks) == 90 and int(dash.duration_ticks) == 6 and float(dash.displacement_units) == 180.0 and not bool(dash.invulnerable), "dash facts changed", failures)
	var dodge: Dictionary = registry.get_skill("basic_dodge")
	_expect(int(dodge.cooldown_ticks) == 35 and int(dodge.duration_ticks) == 5 and float(dodge.speed_units_per_second) == 650.0 and bool(dodge.invulnerable), "dodge facts changed", failures)
	var file := FileAccess.open("res://content/early_skills.json", FileAccess.READ)
	var content: Dictionary = JSON.parse_string(file.get_as_text())
	var missing: Dictionary = content.duplicate(true)
	missing.skills[0].erase("limitations")
	_expect(_contains(registry.validate_content(missing), "missing field 'limitations'"), "strict fields did not reject a missing player field", failures)
	var extra: Dictionary = content.duplicate(true)
	extra.skills[0]["formula"] = "hidden"
	_expect(_contains(registry.validate_content(extra), "unknown field 'formula'"), "strict fields did not reject an unknown field", failures)
	var drift: Dictionary = content.duplicate(true)
	drift.skills[2].cooldown_ticks = 91
	_expect(_contains(registry.validate_content(drift), "authoritative fact 'cooldown_ticks' changed"), "authoritative skill facts can drift silently", failures)
	_finish(failures)


func _contains(errors: Array[String], needle: String) -> bool:
	for error in errors:
		if error.contains(needle):
			return true
	return false


func _expect(condition: bool, message: String, failures: Array[String]) -> void: Assert.expect(condition, message, failures)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("PASS  test_early_skills.gd")
		quit(0)
		return
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)
