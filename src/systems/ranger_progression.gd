class_name RangerProgression
extends ClassProgression

## The Ranger's progression half of the player-class seam
## (docs/rebuild/ROOM_SESSION_DESIGN.md, "ClassKit"): the skill vocabulary, the
## stacking talent capabilities, the stance key, the p cap with its overflow
## damage conversion, the interface graph and the PiercingArrowModel growth
## model, moved verbatim out of BuildResolver, TalentBuild and
## ApplicationState. Implementations are pure and deterministic: they read only
## their arguments, so resolved-build fingerprints stay stable.

const ArrowModel = preload("res://src/systems/piercing_arrow_model.gd")


func class_id() -> String:
	return "ranger"


func default_skill_id() -> String:
	return "piercing_arrow"


func supported_skill_ids() -> Array[String]:
	return ["piercing_arrow"]


func stacking_capability_ids() -> Array[String]:
	return [
		"hunter_mark_duration_multiplier",
		"dash_duration_multiplier",
		"dodge_cooldown_reduction",
		"p_overflow_damage_efficiency_bonus",
	]


func stance_available(allocated_talent_ids: Array) -> bool:
	return "ranger_near_far_hunting" in allocated_talent_ids


func apply_parameter_rules(parameters: Dictionary, talent_capabilities: Dictionary, record_source: Callable) -> void:
	var raw_p := float(parameters.p)
	var overflow_p := maxf(0.0, raw_p - 1.0)
	parameters.p = clampf(raw_p, 0.0, 1.0)
	if raw_p != float(parameters.p):
		record_source.callv(["p", "rule", "p_cap", "clamp", 1.0, raw_p, float(parameters.p)])
	if overflow_p > 0.0:
		var damage_before := float(parameters.damage)
		var overflow_efficiency := RangerSkillRules.P_OVERFLOW_DAMAGE_BASE_EFFICIENCY + float(talent_capabilities.get("p_overflow_damage_efficiency_bonus", 0.0))
		var overflow_bonus := overflow_p * overflow_efficiency
		parameters.damage = damage_before * (1.0 + overflow_bonus)
		record_source.callv(["damage", "rule", "p_overflow_damage", "multiply_bonus", overflow_bonus, damage_before, float(parameters.damage)])


func resolve_interfaces(skill_id: String, rune_ids: Array[String], law_ids: Array[String], runes: Dictionary, laws: Dictionary) -> Dictionary:
	var connected: Array[String] = []
	var missing: Array[String] = []
	if skill_id == "piercing_arrow":
		connected.append("piercing_continuation")
	for rune_id in rune_ids:
		if runes.has(rune_id):
			connected.append(String((runes[rune_id] as Dictionary).provides_interface))
	if "breeding_split" not in rune_ids:
		missing.append("breedable_event")
	for law_id in law_ids:
		if not laws.has(law_id):
			continue
		var law: Dictionary = laws[law_id]
		var requirements_met := true
		for requirement in (law.requires_interfaces as Array):
			if String(requirement) not in connected:
				requirements_met = false
				if String(requirement) not in missing:
					missing.append(String(requirement))
		if requirements_met:
			connected.append(String(law.provides_interface))
	if "pack_hunt_mark" not in law_ids or "branch_target_history" not in connected:
		missing.append("branch_target_history")
	connected = _sorted_unique(connected)
	missing = _sorted_unique(missing)
	return {"connected": connected, "missing": missing}


func growth_model(parameters: Dictionary, connected_interfaces: Array) -> Dictionary:
	var has_split: bool = "breedable_event" in connected_interfaces
	var has_pack_mark: bool = "branch_target_history" in connected_interfaces
	return ArrowModel.evaluate(
		float(parameters.p), float(parameters.T), float(parameters.d),
		float(parameters.v), float(parameters.turn), has_split, has_pack_mark
	)


static func _sorted_unique(values: Array[String]) -> Array[String]:
	var seen: Dictionary = {}
	var result: Array[String] = []
	for value in values:
		if not seen.has(value):
			seen[value] = true
			result.append(value)
	result.sort()
	return result
