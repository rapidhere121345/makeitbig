extends RefCounted

## Proxy (Auto-mode) build authority extracted from ApplicationState: the
## persisted proxy_build shape, core equip/configure transactions, the owned
## proxy-core inventory and the first-kill / Auto reward grants. Static; the
## live profile dictionary is passed in and mutated in place.
const ProxyBuildScript = preload("res://src/systems/proxy_build.gd")
const CoreResult := preload("res://src/core/result.gd")
const ProfileRules := preload("res://src/game/application/profile_rules.gd")

const INITIAL_PROXY_CORE_IDS := ["near_enemy_horizon", "direct_gait", "single_key_execution", "short_trace_memory"]
const AUTO_PROXY_REWARD_IDS := ["marking_prism", "distance_keeping_gait"]
const PROXY_CORE_CATALOG_IDS := [
	"near_enemy_horizon", "marking_prism", "direct_gait", "distance_keeping_gait",
	"single_key_execution", "short_trace_memory",
]


static func resolved_snapshot(profile: Dictionary) -> Dictionary:
	if profile.is_empty():
		return CoreResult.failure("profile_required")
	var registry: Variant = ProfileRules.loaded_content_registry()
	if registry == null:
		return CoreResult.failure("content_unavailable")
	var raw_result := raw_snapshot(profile)
	if not bool(raw_result.get("ok", false)):
		return CoreResult.failure("invalid_proxy_build")
	var raw_build: Dictionary = raw_result.value
	var compiled: Dictionary = ProxyBuildScript.compile(compile_input(raw_build), registry.cores)
	if not bool(compiled.get("ok", false)):
		return CoreResult.failure("proxy_build_%s" % String(compiled.get("error", "invalid")))
	return {
		"ok": true,
		"proxy_build": raw_build.duplicate(true),
		"resolved_proxy_build": (compiled.value as Dictionary).duplicate(true),
	}.duplicate(true)


static func equip_core(profile: Dictionary, core_id: String) -> Dictionary:
	if profile.is_empty():
		return CoreResult.failure("profile_required")
	if not bool((profile.progression as Dictionary).get("proxy_unlocked", false)):
		return CoreResult.failure("proxy_locked")
	var normalized_id := core_id.strip_edges()
	if normalized_id.is_empty():
		return CoreResult.failure("invalid_core_id")
	var registry: Variant = ProfileRules.loaded_content_registry()
	if registry == null:
		return CoreResult.failure("content_unavailable")
	if normalized_id not in PROXY_CORE_CATALOG_IDS or not registry.cores.has(normalized_id):
		return CoreResult.failure("unsupported_proxy_core")
	if not owns_core(profile, normalized_id):
		return CoreResult.failure("proxy_core_not_owned")
	var raw_result := raw_snapshot(profile)
	if not bool(raw_result.get("ok", false)):
		return CoreResult.failure("invalid_proxy_build")
	var candidate: Dictionary = raw_result.value
	var core: Dictionary = registry.cores[normalized_id]
	var slot_index := ProxyBuildScript.SLOT_ORDER.find(String(core.slot))
	if slot_index < 0:
		return CoreResult.failure("unsupported_proxy_core")
	(candidate.cores as Array)[slot_index] = normalized_id
	var retained_settings := {}
	for selected_id_value in (candidate.cores as Array):
		var selected_id := String(selected_id_value)
		if (candidate.settings as Dictionary).has(selected_id):
			retained_settings[selected_id] = (candidate.settings as Dictionary)[selected_id].duplicate(true) if (candidate.settings as Dictionary)[selected_id] is Dictionary else (candidate.settings as Dictionary)[selected_id]
	candidate["settings"] = retained_settings
	return commit_candidate(profile, candidate, registry.cores)


static func configure_core(profile: Dictionary, core_id: String, settings: Dictionary) -> Dictionary:
	if profile.is_empty():
		return CoreResult.failure("profile_required")
	var normalized_id := core_id.strip_edges()
	var raw_result := raw_snapshot(profile)
	if not bool(raw_result.get("ok", false)):
		return CoreResult.failure("invalid_proxy_build")
	var candidate: Dictionary = raw_result.value
	if normalized_id.is_empty() or normalized_id not in (candidate.cores as Array):
		return CoreResult.failure("proxy_core_not_equipped")
	var registry: Variant = ProfileRules.loaded_content_registry()
	if registry == null:
		return CoreResult.failure("content_unavailable")
	(candidate.settings as Dictionary)[normalized_id] = settings.duplicate(true)
	return commit_candidate(profile, candidate, registry.cores)


static func raw_snapshot(profile: Dictionary) -> Dictionary:
	var stored_value: Variant = profile.get("proxy_build", null)
	if not stored_value is Dictionary:
		return CoreResult.failure("invalid_proxy_build")
	var stored: Dictionary = stored_value
	if not ProfileRules.has_exact_keys(stored, ["cores", "settings", "attachments"]):
		return CoreResult.failure("invalid_proxy_build")
	if not stored.cores is Array or (stored.cores as Array).size() != ProxyBuildScript.SLOT_ORDER.size():
		return CoreResult.failure("invalid_proxy_build")
	if not stored.settings is Dictionary:
		return CoreResult.failure("invalid_proxy_build")
	if not stored.attachments is Array or (stored.attachments as Array).size() != 3:
		return CoreResult.failure("invalid_proxy_build")
	for core_id in (stored.cores as Array):
		if not ProfileRules.is_text(core_id):
			return CoreResult.failure("invalid_proxy_build")
	for attachment_id in (stored.attachments as Array):
		if not ProfileRules.is_text(attachment_id) or not String(attachment_id).is_empty():
			return CoreResult.failure("invalid_proxy_build")
	return {"ok": true, "value": stored.duplicate(true)}


static func compile_input(raw_build: Dictionary) -> Dictionary:
	return {
		"cores": (raw_build.cores as Array).duplicate(),
		"settings": (raw_build.settings as Dictionary).duplicate(true),
	}


static func commit_candidate(profile: Dictionary, candidate: Dictionary, core_catalog: Dictionary) -> Dictionary:
	var compiled: Dictionary = ProxyBuildScript.compile(compile_input(candidate), core_catalog)
	if not bool(compiled.get("ok", false)):
		return CoreResult.failure("proxy_build_%s" % String(compiled.get("error", "invalid")))
	profile["proxy_build"] = candidate.duplicate(true)
	return {
		"ok": true,
		"proxy_build": candidate.duplicate(true),
		"resolved_proxy_build": (compiled.value as Dictionary).duplicate(true),
	}.duplicate(true)


static func owns_core(profile: Dictionary, core_id: String) -> bool:
	for component in ((profile.inventory as Dictionary).proxy_components as Array):
		if component is Dictionary and String((component as Dictionary).get("id", "")) == core_id:
			return true
	return false


static func catalog_snapshot(core_catalog: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for core_id in PROXY_CORE_CATALOG_IDS:
		if not core_catalog.has(core_id) or not core_catalog[core_id] is Dictionary:
			continue
		var core: Dictionary = core_catalog[core_id]
		result[core_id] = {
			"id": String(core.id),
			"name": String(core.name),
			"slot": String(core.slot),
			"protocol": String(core.protocol),
			"settings_schema": (core.get("settings_schema", {}) as Dictionary).duplicate(true) if core.get("settings_schema", null) is Dictionary else {},
			"default_settings": (core.get("default_settings", {}) as Dictionary).duplicate(true) if core.get("default_settings", null) is Dictionary else {},
		}
	return result


static func is_proxy_component(value: Variant) -> bool:
	if not value is Dictionary or not ProfileRules.has_exact_keys(value as Dictionary, ["id", "name", "slot", "rarity", "type", "protocol", "source_contract"]):
		return false
	var component: Dictionary = value
	var registry: Variant = ProfileRules.loaded_content_registry()
	var id := String(component.get("id", ""))
	if registry == null or not registry.cores.has(id) or not registry.cores[id] is Dictionary:
		return false
	var core: Dictionary = registry.cores[id]
	return id in PROXY_CORE_CATALOG_IDS \
		and component.get("type", null) == "proxy_core" \
		and component.get("rarity", null) == "white" \
		and component.get("name", null) == core.get("name", null) \
		and component.get("slot", null) == core.get("slot", null) \
		and component.get("protocol", null) == core.get("protocol", null) \
		and ProfileRules.is_text(component.get("source_contract", null)) \
		and not String(component.source_contract).strip_edges().is_empty()


static func grant_initial(profile: Dictionary, source_contract: String) -> Array:
	(profile.proxy_build as Dictionary)["cores"] = INITIAL_PROXY_CORE_IDS.duplicate()
	(profile.proxy_build as Dictionary)["settings"] = {}
	var granted: Array = []
	for core_id in INITIAL_PROXY_CORE_IDS:
		var item := grant_core(profile, core_id, source_contract)
		if not item.is_empty():
			granted.append(item)
	return granted


static func grant_core(profile: Dictionary, core_id: String, source_contract: String) -> Dictionary:
	if owns_core(profile, core_id):
		return {}
	var item := component_item(core_id, source_contract)
	if item.is_empty():
		return {}
	((profile.inventory as Dictionary).proxy_components as Array).append(item.duplicate(true))
	return item


static func component_item(core_id: String, source_contract: String) -> Dictionary:
	var registry: Variant = ProfileRules.loaded_content_registry()
	if registry == null or core_id not in PROXY_CORE_CATALOG_IDS or not registry.cores.has(core_id):
		return {}
	var core: Dictionary = registry.cores[core_id]
	return {
		"id": core_id,
		"name": String(core.name),
		"slot": String(core.slot),
		"rarity": "white",
		"type": "proxy_core",
		"protocol": String(core.protocol),
		"source_contract": source_contract,
	}
