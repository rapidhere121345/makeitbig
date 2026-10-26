extends RefCounted

## Leaf helpers shared by every ApplicationState collaborator: the profile
## schema version, value predicates for untrusted persisted data, inventory
## lookups and the content-registry loaders. Static and stateless.
const ContentRegistryScript = preload("res://src/content/content_registry.gd")
const EarlyCampaignRegistryScript = preload("res://src/content/early_campaign_registry.gd")
const EarlyItemRegistryScript = preload("res://src/content/early_item_registry.gd")

const SCHEMA_VERSION := 10
const FORGE_OPERATIONS := ["inscribe", "rewrite", "refine"]


static func is_text(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME


static func is_non_negative_integer(value: Variant) -> bool:
	return is_exact_integer(value) and int(value) >= 0


static func is_exact_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var number := float(value)
	return not is_nan(number) and not is_inf(number) and floor(number) == number


static func has_exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key in expected:
		if not value.has(key):
			return false
	return true


static func is_fingerprint(value: Variant) -> bool:
	if not is_text(value):
		return false
	var fingerprint := String(value)
	if fingerprint.length() != 64:
		return false
	for character in fingerprint:
		if character not in "0123456789abcdef":
			return false
	return true


static func loaded_content_registry() -> Variant:
	var registry := ContentRegistryScript.new()
	if not registry.load_all().is_empty():
		return null
	return registry


static func loaded_item_registry() -> Variant:
	var registry := EarlyItemRegistryScript.new()
	if not registry.load_all().is_empty():
		return null
	return registry


static func loaded_early_campaign_registry() -> Variant:
	var registry := EarlyCampaignRegistryScript.new()
	if not registry.load_campaign().is_empty():
		return null
	return registry


static func is_valid_item_instance(value: Variant) -> bool:
	var registry: Variant = loaded_item_registry()
	return registry != null and registry.validate_item_instance(value).is_empty()


static func owned_equipment(profile: Dictionary, instance_id: String) -> Dictionary:
	if profile.is_empty():
		return {}
	var inventory_value: Variant = profile.get("inventory", {})
	if not inventory_value is Dictionary:
		return {}
	var equipment_value: Variant = (inventory_value as Dictionary).get("equipment", [])
	if not equipment_value is Array:
		return {}
	return owned_equipment_from(equipment_value, instance_id)


static func owned_equipment_from(equipment: Array, instance_id: String) -> Dictionary:
	for item in equipment:
		if item is Dictionary and String((item as Dictionary).get("instance_id", "")) == instance_id:
			return (item as Dictionary).duplicate(true)
	return {}


static func equipment_index(equipment: Array, instance_id: String) -> int:
	for index in equipment.size():
		if equipment[index] is Dictionary and String((equipment[index] as Dictionary).get("instance_id", "")) == instance_id:
			return index
	return -1
