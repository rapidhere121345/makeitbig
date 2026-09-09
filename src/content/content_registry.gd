class_name ContentRegistry
extends RefCounted

## Loads the v1 proxy-component and ranger-preset content from plain JSON
## (docs/GAME_DESIGN_FINAL_v1.0.md chapter 14 and sections 4.1 / 19.1) and
## performs structural validation only. Content files are pure data: this
## registry never instantiates, compiles, or executes anything from them.

const PROXY_PATH := "res://content/proxy_components.json"
const PRESET_PATH := "res://content/ranger_presets.json"

const CORE_SLOTS: Array[String] = ["perception", "movement", "execution", "memory"]
const ATTACHMENT_CATEGORIES: Array[String] = ["scavenging", "navigation", "tactics", "cycle_tempo", "stability"]
const FIRMWARE_COMPATIBLE_SLOTS: Array[String] = ["perception", "movement", "execution", "memory", "attachment"]
const EXPECTED_SCHEMA_VERSION := 1
const EXPECTED_CORES_PER_SLOT := 4
const EXPECTED_ATTACHMENTS_PER_CATEGORY := 2
const EXPECTED_FIRMWARE_COUNT := 16
const EXPECTED_FIRMWARE_PER_SLOT := {
	"perception": 3,
	"movement": 3,
	"execution": 4,
	"memory": 3,
	"attachment": 3,
}
const EXPECTED_NUMERIC_SLOTS := 3
const ATTACHMENT_PRESET_SIZE := 3

var cores := {}
var attachments := {}
var firmwares := {}
var preset_shared_parameters := {}
var preset_equipped_parameters := {}
var presets := {}
var preset_order: Array[String] = []


func load_all() -> Array[String]:
	cores.clear()
	attachments.clear()
	firmwares.clear()
	preset_shared_parameters.clear()
	preset_equipped_parameters.clear()
	presets.clear()
	preset_order.clear()
	var failures: Array[String] = []
	var proxy_data := _read_json(PROXY_PATH)
	if proxy_data.is_empty():
		failures.append("registry: cannot read/parse %s" % PROXY_PATH)
	else:
		failures.append_array(validate_proxy_components(proxy_data))
		if failures.is_empty():
			_ingest_proxy(proxy_data)
	var preset_data := _read_json(PRESET_PATH)
	if preset_data.is_empty():
		failures.append("registry: cannot read/parse %s" % PRESET_PATH)
	else:
		failures.append_array(validate_ranger_presets(preset_data))
		if failures.is_empty():
			_ingest_presets(preset_data)
	return failures


func validate_proxy_components(data: Dictionary) -> Array[String]:
	var failures: Array[String] = []
	if data.get("schema_version", null) != EXPECTED_SCHEMA_VERSION:
		failures.append("proxy: schema_version must be %d" % EXPECTED_SCHEMA_VERSION)
	var cores_list: Array = data.get("cores", [])
	var attachments_list: Array = data.get("attachments", [])
	var firmwares_list: Array = data.get("firmwares", [])
	# No early exit on empty lists: the census checks below must still report
	# every missing slot, category, and firmware shortfall.
	var seen := {}
	var per_slot := {}
	for slot in CORE_SLOTS:
		per_slot[slot] = 0
	var per_category := {}
	for category in ATTACHMENT_CATEGORIES:
		per_category[category] = 0
	for entry in cores_list:
		if not (entry is Dictionary):
			failures.append("proxy: core entry must be an object")
			continue
		var entry_dict: Dictionary = entry
		var id := _checked_id(entry_dict, seen, failures, "core")
		var slot := _checked_text(entry_dict, "slot", failures, id, "core")
		if slot != "" and slot not in CORE_SLOTS:
			failures.append("core %s: unknown slot '%s'" % [id, slot])
		elif slot != "":
			per_slot[slot] = int(per_slot[slot]) + 1
		_checked_name(entry_dict, id, failures, "core")
		_checked_text(entry_dict, "protocol", failures, id, "core")
		_checked_numeric_slots(entry_dict, id, failures, "core")
	for entry in attachments_list:
		if not (entry is Dictionary):
			failures.append("proxy: attachment entry must be an object")
			continue
		var entry_dict: Dictionary = entry
		var id := _checked_id(entry_dict, seen, failures, "attachment")
		var category := _checked_text(entry_dict, "category", failures, id, "attachment")
		if category != "" and category not in ATTACHMENT_CATEGORIES:
			failures.append("attachment %s: unknown category '%s'" % [id, category])
		elif category != "":
			per_category[category] = int(per_category[category]) + 1
		_checked_name(entry_dict, id, failures, "attachment")
		_checked_text(entry_dict, "protocol", failures, id, "attachment")
		_checked_numeric_slots(entry_dict, id, failures, "attachment")
	for slot in CORE_SLOTS:
		if int(per_slot[slot]) != EXPECTED_CORES_PER_SLOT:
			failures.append("proxy: core slot %s has %d entries, expected %d"
				% [slot, int(per_slot[slot]), EXPECTED_CORES_PER_SLOT])
	for category in ATTACHMENT_CATEGORIES:
		if int(per_category[category]) != EXPECTED_ATTACHMENTS_PER_CATEGORY:
			failures.append("proxy: attachment category %s has %d entries, expected %d"
				% [category, int(per_category[category]), EXPECTED_ATTACHMENTS_PER_CATEGORY])
	if firmwares_list.size() != EXPECTED_FIRMWARE_COUNT:
		failures.append("proxy: %d firmwares, expected %d"
			% [firmwares_list.size(), EXPECTED_FIRMWARE_COUNT])
	var firmware_per_slot := {}
	for slot in FIRMWARE_COMPATIBLE_SLOTS:
		firmware_per_slot[slot] = 0
	for entry in firmwares_list:
		if not (entry is Dictionary):
			failures.append("proxy: firmware entry must be an object")
			continue
		var entry_dict: Dictionary = entry
		var id := _checked_id(entry_dict, seen, failures, "firmware")
		var compatible := _checked_text(entry_dict, "compatible_slot", failures, id, "firmware")
		if compatible != "" and compatible not in FIRMWARE_COMPATIBLE_SLOTS:
			failures.append("firmware %s: unknown compatible_slot '%s'" % [id, compatible])
		elif compatible != "":
			firmware_per_slot[compatible] = int(firmware_per_slot[compatible]) + 1
		_checked_name(entry_dict, id, failures, "firmware")
		_checked_text(entry_dict, "semantics", failures, id, "firmware")
	for slot in FIRMWARE_COMPATIBLE_SLOTS:
		var expected: int = int(EXPECTED_FIRMWARE_PER_SLOT[slot])
		if int(firmware_per_slot[slot]) != expected:
			failures.append("proxy: firmware slot %s has %d entries, expected %d"
				% [slot, int(firmware_per_slot[slot]), expected])
	return failures


func validate_ranger_presets(data: Dictionary) -> Array[String]:
	var failures: Array[String] = []
	if data.get("schema_version", null) != EXPECTED_SCHEMA_VERSION:
		failures.append("presets: schema_version must be %d" % EXPECTED_SCHEMA_VERSION)
	var shared: Variant = data.get("shared_parameters", {})
	if not (shared is Dictionary) or (shared as Dictionary).is_empty():
		failures.append("presets: missing shared_parameters")
	else:
		failures.append_array(_validate_parameter_block(shared, "shared_parameters"))
	var equipped: Variant = data.get("prototype_equipped_parameters", {})
	if not (equipped is Dictionary) or (equipped as Dictionary).is_empty():
		failures.append("presets: missing prototype_equipped_parameters")
	else:
		failures.append_array(_validate_parameter_block(equipped, "prototype_equipped_parameters"))
	var preset_list: Variant = data.get("presets", [])
	if not (preset_list is Array) or (preset_list as Array).is_empty():
		failures.append("presets: missing presets list")
		return failures
	var seen := {}
	for entry in (preset_list as Array):
		if not (entry is Dictionary):
			failures.append("presets: preset entry must be an object")
			continue
		var entry_dict: Dictionary = entry
		var id := String(entry_dict.get("id", ""))
		if id == "":
			failures.append("presets: preset without an id")
			continue
		if seen.has(id):
			failures.append("presets: duplicate preset id '%s'" % id)
			continue
		seen[id] = true
		if String(entry_dict.get("name", "")) == "":
			failures.append("preset %s: missing name" % id)
		var p_value: Variant = entry_dict.get("p", null)
		if not _is_number(p_value):
			failures.append("preset %s: p must be a number" % id)
		elif _as_float(p_value) <= 0.0 or _as_float(p_value) > 1.0:
			failures.append("preset %s: p=%s out of range (0, 1]" % [id, str(p_value)])
	return failures


## An attachment preset equips the three untyped attachment slots.
## Same-category duplicates are forbidden by the design (chapter 14.1).
func validate_attachment_preset(attachment_ids: Array) -> Array[String]:
	var failures: Array[String] = []
	if attachment_ids.size() != ATTACHMENT_PRESET_SIZE:
		failures.append("attachment preset must equip exactly %d attachments"
			% ATTACHMENT_PRESET_SIZE)
	var seen_ids := {}
	var seen_categories := {}
	for raw_id in attachment_ids:
		var id := String(raw_id)
		if not attachments.has(id):
			failures.append("attachment preset: unknown attachment id '%s'" % id)
			continue
		if seen_ids.has(id):
			failures.append("attachment preset: duplicate attachment '%s'" % id)
			continue
		seen_ids[id] = true
		var category := String((attachments[id] as Dictionary).get("category", ""))
		if seen_categories.has(category):
			failures.append("attachment preset: category '%s' repeated" % category)
			continue
		seen_categories[category] = true
	return failures


func core_ids() -> Array:
	return cores.keys()


func attachment_ids() -> Array:
	return attachments.keys()


func firmware_ids() -> Array:
	return firmwares.keys()


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed
	return {}


func _ingest_proxy(data: Dictionary) -> void:
	for entry in (data.get("cores", []) as Array):
		cores[String(entry["id"])] = entry
	for entry in (data.get("attachments", []) as Array):
		attachments[String(entry["id"])] = entry
	for entry in (data.get("firmwares", []) as Array):
		firmwares[String(entry["id"])] = entry


func _ingest_presets(data: Dictionary) -> void:
	preset_shared_parameters = data.get("shared_parameters", {})
	preset_equipped_parameters = data.get("prototype_equipped_parameters", {})
	for entry in (data.get("presets", []) as Array):
		var id := String(entry["id"])
		presets[id] = entry
		preset_order.append(id)


func _validate_parameter_block(block: Dictionary, block_name: String) -> Array[String]:
	var failures: Array[String] = []
	for key in ["shared_lifetime", "distance", "speed", "minimum_turn_time"]:
		var value: Variant = block.get(key, null)
		if not _is_number(value):
			failures.append("presets: %s.%s must be a number" % [block_name, key])
		elif _as_float(value) <= 0.0:
			failures.append("presets: %s.%s must be positive" % [block_name, key])
	return failures


func _checked_id(entry: Dictionary, seen: Dictionary, failures: Array[String], kind: String) -> String:
	var id := String(entry.get("id", ""))
	if id == "":
		failures.append("%s entry without an id" % kind)
		return kind + "??"
	if seen.has(id):
		failures.append("duplicate id '%s' across proxy components" % id)
		return id
	seen[id] = true
	return id


func _checked_name(entry: Dictionary, id: String, failures: Array[String], kind: String) -> void:
	if String(entry.get("name", "")) == "":
		failures.append("%s %s: missing name" % [kind, id])


func _checked_text(entry: Dictionary, key: String, failures: Array[String], id: String, kind: String) -> String:
	var raw_value: Variant = entry.get(key, null)
	var value: String = raw_value.strip_edges() if raw_value is String else ""
	if value.is_empty():
		failures.append("%s %s: missing %s" % [kind, id, key])
	return value


func _checked_numeric_slots(entry: Dictionary, id: String, failures: Array[String], kind: String) -> void:
	var value: Variant = entry.get("numeric_slots", null)
	if not _is_number(value) or int(value) != EXPECTED_NUMERIC_SLOTS:
		failures.append("%s %s: numeric_slots must be %d" % [kind, id, EXPECTED_NUMERIC_SLOTS])


func _is_number(value: Variant) -> bool:
	return value is int or value is float


func _as_float(value: Variant) -> float:
	if value is int or value is float:
		return float(value)
	return -1.0
