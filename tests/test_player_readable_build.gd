extends SceneTree

const FormatterScript = preload("res://src/presentation/player_readable_build.gd")


func _initialize() -> void:
	_finish(run())


func run() -> Array[String]:
	var failures: Array[String] = []
	var formatter = FormatterScript.new()
	for tier in range(1, 5):
		_expect(formatter.tier_label(tier) == ["Tier I", "Tier II", "Tier III", "Tier IV"][tier - 1],
			"tier label lost its English order or Roman numeral", failures)
	for method_name in ["parameter_name", "format_parameter", "format_modifier", "format_affix", "format_item", "format_comparison", "format_candidate_decision_summary"]:
		_expect(formatter.has_method(method_name), "missing reusable public method %s" % method_name, failures)
	_expect(formatter.parameter_name("p") == "Piercing Arrow Continuation Chance", "parameter_name did not map p", failures)
	_expect("Lower Is Better" in formatter.parameter_name("turn"), "turn name lost lower-is-better guidance", failures)
	_expect(formatter.format_parameter("turn", 0.18) == "Turn Time (Lower Is Better): 0.18 s",
		"turn-time formatting repeated or lost its lower-is-better guidance", failures)
	_expect(formatter.format_parameter("critical_chance", 0.125).contains("12.5%"), "critical chance formatting is wrong", failures)
	_expect(formatter.format_modifier({"parameter": "damage", "operation": "multiply", "value": 1.12}).contains("Increase 12%"), "multiply modifier formatting is wrong", failures)
	_expect(formatter.format_affix({"family_id": "piercing_continuation", "tier": 2}).contains("Piercing Arrow Continuation Chance Tier II")
		and formatter.format_affix({"family_id": "piercing_continuation", "tier": 2}).contains("+7 percentage points"), "affix did not read its real tier value from registry", failures)
	var comparison := formatter.format_comparison({"turn": 0.4, "damage": 100.0}, {"turn": 0.36, "damage": 112.0})
	_expect("Turn Time (Lower Is Better)" in comparison and "0.4 s" in comparison and "0.36 s" in comparison and "100 → 112" in comparison, "comparison copy is incomplete", failures)
	var default_decision := formatter.format_candidate_decision_summary(
		{"p": 0.61},
		{
			"ok": true,
			"final_parameters": {"p": 0.61},
			"interfaces_gained": ["breedable_event", "quick_draw"],
			"interfaces_lost": ["branch_target_history"],
		}
	)
	_expect(default_decision.contains("Interfaces Gained: Breedable Child Arrows, Unknown Interface (quick_draw)")
		and default_decision.contains("Interfaces Lost: Branch Target History"),
		"candidate decision summary did not translate default known interfaces or retain unknown ids", failures)
	var decision := formatter.format_candidate_decision_summary(
		{"p": 0.61, "v": 682.0, "damage": 160.0},
		{
			"ok": true,
			"final_parameters": {"p": 0.54, "v": 750.2, "damage": 160.0},
			"interfaces_gained": ["quick_draw"],
			"interfaces_lost": ["breedable_event", "branch_target_history"],
		},
		{"breedable_event": "Custom Breeding Interface"}
	)
	_expect(decision.contains("Continuation Chance -7 percentage points") and decision.contains("Projectile Speed +68.2 units/s")
		and decision.contains("Interfaces Gained: Unknown Interface (quick_draw)")
		and decision.contains("Interfaces Lost: Custom Breeding Interface, Branch Target History"),
		"candidate decision summary lost concrete parameter deltas, defaults, or explicit overrides", failures)
	_expect(not decision.contains("Carrier Damage"), "candidate decision summary included an unchanged parameter", failures)
	var item := {
		"instance_id": "diagnostic-only", "base_item_id": "ashwood_longbow", "slot": "main_hand",
		"affixes": [{"family_id": "piercing_continuation", "tier": 2}],
		"rune_id": "breeding_split", "law_id": "pack_hunt_mark",
	}
	var item_text := formatter.format_item(item)
	_expect("Slot: Main Hand" in item_text and "Base Stats" in item_text and "Breeding Split" in item_text and "Pack Hunt Mark" in item_text, "format_item lost player-facing equipment details", failures)
	_expect("Added to equipment storage" not in item_text, "neutral item formatter leaked settlement-only copy", failures)
	_expect("diagnostic-only" not in item_text and "ashwood_longbow" not in item_text and "piercing_continuation" not in item_text, "format_item leaked raw ids", failures)
	_expect(formatter.diagnostic_ids(item).contains("diagnostic-only") and formatter.diagnostic_ids(item).contains("piercing_continuation"), "diagnostic ids are not separately available", failures)
	var skill_registry = load("res://src/content/early_skill_registry.gd").new()
	_expect(skill_registry.load_all().is_empty(), "skill copy: registry did not load", failures)
	var skill_text := formatter.format_skill(skill_registry.get_skill("piercing_arrow"))
	_expect(skill_text.contains("Holding the input chains one shot at each valid opening"), "skill copy: held-fire behavior is not disclosed", failures)
	return failures


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("PASS  test_player_readable_build.gd")
		quit(0)
		return
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)
