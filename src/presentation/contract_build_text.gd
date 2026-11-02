extends RefCounted

## Pure text builders for the contract screen's build details: parameter line,
## growth conclusion, component summary and core skill details. Everything is
## static and reads only its arguments.


static func parameter_line(resolved: Dictionary, player_readable: PlayerReadableBuild) -> String:
	var parameters_value: Variant = resolved.get("final_parameters", {})
	var parameters: Dictionary = parameters_value if parameters_value is Dictionary else {}
	return player_readable.format_parameters(parameters)


static func growth_conclusion(resolved: Dictionary, training: Dictionary) -> String:
	var fingerprint := str(resolved.get("build_fingerprint", "")).strip_edges()
	var report := matched_training_report(training, fingerprint)
	if report.is_empty():
		return "Unverified"
	var state := str(report.get("state", "")).strip_edges()
	return String({"convergent": "Convergent", "critical": "Critical", "exponential": "Exponential"}.get(state.to_lower(), "Unverified"))


static func core_skill_summary(build: Dictionary, resolved: Dictionary, skill_registry: EarlySkillRegistry, player_readable: PlayerReadableBuild) -> String:
	var skill_ids := component_values(build, resolved, "skills", "skill_id")
	if not "basic_dodge" in skill_ids:
		skill_ids.append("basic_dodge")
	var details: Array[String] = []
	for raw_id in skill_ids:
		var skill := skill_registry.get_skill(String(raw_id))
		if not skill.is_empty():
			details.append(player_readable.format_skill(skill))
	return "Core skill details:\n%s" % "\n\n".join(details) if not details.is_empty() else "Core skill details unavailable"


static func matched_training_report(training: Dictionary, fingerprint: String) -> Dictionary:
	if fingerprint.is_empty():
		return {}
	var reports_by_fingerprint_value: Variant = training.get("reports_by_fingerprint", {})
	if not reports_by_fingerprint_value is Dictionary:
		return {}
	var report_value: Variant = (reports_by_fingerprint_value as Dictionary).get(fingerprint, {})
	if not report_value is Dictionary:
		return {}
	var report: Dictionary = report_value
	if String(report.get("build_fingerprint", "")).strip_edges() != fingerprint:
		return {}
	return report.duplicate(true)


static func components_summary(build: Dictionary, resolved: Dictionary, skill_registry: EarlySkillRegistry, player_readable: PlayerReadableBuild) -> String:
	var skills := component_values(build, resolved, "skills", "skill_id")
	var runes := component_values(build, resolved, "runes", "rune_ids")
	var laws := component_values(build, resolved, "laws", "law_ids")
	if laws.is_empty():
		laws = component_values(build, resolved, "rules", "law_ids")
	if laws.is_empty():
		laws = component_values(build, resolved, "law", "law_ids")
	var skill_names: Array[String] = []
	for raw_skill in skills:
		var skill := skill_registry.get_skill(String(raw_skill))
		if not skill.is_empty():
			skill_names.append(String(skill.get("name", "Skill")))
	var rune_lines: Array[String] = []
	for raw_rune in runes:
		rune_lines.append(player_readable.format_rune(String(raw_rune)).trim_prefix("Rune: "))
	var law_lines: Array[String] = []
	for raw_law in laws:
		law_lines.append(player_readable.format_law(String(raw_law)).trim_prefix("Law: "))
	return "Skill: %s\nRune: %s\nLaw: %s" % [
		", ".join(skill_names) if not skill_names.is_empty() else "None",
		"; ".join(rune_lines) if not rune_lines.is_empty() else "None",
		"; ".join(law_lines) if not law_lines.is_empty() else "None",
	]


static func component_values(build: Dictionary, resolved: Dictionary, list_key: String, singular_key: String) -> Array:
	var list_value: Variant = build.get(list_key, null)
	if list_value is Array and not (list_value as Array).is_empty():
		return (list_value as Array).duplicate()
	var resolved_value: Variant = resolved.get(singular_key, null)
	if resolved_value is Array and not (resolved_value as Array).is_empty():
		return (resolved_value as Array).duplicate()
	if resolved_value is String and not (resolved_value as String).strip_edges().is_empty():
		return [resolved_value]
	return []
