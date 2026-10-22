class_name EquipmentPresentationModel
extends RefCounted

## Node-free presentation data for equipment and forge surfaces. The caller owns
## the authoritative snapshot; this model only answers read-only display queries
## and never recomputes a build, a preview, or a random forge result.

const PlayerReadableBuildScript = preload("res://src/presentation/player_readable_build.gd")
const LAW_TALLY_LABELS: Dictionary = {
	"inscribe": "Inscribe Law Tokens",
	"rewrite": "Rewrite Law Tokens",
	"refine": "Refine Law Tokens",
}

var readable: PlayerReadableBuildScript
var base_items: Dictionary
var affix_families: Dictionary
var salvage_previews: Dictionary
var unknown_base_label := "Unknown Base"


func _init(
	readable_build: PlayerReadableBuildScript = null,
	snapshot_base_items: Dictionary = {},
	snapshot_affix_families: Dictionary = {},
	snapshot_salvage_previews: Dictionary = {},
	missing_item_label: String = "Unknown Base"
) -> void:
	readable = readable_build if readable_build != null else PlayerReadableBuildScript.new()
	base_items = snapshot_base_items
	affix_families = snapshot_affix_families
	salvage_previews = snapshot_salvage_previews
	unknown_base_label = missing_item_label


func same_slot_candidates(slot: String, equipped_id: String, inventory: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_item in inventory:
		if not raw_item is Dictionary:
			continue
		var item: Dictionary = raw_item
		if String(item.get("slot", "")) == slot and String(item.get("instance_id", "")) != equipped_id:
			result.append(item)
	return result


## query keys: keyword, family, min_tier, requires_rune, requires_law,
## requires_salvage, sort, reviewed_instance_id. It is a plain dictionary so the
## control layer can persist presentation state without exposing controls here.
func filter_sort(candidates: Array[Dictionary], query: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var needle := String(query.get("keyword", "")).strip_edges().to_lower()
	var family_filter := String(query.get("family", ""))
	var minimum_tier := int(query.get("min_tier", 0))
	var requires_rune := bool(query.get("requires_rune", false))
	var requires_law := bool(query.get("requires_law", false))
	var requires_salvage := bool(query.get("requires_salvage", false))
	var sort := String(query.get("sort", "name"))
	for item in candidates:
		var family_match := family_filter.is_empty()
		var highest_tier := 0
		var searchable := display_name(item).to_lower()
		for raw_affix in _array(item.get("affixes", [])):
			if not raw_affix is Dictionary:
				continue
			var affix: Dictionary = raw_affix
			var family_id := String(affix.get("family_id", ""))
			var family := _dictionary(affix_families.get(family_id, {}))
			searchable += " " + String(affix.get("family_name", family.get("name", ""))).to_lower()
			family_match = family_match or family_id == family_filter
			highest_tier = maxi(highest_tier, int(affix.get("tier", 0)))
		if not needle.is_empty() and not searchable.contains(needle):
			continue
		if not family_match or highest_tier < minimum_tier:
			continue
		if requires_rune and String(item.get("rune_id", "")).is_empty() and _dictionary(item.get("rune", {})).is_empty():
			continue
		if requires_law and String(item.get("law_id", "")).is_empty() and _dictionary(item.get("law", {})).is_empty():
			continue
		if requires_salvage and salvage_action(item).is_empty():
			continue
		result.append(item)
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if sort == "highest_tier":
			var tier_difference := highest_affix_tier(right) - highest_affix_tier(left)
			if tier_difference != 0:
				return tier_difference < 0
		elif sort == "affix_count":
			var count_difference := _array(right.get("affixes", [])).size() - _array(left.get("affixes", [])).size()
			if count_difference != 0:
				return count_difference < 0
		var left_name := display_name(left)
		var right_name := display_name(right)
		return left_name < right_name or (left_name == right_name and String(left.get("instance_id", "")) < String(right.get("instance_id", "")))
	)
	var reviewed_id := String(query.get("reviewed_instance_id", ""))
	if not reviewed_id.is_empty():
		for index in result.size():
			if String(result[index].get("instance_id", "")) == reviewed_id:
				var reviewed: Dictionary = result.pop_at(index)
				result.push_front(reviewed)
				break
	return result


func highest_affix_tier(item: Dictionary) -> int:
	var highest := 0
	for raw_affix in _array(item.get("affixes", [])):
		if raw_affix is Dictionary:
			highest = maxi(highest, int((raw_affix as Dictionary).get("tier", 0)))
	return highest


func display_name(item: Dictionary) -> String:
	for key in ["name", "display_name", "base_name"]:
		var explicit := String(item.get(key, "")).strip_edges()
		if not explicit.is_empty():
			return explicit
	var base_id := String(item.get("base_item_id", ""))
	var base := _dictionary(base_items.get(base_id, {}))
	var published := String(base.get("name", "")).strip_edges()
	if not published.is_empty():
		return published
	return unknown_base_label


func affix_labels(value: Variant, published_names: bool) -> Array[String]:
	var labels: Array[String] = []
	if not value is Array:
		return labels
	for raw_affix in value as Array:
		if not raw_affix is Dictionary:
			continue
		var affix: Dictionary = raw_affix
		var family_id := String(affix.get("family_id", affix.get("family", ""))).strip_edges()
		if family_id.is_empty():
			continue
		var label := family_id
		if published_names:
			var explicit := String(affix.get("name", "")).strip_edges()
			label = explicit if not explicit.is_empty() else published_name("affix_families", family_id)
			if label == family_id:
				label = "Unknown Affix"
		var tier := ""
		if affix.has("tier"):
			tier = " " + readable.tier_label(int(affix.get("tier", 0))) if published_names else " T%d" % int(affix.get("tier", 0))
		labels.append("%s%s" % [label, tier])
	return labels


func compact_difference(item: Dictionary) -> String:
	var labels: Array[String] = []
	for raw_affix in _array(item.get("affixes", [])):
		if raw_affix is Dictionary:
			labels.append(readable.format_affix(raw_affix).get_slice(": ", 0))
	if not labels.is_empty():
		var shown := labels.slice(0, 2)
		if labels.size() > 2:
			shown.append("+%d" % (labels.size() - 2))
		return "; ".join(shown)
	var parts: Array[String] = []
	var rune_id := String(item.get("rune_id", "")).strip_edges()
	var law_id := String(item.get("law_id", "")).strip_edges()
	if not rune_id.is_empty():
		parts.append("Rune %s" % modifier_name(rune_id))
	if not law_id.is_empty():
		parts.append("Law %s" % modifier_name(law_id))
	return "; ".join(parts) if not parts.is_empty() else "No Affixes"


func current_inline_summary(item: Dictionary) -> String:
	var base_effects := _base_effect_labels(item)
	var affix_identities := _affix_identities(item)
	return "%s · Base %s · %s\nAffixes %s · Rune %s · Law %s" % [
		readable.slot_label(String(item.get("slot", ""))),
		display_name(item),
		"; ".join(base_effects) if not base_effects.is_empty() else "None",
		"; ".join(affix_identities) if not affix_identities.is_empty() else "None",
		modifier_name(String(item.get("rune_id", ""))).get_slice("|", 0),
		modifier_name(String(item.get("law_id", ""))).get_slice("|", 0),
	]


## comparison_note: "" keeps the bare facts; "included" extends the base line
## with the standing clarification that the base-material multipliers are
## already inside the authoritative comparison shown above; "no_preview" says
## no valid preview exists instead of implying a comparison happened. The note
## rides the existing base line so the standard facts stay three lines.
func candidate_inline_facts(item: Dictionary, comparison_note: String = "") -> String:
	var base_effects := _base_effect_labels(item)
	var affix_identities := _affix_identities(item)
	var extras: Array[String] = []
	if not affix_identities.is_empty():
		extras.append("Affixes " + ", ".join(affix_identities))
	if not String(item.get("rune_id", "")).is_empty():
		extras.append("With Rune")
	if not String(item.get("law_id", "")).is_empty():
		extras.append("With Law")
	var base_text := "; ".join(base_effects) if not base_effects.is_empty() else "None"
	if comparison_note == "included" and not base_effects.is_empty():
		base_text += " · Multiplier included in the comparison above"
	elif comparison_note == "no_preview":
		base_text += " · No valid preview; multiplier not compared"
	var lines: Array[String] = [
		readable.slot_label(String(item.get("slot", ""))),
		"Base Stats: %s" % base_text,
		" · ".join(extras) if not extras.is_empty() else "No Affixes / Runes / Laws",
	]
	return "\n".join(lines)


func salvage_action(item: Dictionary) -> Dictionary:
	var instance_id := String(item.get("instance_id", ""))
	if instance_id.is_empty() or bool(item.get("protected", false)):
		return {}
	var preview := _dictionary(salvage_previews.get(instance_id, null))
	if preview.is_empty() or not bool(preview.get("ok", false)):
		return {}
	var operation := String(preview.get("operation", "")).strip_edges().to_lower()
	if not LAW_TALLY_LABELS.has(operation):
		return {}
	var amount: Variant = preview.get("amount", null)
	if typeof(amount) != TYPE_INT or int(amount) < 1:
		return {}
	return {"operation": operation, "amount": int(amount), "label": String(LAW_TALLY_LABELS[operation])}


func result_face(entry: Dictionary) -> String:
	var affixes := affix_labels(entry.get("affixes", null), true)
	var line := "%s · Stored · Not equipped; current build unchanged\nAffixes: %s" % [
		readable.slot_label(String(entry.get("slot", ""))),
		", " .join(affixes) if not affixes.is_empty() else "No Record",
	]
	if entry.has("rune_id") or entry.has("law_id") or entry.has("current_parameters") or entry.has("equipped_parameters"):
		line += "\nSee details for full stats"
	return line


func result_full(entry: Dictionary) -> String:
	var current := _dictionary(entry.get("current_parameters", {}))
	var equipped := _dictionary(entry.get("equipped_parameters", {}))
	return "Added to equipment storage · Not equipped; current build unchanged\n%s" % readable.format_item(entry, current, equipped)


func result_audit(entry: Dictionary) -> String:
	var slot := String(entry.get("slot", ""))
	var slot_label: String = String(readable.slot_label(slot)) if not slot.is_empty() else "Unknown"
	var base_id := String(entry.get("base_item_id", ""))
	var base_text := base_id if not base_id.is_empty() else "Unknown Base"
	var affixes := affix_labels(entry.get("affixes", null), false)
	var line := "Slot: %s    Name: %s    Base: %s    Affixes: %s    ID: %s" % [
		slot_label,
		display_name(entry),
		base_text,
		" / ".join(affixes) if not affixes.is_empty() else "None",
		instance_id_text(entry.get("instance_id", null)),
	]
	var extras := _result_extra_fields(entry)
	return line if extras.is_empty() else "%s    %s" % [line, extras]


func published_name(table: String, id: String) -> String:
	var row := _dictionary((base_items if table == "base_items" else affix_families).get(id, null))
	var published := String(row.get("name", "")).strip_edges()
	return published if not published.is_empty() else id


func modifier_name(modifier_id: String) -> String:
	if modifier_id.is_empty():
		return "None"
	var rune_text := String(readable.format_rune(modifier_id))
	if not rune_text.contains("Unknown Rune"):
		return rune_text.trim_prefix("Rune: ")
	return String(readable.format_law(modifier_id)).trim_prefix("Law: ")


func instance_id_text(value: Variant) -> String:
	if not value is String and not value is int and not value is float:
		return "Unknown"
	var instance_id := String(value)
	return instance_id if not instance_id.is_empty() else "Unknown"


func _base_effect_labels(item: Dictionary) -> Array[String]:
	var labels: Array[String] = []
	var base := _dictionary(base_items.get(String(item.get("base_item_id", "")), {}))
	for raw_modifier in _array(base.get("modifiers", [])):
		if raw_modifier is Dictionary:
			labels.append(String(readable.format_modifier(raw_modifier)).get_slice("(", 0))
	return labels


func _affix_identities(item: Dictionary) -> Array[String]:
	var identities: Array[String] = []
	for raw_affix in _array(item.get("affixes", [])):
		if not raw_affix is Dictionary:
			continue
		var affix: Dictionary = raw_affix
		var family := _dictionary(affix_families.get(String(affix.get("family_id", "")), {}))
		identities.append("%s %s" % [
			String(family.get("name", "Unknown Affix")),
			String(readable.tier_label(int(affix.get("tier", 0)))),
		])
	return identities


func _result_extra_fields(entry: Dictionary) -> String:
	var parts: Array[String] = []
	var source: Variant = entry.get("source", null)
	var source_text := _raw_text(source)
	if not source_text.is_empty():
		parts.append("Source: %s" % source_text)
	var rune_id := String(entry.get("rune_id", "")).strip_edges()
	if not rune_id.is_empty():
		parts.append("Rune: %s" % rune_id)
	var law_id := String(entry.get("law_id", "")).strip_edges()
	if not law_id.is_empty():
		parts.append("Law: %s" % law_id)
	var law_seed: Variant = entry.get("law_seed", null)
	if law_seed is int or law_seed is float or law_seed is String:
		parts.append("Sacred Law Seed: %s" % str(law_seed))
	return "    ".join(parts)


func _raw_text(value: Variant) -> String:
	if value == null:
		return ""
	if value is bool or value is int or value is float or value is String:
		return str(value)
	return JSON.stringify(value)


func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


func _array(value: Variant) -> Array:
	return value if value is Array else []
