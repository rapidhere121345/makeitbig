extends RefCounted

## Active-build authority extracted from ApplicationState: starting-fixture
## construction, legacy preset naming, the single resolution path every
## equip/preview/salvage/forge/validation caller shares, and the structural
## validator for the persisted active_build. Static; the profile is passed in.
const CharacterProgressionScript = preload("res://src/systems/character_progression.gd")
const EarlyItemRegistryScript = preload("res://src/content/early_item_registry.gd")
const BuildResolverScript = preload("res://src/systems/build_resolver.gd")
const CoreResult := preload("res://src/core/result.gd")
const ProfileRules := preload("res://src/game/application/profile_rules.gd")

const DEFAULT_RANGER_PRESET := "fixed_start"
const LEGACY_RANGER_PRESET := "exponential"
const PRESET_FIXTURES := {
	"fixed": "fixed_start",
	"start": "fixed_start",
	"fixed_start": "fixed_start",
	"convergent": "calibration_convergent",
	"stable": "calibration_convergent",
	"critical": "calibration_critical",
	"boundary": "calibration_critical",
	"exponential": "calibration_exponential",
	"growth": "calibration_exponential",
}


static func talent_context(source: Dictionary) -> Dictionary:
	return {"talents": (source.get("talents", {"allocated_ids":[],"stance":"mid"}) as Dictionary).duplicate(true), "talent_points": int(CharacterProgressionScript.snapshot(source.get("character", {})).points_earned), "unlocked_classes": source.get("unlocked_classes", ["ranger"])}


static func fixture_state(fixture_id: String) -> Dictionary:
	var registry: Variant = ProfileRules.loaded_item_registry()
	if registry == null or not registry.build_fixtures.has(fixture_id):
		return {}
	var fixture: Dictionary = registry.build_fixtures[fixture_id]
	var by_slot: Dictionary = registry.equipment_for_fixture(fixture_id)
	if by_slot.size() != EarlyItemRegistryScript.PROTOTYPE_OPEN_SLOTS.size():
		return {}
	var ids := empty_equipped_item_ids()
	var equipment: Array = []
	for slot in EarlyItemRegistryScript.PROTOTYPE_OPEN_SLOTS:
		var item: Dictionary = by_slot[slot]
		ids[slot] = String(item.instance_id)
		equipment.append(item.duplicate(true))
	var skills: Array = [String(fixture.skill_id), "", ""]
	return {
		"equipment": equipment,
		"active_build": {
			"skills": skills,
			"equipped_item_ids": ids,
		},
	}.duplicate(true)


static func empty_equipped_item_ids() -> Dictionary:
	var result := {}
	for slot in EarlyItemRegistryScript.EQUIPMENT_SLOTS:
		result[slot] = ""
	return result


static func fixture_id_for_legacy_name(value: String) -> String:
	var normalized := value.strip_edges().to_lower()
	if normalized.begins_with("calibration_"):
		return normalized if normalized in PRESET_FIXTURES.values() else ""
	return String(PRESET_FIXTURES.get(normalized, ""))


static func legacy_preset_for_active_build(build: Dictionary) -> String:
	match exact_fixture_for_build(build):
		"fixed_start", "calibration_convergent":
			return "convergent"
		"calibration_critical":
			return "critical"
		"calibration_exponential":
			return "exponential"
	return "custom"


static func exact_fixture_for_build(build: Dictionary) -> String:
	var equipped_value: Variant = build.get("equipped_item_ids", {})
	if not equipped_value is Dictionary:
		return ""
	var equipped: Dictionary = equipped_value
	var registry: Variant = ProfileRules.loaded_item_registry()
	if registry == null:
		return ""
	var fixture_ids: Array = ["fixed_start", "calibration_convergent", "calibration_critical", "calibration_exponential"]
	for fixture_id in fixture_ids:
		var fixture: Dictionary = registry.build_fixtures[fixture_id]
		var matches := true
		for slot in EarlyItemRegistryScript.EQUIPMENT_SLOTS:
			var expected := String(fixture.equipment.get(slot, ""))
			if String(equipped.get(slot, "")) != expected:
				matches = false
				break
		if matches:
			return fixture_id
	return ""


static func legacy_build_from_preset(preset_id: String) -> Dictionary:
	var registry: Variant = ProfileRules.loaded_content_registry()
	if registry == null or not registry.presets.has(preset_id):
		return {}
	var preset: Dictionary = registry.presets[preset_id]
	var equipment: Dictionary = (preset.equipment as Dictionary).duplicate(true)
	equipment["parameters"] = registry.preset_equipped_parameters.duplicate(true)
	return {
		"preset_id": preset_id,
		"equipment": equipment,
	}.duplicate(true)


static func fingerprint_for_fixture(profile: Dictionary, fixture_id: String) -> String:
	if fixture_id.is_empty():
		return ""
	var registry: Variant = ProfileRules.loaded_item_registry()
	if registry == null:
		return ""
	var fixture: Dictionary = registry.build_fixtures.get(fixture_id, {})
	if fixture.is_empty(): return ""
	var resolved: Dictionary = BuildResolverScript.new(registry).resolve(
		fixture.base_parameters, registry.equipment_for_fixture(fixture_id), String(fixture.skill_id), talent_context(profile)
	)
	return String(resolved.get("build_fingerprint", "")) if bool(resolved.get("ok", false)) else ""


static func resolve_active_build(profile: Dictionary, build: Dictionary) -> Dictionary:
	var inventory: Dictionary = profile.inventory
	return resolve_with_inventory(build, inventory.equipment, profile)


## `character_profile` supplies the talent/character context; callers pass the
## live profile, or the candidate profile while it is still being validated.
static func resolve_with_inventory(build: Dictionary, equipment_inventory: Array, character_profile: Dictionary) -> Dictionary:
	var registry: Variant = ProfileRules.loaded_item_registry()
	if registry == null:
		return CoreResult.failure("content_unavailable")
	var equipped_value: Variant = build.get("equipped_item_ids", {})
	if not equipped_value is Dictionary:
		return CoreResult.failure("invalid_active_build")
	var equipped_items := {}
	for slot in EarlyItemRegistryScript.PROTOTYPE_OPEN_SLOTS:
		var instance_id := String((equipped_value as Dictionary).get(slot, ""))
		if instance_id.is_empty():
			continue
		var item := ProfileRules.owned_equipment_from(equipment_inventory, instance_id)
		if item.is_empty() or String(item.get("slot", "")) != slot:
			return CoreResult.failure("equipped_item_not_owned")
		equipped_items[slot] = item
	if not registry.build_fixtures.has("fixed_start"):
		return CoreResult.failure("content_unavailable")
	var fixture: Dictionary = registry.build_fixtures.fixed_start
	var skills: Array = build.get("skills", [])
	var skill_id := String(skills[0]) if not skills.is_empty() else ""
	var resolver := BuildResolverScript.new(registry)
	return resolver.resolve(
		(fixture.base_parameters as Dictionary).duplicate(true),
		equipped_items,
		skill_id,
		talent_context(character_profile)
	)


static func resolved_connected_interfaces(resolved: Dictionary) -> Array[String]:
	var interfaces: Array[String] = []
	var value: Variant = resolved.get("connected_interfaces", null)
	if value is Array:
		for entry in value:
			if ProfileRules.is_text(entry):
				interfaces.append(String(entry))
	return interfaces


static func resolved_tag_ids(resolved: Dictionary) -> Array[String]:
	# The resolved Build currently exposes no authoritative tag set; never infer
	# tags from item affixes. Only honor a future explicit "tags" array.
	var tags: Array[String] = []
	var value: Variant = resolved.get("tags", null)
	if value is Array:
		for entry in value:
			if ProfileRules.is_text(entry):
				tags.append(String(entry))
	tags.sort()
	return tags


static func is_valid_active_build(build: Dictionary) -> bool:
	if not ProfileRules.has_exact_keys(build, ["skills", "equipped_item_ids"]):
		return false
	var skills: Variant = build.get("skills", null)
	if not (skills is Array) or (skills as Array).size() != 3:
		return false
	for skill in (skills as Array):
		if not ProfileRules.is_text(skill):
			return false
	var equipped: Variant = build.get("equipped_item_ids", null)
	if not (equipped is Dictionary) or not ProfileRules.has_exact_keys(equipped, EarlyItemRegistryScript.EQUIPMENT_SLOTS):
		return false
	var seen_ids := {}
	for slot in EarlyItemRegistryScript.EQUIPMENT_SLOTS:
		var instance_id: Variant = (equipped as Dictionary).get(slot, null)
		if not ProfileRules.is_text(instance_id):
			return false
		var id := String(instance_id)
		if slot not in EarlyItemRegistryScript.PROTOTYPE_OPEN_SLOTS and not id.is_empty():
			return false
		if not id.is_empty() and seen_ids.has(id):
			return false
		seen_ids[id] = true
	return true
