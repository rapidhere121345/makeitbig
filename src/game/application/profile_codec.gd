extends RefCounted

## Persistent-payload codec extracted from ApplicationState: builds the save
## payload, validates an untrusted payload against the exact schema-10 profile
## shape, and normalizes JSON-decoded numbers. Static and side-effect free; the
## owner commits a parsed payload only after every check has passed.
const CharacterProgressionScript = preload("res://src/systems/character_progression.gd")
const ProxyBuildScript = preload("res://src/systems/proxy_build.gd")
const CoreResult := preload("res://src/core/result.gd")
const ProfileRules := preload("res://src/game/application/profile_rules.gd")
const BuildResolution := preload("res://src/game/application/build_resolution.gd")
const CampaignProgress := preload("res://src/game/application/campaign_progress.gd")
const ProxyBuilds := preload("res://src/game/application/proxy_builds.gd")

const SUPPORTED_CLASSES := ["ranger", "alchemist", "mage"]
const SAFE_ROUTES := ["title", "tutorial", "base"]


static func payload_for_profile(profile_value: Dictionary, last_result: Dictionary, safe_route: String) -> Dictionary:
	var route := safe_route if safe_route in SAFE_ROUTES else "base"
	if profile_value.is_empty():
		route = "title"
	return {
		"schema_version": ProfileRules.SCHEMA_VERSION,
		"profile": profile_value.duplicate(true),
		"last_result": last_result.duplicate(true),
		"safe_route": route,
	}.duplicate(true)


## Returns a failure result, or {"ok": true, "profile", "last_result", "route"}
## with the profile already number-normalized.
static func parse_payload(payload: Variant) -> Dictionary:
	if not (payload is Dictionary):
		return CoreResult.failure("invalid_payload")
	var candidate: Dictionary = payload
	var schema: Variant = candidate.get("schema_version", null)
	if not ProfileRules.is_exact_integer(schema) or int(schema) != ProfileRules.SCHEMA_VERSION:
		return CoreResult.failure("unsupported_schema_version")
	var candidate_profile: Variant = candidate.get("profile", null)
	if not (candidate_profile is Dictionary):
		return CoreResult.failure("invalid_profile")
	var restored_profile: Dictionary = (candidate_profile as Dictionary).duplicate(true)
	if not restored_profile.is_empty() and not is_valid_profile(restored_profile):
		return CoreResult.failure("invalid_profile")
	if not restored_profile.is_empty():
		_normalize_current_profile_numbers(restored_profile)
	var candidate_result: Variant = candidate.get("last_result", {})
	if not (candidate_result is Dictionary):
		return CoreResult.failure("invalid_last_result")
	var route_value: Variant = candidate.get("safe_route", "title")
	if not ProfileRules.is_text(route_value) or String(route_value) not in SAFE_ROUTES:
		return CoreResult.failure("invalid_safe_route")
	var route := String(route_value)
	if restored_profile.is_empty():
		route = "title"
	return {
		"ok": true,
		"profile": restored_profile.duplicate(true),
		"last_result": (candidate_result as Dictionary).duplicate(true),
		"route": route,
	}


static func is_valid_profile(candidate: Dictionary) -> bool:
	var profile_schema: Variant = candidate.get("schema_version", null)
	if not ProfileRules.is_exact_integer(profile_schema) or int(profile_schema) != ProfileRules.SCHEMA_VERSION:
		return false
	if String(candidate.get("profile_id", "")).strip_edges().is_empty():
		return false
	var initial_class: Variant = candidate.get("initial_class", null)
	if not ProfileRules.is_text(initial_class) or String(initial_class) not in SUPPORTED_CLASSES:
		return false
	if typeof(candidate.get("tutorial_complete", null)) != TYPE_BOOL:
		return false
	if not CampaignProgress.is_valid_story(candidate):
		return false
	if not CharacterProgressionScript.is_valid_state(candidate.get("character")):
		return false
	var talents_value: Variant = candidate.get("talents")
	if not talents_value is Dictionary or not ProfileRules.has_exact_keys(talents_value, ["allocated_ids", "stance"]):
		return false
	if not talents_value.get("allocated_ids") is Array or String(talents_value.get("stance", "")) not in ["near", "mid", "far"]:
		return false
	var unlocked: Variant = candidate.get("unlocked_classes", null)
	if not (unlocked is Array) or (unlocked as Array).is_empty():
		return false
	var seen := {}
	for unlocked_class in (unlocked as Array):
		if not ProfileRules.is_text(unlocked_class) or String(unlocked_class) not in SUPPORTED_CLASSES or seen.has(String(unlocked_class)):
			return false
		seen[String(unlocked_class)] = true
	if not seen.has(String(initial_class)):
		return false
	var resources: Variant = candidate.get("resources", null)
	if not (resources is Dictionary) or not ProfileRules.has_exact_keys(resources as Dictionary, ["law_tallies"]):
		return false
	var tallies: Variant = (resources as Dictionary).get("law_tallies", null)
	if not (tallies is Dictionary) or not ProfileRules.has_exact_keys(tallies as Dictionary, ProfileRules.FORGE_OPERATIONS):
		return false
	for operation in ProfileRules.FORGE_OPERATIONS:
		if not ProfileRules.is_non_negative_integer((tallies as Dictionary).get(operation, null)):
			return false
	if candidate.has("forge"):
		return false
	var inventory: Variant = candidate.get("inventory", null)
	if not _is_valid_partitioned_inventory(inventory):
		return false
	if not (candidate.get("build_presets", null) is Array):
		return false
	var active_build: Variant = candidate.get("active_build", null)
	if not (active_build is Dictionary):
		return false
	var proxy_build: Variant = candidate.get("proxy_build", null)
	if not (proxy_build is Dictionary) or not ProfileRules.has_exact_keys(proxy_build as Dictionary, ["cores", "settings", "attachments"]):
		return false
	if not ((proxy_build as Dictionary).get("cores", null) is Array) or ((proxy_build as Dictionary).get("cores") as Array).size() != 4:
		return false
	if not ((proxy_build as Dictionary).get("settings", null) is Dictionary):
		return false
	if not ((proxy_build as Dictionary).get("attachments", null) is Array) or ((proxy_build as Dictionary).get("attachments") as Array).size() != 3:
		return false
	for core_id in (proxy_build as Dictionary).cores:
		if not ProfileRules.is_text(core_id):
			return false
	for attachment_id in (proxy_build as Dictionary).attachments:
		if not ProfileRules.is_text(attachment_id) or not String(attachment_id).is_empty():
			return false
	var selected_cores: Array = (proxy_build as Dictionary).cores
	var any_selected := false
	for core_id in selected_cores:
		any_selected = any_selected or not String(core_id).is_empty()
	if any_selected:
		var owned_core_ids := {}
		for component in (inventory as Dictionary).proxy_components:
			owned_core_ids[String((component as Dictionary).id)] = true
		for core_id in selected_cores:
			if not owned_core_ids.has(String(core_id)):
				return false
		var proxy_registry: Variant = ProfileRules.loaded_content_registry()
		if proxy_registry == null or not bool(ProxyBuildScript.compile(ProxyBuilds.compile_input(proxy_build as Dictionary), proxy_registry.cores).get("ok", false)):
			return false
	elif not (proxy_build as Dictionary).settings.is_empty():
		return false
	if not (candidate.get("discoveries", null) is Array):
		return false
	var immortality: Variant = candidate.get("immortality", null)
	if not (immortality is Dictionary) or typeof((immortality as Dictionary).get("unlocked", null)) != TYPE_BOOL or not ((immortality as Dictionary).get("proofs", null) is Array):
		return false
	var progression: Variant = candidate.get("progression", null)
	if not (progression is Dictionary) or not ProfileRules.is_non_negative_integer((progression as Dictionary).get("contract_wins", null)):
		return false
	if typeof((progression as Dictionary).get("ending_unlocked", null)) != TYPE_BOOL:
		return false
	if not BuildResolution.is_valid_active_build(active_build as Dictionary):
		return false
	if not bool(BuildResolution.resolve_with_inventory(active_build, (inventory as Dictionary).equipment, candidate).get("ok", false)):
		return false
	var training: Variant = candidate.get("training", null)
	if not (training is Dictionary) or not ProfileRules.has_exact_keys(training as Dictionary, ["reports_by_fingerprint"]):
		return false
	var reports_by_fingerprint: Variant = (training as Dictionary).get("reports_by_fingerprint", null)
	if not (reports_by_fingerprint is Dictionary):
		return false
	for fingerprint: Variant in (reports_by_fingerprint as Dictionary):
		if not ProfileRules.is_fingerprint(fingerprint):
			return false
		var report: Variant = (reports_by_fingerprint as Dictionary)[fingerprint]
		if not (report is Dictionary) or String((report as Dictionary).get("build_fingerprint", "")) != String(fingerprint):
			return false
	for flag in ["threshold_colossus_defeated", "proxy_unlocked", "early_game_complete"]:
		if typeof((progression as Dictionary).get(flag, null)) != TYPE_BOOL:
			return false
	if not ProfileRules.is_non_negative_integer((progression as Dictionary).get("auto_contract_wins", null)):
		return false
	if not CampaignProgress.is_valid_repeatable_completion_counts((progression as Dictionary).get("repeatable_completion_counts", null)):
		return false
	if not CampaignProgress.is_valid_completed_node_ids((progression as Dictionary).get("completed_node_ids", null)):
		return false
	return true


static func _normalize_current_profile_numbers(candidate: Dictionary) -> void:
	candidate["schema_version"] = ProfileRules.SCHEMA_VERSION
	candidate.character.experience = int(candidate.character.experience)
	var tallies: Dictionary = (candidate.resources as Dictionary).law_tallies
	for operation in ProfileRules.FORGE_OPERATIONS:
		tallies[operation] = int(tallies[operation])
	var progression: Dictionary = candidate.progression
	progression["contract_wins"] = int(progression.contract_wins)
	progression["auto_contract_wins"] = int(progression.auto_contract_wins)
	var counts: Dictionary = progression.repeatable_completion_counts
	for contract_id in counts:
		counts[contract_id] = int(counts[contract_id])


static func _is_valid_partitioned_inventory(value: Variant) -> bool:
	if not value is Dictionary or not ProfileRules.has_exact_keys(value, ["equipment", "proxy_components", "legacy_drops"]):
		return false
	for field in ["equipment", "proxy_components", "legacy_drops"]:
		if not (value as Dictionary).get(field, null) is Array:
			return false
	var seen := {}
	for item in ((value as Dictionary).equipment as Array):
		if not ProfileRules.is_valid_item_instance(item):
			return false
		var instance_id := String((item as Dictionary).instance_id)
		if seen.has(instance_id):
			return false
		seen[instance_id] = true
	var proxy_seen := {}
	for component in ((value as Dictionary).proxy_components as Array):
		if not ProxyBuilds.is_proxy_component(component):
			return false
		var component_id := String((component as Dictionary).id)
		if proxy_seen.has(component_id):
			return false
		proxy_seen[component_id] = true
	return true
