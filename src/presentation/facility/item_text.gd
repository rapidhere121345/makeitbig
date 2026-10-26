class_name FacilityItemText
extends RefCounted

## Pure text and formatting helpers shared by the facility pages. Everything here
## is static and screen-agnostic: a body reads only its own arguments, the tables
## re-declared below, and the other helpers in this module — never screen state.

const UiKit := preload("res://src/presentation/ui_kit.gd")
const EarlyInterfaceVocabularyScript = preload("res://src/content/early_interface_vocabulary.gd")

## Mirror of FacilityScreen.TRAINING_GROWTH_NAMES, kept verbatim while the table
## is still read by the screen's own presentation state.
const TRAINING_GROWTH_NAMES := {"convergent": "Convergent", "critical": "Critical", "exponential": "Exponential"}
## Mirror of FacilityScreen.LAW_TALLY_LABELS, kept verbatim while the table is
## still read by the screen's own salvage flow.
const LAW_TALLY_LABELS: Dictionary = {
	"inscribe": "Inscribe Law Tokens",
	"rewrite": "Rewrite Law Tokens",
	"refine": "Refine Law Tokens",
}


static func joined_or_none(value: Variant) -> String:
	var text := display_value(value)
	return text if not text.is_empty() else "None"


## Keep every production formatter character in order. Only blank lines are
## inserted before semantic sections; the rules, numbers and limitations are
## neither rewritten nor abbreviated by this presentation.
static func skill_detail_paragraphs(readable_text: String) -> String:
	var result := readable_text
	for heading: String in ["Target Rule: ", "Full Effect: ", "Cooldown: ", "Synergy: ", "Limits: "]:
		result = result.replace("\n" + heading, "\n\n" + heading)
	return result


static func resolved_interface_facts_text(value: Variant) -> String:
	var labels: Array[String] = []
	for id: Variant in UiKit.as_array(value):
		labels.append(EarlyInterfaceVocabularyScript.player_name(String(id)))
	return joined_or_none(labels)


## The one report the page is allowed to read: the build must have passed the test
## range and the stored report must carry exactly that fingerprint. Anything else is
## a report about a different build, and is reported as "not verified" instead of
## being shown as this build's readings.
static func matched_training_report(training: Dictionary, fingerprint: String) -> Dictionary:
	if fingerprint.is_empty():
		return {}
	var reports_by_fingerprint := UiKit.as_dictionary(training.get("reports_by_fingerprint", {}))
	var report := UiKit.as_dictionary(reports_by_fingerprint.get(fingerprint, {}))
	if report.is_empty() or String(report.get("build_fingerprint", "")).strip_edges() != fingerprint:
		return {}
	return report.duplicate(true)


## One readable card of the training page: an 18px state word over the value the
## page is allowed to read. The cards share the cold slate surface and the dim edge
## of the loadout cells; only the card that carries the conclusion takes the bright
## old-copper focus edge, so the one reading the first screen has to deliver is the
## one block that is marked. Nothing here is derived: the value is the resolved
## Build's own word or the matched report's own sentence.
static func training_interface_text(value: Variant) -> String:
	var labels: Array[String] = []
	for id: Variant in UiKit.as_array(value):
		labels.append(EarlyInterfaceVocabularyScript.player_name(String(id)))
	return joined_or_none(labels)


## The three numbers one matching report owns, and nothing else. With no matching
## report the line is the stand-in sentence: an older build's R, g or event count is
## never reprinted here as if it belonged to the current Build.
static func training_readings_text(report: Dictionary) -> String:
	if report.is_empty():
		return "Current build not yet trained"
	return "Training readings: R %s · g %s · Total Events %s" % [
		format_value(report.get("R", report.get("r", "Unknown"))),
		format_value(report.get("g", "Unknown")),
		String(report.get("event_count_display", format_value(report.get("event_count", "Unknown")))),
	]


## The complete raw report line of the one matching report. It is the reference
## layer, not the reading: it restates the matched numbers and adds the state word,
## the reproducible seed, the complete generational string and the report's own
## action sentence. A mismatching or unverified build gets the stand-in sentence and
## no field of the old report at all.
static func training_report_text(training: Dictionary, fingerprint: String, verified: bool) -> String:
	var report := matched_training_report(training, fingerprint) if verified else {}
	if report.is_empty():
		return "Current build not yet trained"
	var lines: Array[String] = [
		training_readings_text(report),
		"Growth Classification: %s" % String(TRAINING_GROWTH_NAMES.get(String(report.get("state", "Unknown")), String(report.get("state", "Unknown")))),
	]
	var curve := growth_curve_line(report.get("growth_curve", []))
	if not curve.is_empty():
		lines.append("Event Growth Curve: %s" % curve)
	var action := String(report.get("action", "")).strip_edges()
	if not action.is_empty():
		lines.append("Next Step: %s" % action)
	return "\n".join(lines)


## Renders growth_curve verbatim for display only. It keeps exactly the points that
## are Dictionaries with an exact-int generation and a non-empty String events_display;
## it never derives or recomputes any value.
static func growth_curve_line(value: Variant) -> String:
	var points := growth_curve_points(value)
	if points.is_empty():
		return ""
	var rendered: Array[String] = []
	for point in points:
		rendered.append("G%d:%s" % [int(point.get("generation", 0)), String(point.get("events_display", ""))])
	return " → ".join(rendered)


## The growth_curve points the page may draw, verbatim and in generation order. The
## filter is the text line's filter, so a trace can never show a point the report
## line drops. The magnitude field is only ever the report's own comparable number:
## the finite events_float it already carries, or its display string when that string
## is a plain decimal or scientific reading. Nothing is recomputed from R or g, and a
## point without such a number keeps magnitude NAN, which is what turns a trace into
## the order-only form instead of a made-up height.
static func growth_curve_points(value: Variant) -> Array[Dictionary]:
	if not value is Array:
		return []
	var points: Array[Dictionary] = []
	for entry: Variant in (value as Array):
		if not entry is Dictionary:
			continue
		var point: Dictionary = entry
		var generation: Variant = point.get("generation", null)
		if typeof(generation) != TYPE_INT:
			continue
		var events: Variant = point.get("events_display", "")
		if not events is String:
			continue
		var events_display := String(events).strip_edges()
		if events_display.is_empty():
			continue
		points.append({
			"generation": int(generation),
			"events_display": events_display,
			"magnitude": comparable_magnitude(point, events_display),
		})
	points.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("generation", 0)) < int(right.get("generation", 0))
	)
	return points


static func comparable_magnitude(point: Dictionary, events_display: String) -> float:
	var raw: Variant = point.get("events_float", null)
	if is_number(raw) and is_finite(float(raw)) and float(raw) > 0.0:
		return float(raw)
	if not is_decimal_reading(events_display):
		return NAN
	return float(events_display)


## True when a display string is a plain decimal or scientific reading, so the very
## same number can stand on an axis. A tower reading such as 10^^2(3.5), a unit
## suffix or any prose is not a comparable reading and keeps the trace on its
## order-only form.
static func is_decimal_reading(text: String) -> bool:
	var body := text.strip_edges()
	if body.is_empty():
		return false
	var digits := 0
	var digits_after_exponent := 0
	var seen_dot := false
	var seen_exponent := false
	for index in body.length():
		var character := body[index]
		if character >= "0" and character <= "9":
			digits += 1
			if seen_exponent:
				digits_after_exponent += 1
			continue
		if character == "." and not seen_dot and not seen_exponent:
			seen_dot = true
			continue
		if (character == "e" or character == "E") and not seen_exponent and digits > 0:
			seen_exponent = true
			continue
		if character == "+" or character == "-":
			if index == 0:
				continue
			if body[index - 1] == "e" or body[index - 1] == "E":
				continue
		return false
	if digits == 0:
		return false
	if seen_exponent and digits_after_exponent == 0:
		return false
	return true


static func is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func modifier_text(modifier: Dictionary) -> String:
	return "%s %s %s" % [
		String(modifier.get("parameter", "Unknown")),
		String(modifier.get("operation", "Unknown")),
		format_value(modifier.get("value", "Unknown")),
	]


static func append_preview_group(lines: Array[String], preview: Dictionary, key: String, label: String) -> void:
	var values := UiKit.as_array(preview.get(key, []))
	if values.is_empty():
		return
	if key.begins_with("interfaces_"):
		var names: Array[String] = []
		for value in values:
			names.append(EarlyInterfaceVocabularyScript.player_name(String(value)))
		lines.append("%s: %s" % [label, ", ".join(names)])
	else:
		lines.append("%s: %d items" % [label, values.size()])


static func law_token_name(operation: String, count: int = -1) -> String:
	var label := String(LAW_TALLY_LABELS.get(operation, "Law Tokens"))
	return label.trim_suffix("s") if count == 1 else label


static func forge_candidate_cost(candidate: Dictionary) -> int:
	var sequence := maxi(1, int(candidate.get("sequence_number", 1)))
	return maxi(1, int(candidate.get("cost", sequence)))


static func forge_candidate_result_item_view(candidate: Dictionary) -> Dictionary:
	var view := UiKit.as_dictionary(candidate.get("result_item_view", {}))
	return view if not view.is_empty() else UiKit.as_dictionary(candidate.get("result_item", {}))


static func nested_value(source: Dictionary, path: Array[String], fallback: Variant) -> Variant:
	var cursor: Variant = source
	for key in path:
		if not cursor is Dictionary or not (cursor as Dictionary).has(key):
			return fallback
		cursor = (cursor as Dictionary).get(key)
	return cursor


static func component_text(build: Dictionary, key: String, fallback: String) -> String:
	var value: Variant = build.get("%s_id" % key, build.get(key, null))
	if value == null:
		value = nested_value(build, ["components", key], null)
	if value == null and build.has("%ss" % key):
		var values := UiKit.as_array(build.get("%ss" % key, []))
		value = values[0] if not values.is_empty() else null
	var text := display_value(value)
	if key == "skill" and not text.is_empty():
		return "Piercing Arrow"
	if text.is_empty():
		return fallback
	var labels := {
		"piercing_arrow": "Piercing Arrow", "spawning_split": "Breeding Split", "spawn_split": "Breeding Split",
		"pack_hunt_mark": "Pack Hunt Mark", "group_hunt_mark": "Pack Hunt Mark",
	}
	return String(labels.get(text.to_lower(), text))


## The stable id behind a legacy component field, when the snapshot carries one.
## A display-only object such as {"name": "Breeding Split"} has no id, so the lookup
## stays empty and the component keeps its text without borrowing other art.
static func component_id(build: Dictionary, key: String) -> String:
	var value: Variant = build.get("%s_id" % key, build.get(key, null))
	if value == null:
		value = nested_value(build, ["components", key], null)
	if value == null and build.has("%ss" % key):
		var values := UiKit.as_array(build.get("%ss" % key, []))
		value = values[0] if not values.is_empty() else null
	if value is Dictionary:
		return String((value as Dictionary).get("id", ""))
	if value is String:
		return String(value)
	return ""


static func build_display_name(build: Dictionary, index: int, verified: bool) -> String:
	if verified:
		return String(build.get("verified_growth_name", build.get("growth_name", build.get("state", build.get("name", build.get("id", "Verified Preset"))))))
	var neutral_name := String(build.get("neutral_name", "")).strip_edges()
	if not neutral_name.is_empty():
		return neutral_name
	return "Preset %s" % String.chr(65 + clampi(index, 0, 25))


static func equipment_text(build: Dictionary) -> String:
	var value: Variant = build.get("equipment_summary", null)
	if value == null:
		var equipment := UiKit.as_dictionary(build.get("equipment", build.get("gear", {})))
		var details: Array[String] = []
		for key in ["name", "description", "summary", "affixes", "calibration"]:
			if equipment.has(key):
				var detail := display_value(equipment.get(key))
				if not detail.is_empty() and detail not in details:
					details.append(detail)
		value = "; ".join(details) if not details.is_empty() else null
	if value == null:
		value = nested_value(build, ["components", "equipment_summary"], null)
	var text := display_value(value)
	return text if not text.is_empty() else "Unknown"


static func display_value(value: Variant) -> String:
	if value is Dictionary:
		var dictionary: Dictionary = value
		for key in ["name", "label", "summary", "id"]:
			if dictionary.has(key):
				return String(dictionary.get(key))
		var parts: Array[String] = []
		for key in dictionary:
			parts.append("%s=%s" % [String(key), format_value(dictionary[key])])
		return ", ".join(parts)
	if value is Array:
		var parts: Array[String] = []
		for item in value:
			parts.append(display_value(item))
		return ", ".join(parts)
	return "" if value == null else str(value)


static func format_value(value: Variant) -> String:
	if typeof(value) == TYPE_FLOAT:
		return ("%.4f" % float(value)).trim_suffix("0").trim_suffix("0").trim_suffix("0").trim_suffix(".")
	return display_value(value)


static func core_canonical_name(value: Variant) -> String:
	var id := display_value(value).strip_edges().to_lower()
	var aliases := {
		"nearest_enemy": "near_enemy_horizon",
		"perception": "near_enemy_horizon",
		"movement": "direct_gait",
		"action": "direct_gait",
		"execution": "single_key_execution",
		"memory": "short_trace_memory",
	}
	return String(aliases.get(id, id))
