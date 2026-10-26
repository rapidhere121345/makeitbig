class_name ApplicationState
extends RefCounted

const StoryProgressionScript = preload("res://src/systems/story_progression.gd")
const TalentBuildScript = preload("res://src/systems/talent_build.gd")
const TalentRegistryScript = preload("res://src/content/talent_registry.gd")
const CharacterProgressionScript = preload("res://src/systems/character_progression.gd")
const LawForgeScript = preload("res://src/systems/law_forge.gd")
const ContentRegistryScript = preload("res://src/content/content_registry.gd")
const EarlyCampaignRegistryScript = preload("res://src/content/early_campaign_registry.gd")
const EarlyInterfaceVocabularyScript = preload("res://src/content/early_interface_vocabulary.gd")
const EarlyItemRegistryScript = preload("res://src/content/early_item_registry.gd")
const BuildResolverScript = preload("res://src/systems/build_resolver.gd")
const TrainingReportBuilderScript = preload("res://src/systems/training_report_builder.gd")
const ProxyBuildScript = preload("res://src/systems/proxy_build.gd")
const EquipmentDropGeneratorScript = preload("res://src/systems/equipment_drop_generator.gd")
const CoreResult := preload("res://src/core/result.gd")
const Collections := preload("res://src/core/collections.gd")

const SCHEMA_VERSION := 10
const PROFILE_SCHEMA_VERSION := SCHEMA_VERSION
const SUPPORTED_CLASSES := ["ranger", "alchemist", "mage"]
const SUPPORTED_MODES := ["Manual", "Auto"]
const SAFE_ROUTES := ["title", "tutorial", "base"]
const MAX_SAFE_JSON_INTEGER := 9007199254740991
const ROOM_EQUIPMENT_DROP_INDEX := 0
const SALVAGE_REFUND_TALLIES := 1
const FORGE_OPERATIONS := ["inscribe", "rewrite", "refine"]
const DEFAULT_RANGER_PRESET := "fixed_start"
const LEGACY_RANGER_PRESET := "exponential"
const BOSS_DIAGNOSIS_CONTRACT_ID := "threshold_colossus"
const BOSS_DIAGNOSIS_MODE := "Manual"
const BOSS_DIAGNOSIS_RANGE_MIN := 120.0
const BOSS_DIAGNOSIS_LIFETIME_MIN := 24.0
const PITY_SIDE_CONTRACT_ID := "side_affix_and_law_tallies"
const PITY_TRIGGER_PERIOD := 3
const PITY_EXPONENTIAL_P_THRESHOLD := 0.5
const PITY_TARGET_GROWTH := "piercing_continuation"
const PITY_TARGET_RANGE := "seeking_distance"
const PITY_TARGET_LIFETIME := "projectile_lifetime"
const PITY_TARGET_POWER := "carrier_power"
const BOSS_BOTTLENECK_GROWTH_CONVERGENT := {
	"id": "growth_convergent",
	"title": "Growth converged; the piercing chain could not grow",
	"action": "Find growth-chance affixes in targeted side contracts, then return with a growing piercing chain",
	"destination": "mainline_05_growth_gate",
}
const BOSS_BOTTLENECK_GROWTH_CRITICAL := {
	"id": "growth_critical",
	"title": "Growth stalled at critical; the piercing chain cannot expand",
	"action": "Find growth-chance affixes in targeted side contracts, then return after surpassing critical growth",
	"destination": "mainline_05_growth_gate",
}
const BOSS_BOTTLENECK_TARGETING_RANGE_SHORT := {
	"id": "targeting_range_short",
	"title": "Targeting range is too short to attack safely",
	"action": "Find targeting-range affixes in targeted side contracts, then return with a safer attack range",
	"destination": "mainline_05_growth_gate",
}
const BOSS_BOTTLENECK_PROJECTILE_LIFETIME_SHORT := {
	"id": "projectile_lifetime_short",
	"title": "Arrow lifetime is too short; the chain ends early",
	"action": "Strengthen shared-lifetime affixes at the Forge, then return with longer-lived arrows",
	"destination": "forge",
}
const BOSS_BOTTLENECK_BOSS_PATTERN_SURVIVAL := {
	"id": "boss_pattern_survival",
	"title": "Boss attacks need more practice",
	"action": "Check your loop in Training and practice avoiding the boss's second-phase attacks before retrying",
	"destination": "training",
}
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
const INITIAL_PROXY_CORE_IDS := ["near_enemy_horizon", "direct_gait", "single_key_execution", "short_trace_memory"]
const AUTO_PROXY_REWARD_IDS := ["marking_prism", "distance_keeping_gait"]
const PROXY_CORE_CATALOG_IDS := [
	"near_enemy_horizon", "marking_prism", "direct_gait", "distance_keeping_gait",
	"single_key_execution", "short_trace_memory",
]
const STABLE_FIRST_REWARD_ITEMS := {
	"breeding_split_item": "reward_mainline_03_breeding_split_gloves",
	"pack_hunt_mark_item": "reward_mainline_05_pack_hunt_mark_ring",
}

var _profile: Dictionary = {}
var _pending_contract: Dictionary = {}
var _active_session: Dictionary = {}
var _last_result: Dictionary = {}
var _forge_context: Dictionary = {}
var _forge_session: Dictionary = {}
var _pending_forge_commit: Dictionary = {}
var _forge_session_serial := 0

var profile: Dictionary:
	get:
		return _profile.duplicate(true)

var pending_contract: Dictionary:
	get:
		return _pending_contract.duplicate(true)

var active_session: Dictionary:
	get:
		return _active_session.duplicate(true)

var last_result: Dictionary:
	get:
		return _last_result.duplicate(true)


func reset() -> void:
	_profile.clear()
	_pending_contract.clear()
	_active_session.clear()
	_last_result.clear()
	_forge_context.clear()
	_forge_session.clear()
	_pending_forge_commit.clear()


func has_profile() -> bool:
	return not _profile.is_empty()


func start_new_profile(initial_class: String = "ranger") -> Dictionary:
	var normalized_class := initial_class.strip_edges().to_lower()
	if normalized_class not in SUPPORTED_CLASSES:
		return CoreResult.failure("invalid_class")
	var initial := _fixture_state(DEFAULT_RANGER_PRESET)
	if initial.is_empty():
		return CoreResult.failure("content_unavailable")
	_profile = {
		"schema_version": PROFILE_SCHEMA_VERSION,
		"profile_id": "local",
		"initial_class": normalized_class,
		"tutorial_complete": false,
		"character": {"experience": 0},
		"talents": {"allocated_ids": [], "stance": "mid"},
		"story": {"schema_version":1,"read_entry_ids":[]},
		"unlocked_classes": [normalized_class],
		"resources": {"law_tallies": {"inscribe": 0, "rewrite": 0, "refine": 0}},
		"inventory": {
			"equipment": initial.equipment,
			"proxy_components": [],
			"legacy_drops": [],
		},
		"build_presets": [{"id": "starter", "name": "Starter Pair"}],
		"active_build": initial.active_build,
		"proxy_build": {
			"cores": ["", "", "", ""],
			"settings": {},
			"attachments": ["", "", ""],
		},
		"training": {"reports_by_fingerprint": {}},
		"discoveries": [],
		"immortality": {"unlocked": false, "proofs": []},
		"progression": {
			"contract_wins": 0,
			"ending_unlocked": false,
			"completed_node_ids": [],
			"repeatable_completion_counts": {},
			"threshold_colossus_defeated": false,
			"proxy_unlocked": false,
			"auto_contract_wins": 0,
			"early_game_complete": false,
		},
	}
	_pending_contract.clear()
	_active_session.clear()
	_last_result.clear()
	_forge_context.clear()
	_forge_session.clear()
	_pending_forge_commit.clear()
	return {"ok": true, "profile": _profile.duplicate(true)}


func complete_tutorial() -> Dictionary:
	if not has_profile():
		return CoreResult.failure("profile_required")
	var first := not bool(_profile.get("tutorial_complete", false))
	_profile["tutorial_complete"] = true
	_record_completed_campaign_node("tutorial_ranger_basics")
	if first:
		_apply_experience(int(CharacterProgressionScript.rules().tutorial_experience))
	return {"ok": true, "profile": _profile.duplicate(true)}


func character_snapshot() -> Dictionary:
	if not has_profile(): return {}
	var reading := CharacterProgressionScript.snapshot(_profile.character)
	reading["points_spent"] = (_profile.talents.allocated_ids as Array).size()
	reading["points_available"] = int(reading.points_earned) - int(reading.points_spent)
	reading["locked"] = not _active_session.is_empty() or not _pending_contract.is_empty()
	reading["stance"] = _profile.talents.stance
	reading["unlocked_classes"] = (_profile.unlocked_classes as Array).duplicate()
	return reading


func _talent_context(source: Dictionary) -> Dictionary:
	return {"talents": (source.get("talents", {"allocated_ids":[],"stance":"mid"}) as Dictionary).duplicate(true), "talent_points": int(CharacterProgressionScript.snapshot(source.get("character", {})).points_earned), "unlocked_classes": source.get("unlocked_classes", ["ranger"])}


func growth_snapshot() -> Dictionary:
	var reading := character_snapshot()
	if reading.is_empty(): return {}
	var compiler := TalentBuildScript.new()
	var context := _talent_context(_profile)
	var raw: Dictionary = _profile.talents
	var trees: Array = []
	for tree_value in compiler.registry.catalog().trees:
		var tree: Dictionary = tree_value
		var nodes: Array = []
		for node_value in tree.nodes:
			var node: Dictionary = node_value
			var id := String(node.id)
			var selected: bool = id in raw.allocated_ids
			var candidate := raw.duplicate(true)
			if not selected: candidate.allocated_ids.append(id)
			var valid: Dictionary = compiler.validate(candidate, int(context.talent_points), context.unlocked_classes)
			var reason := ""
			if not bool(tree.implemented): reason = "This class will be available in a later update"
			elif bool(reading.locked): reason = "Talents are locked during contracts"
			elif not bool(node.get("implemented",true)): reason = "This node will unlock when its mechanic is implemented"
			elif not selected and int(reading.points_available) <= 0: reason = "More talent points required"
			elif not valid.ok: reason = "Meet tier investment requirements and the two-keystone limit"
			nodes.append({"id":id,"name":String(node.name),"tier":int(node.layer),"keystone":bool(node.is_key),"description":String(node.get("description",node.get("pending_reason","Description pending"))),"allocated":selected,"can_allocate":not selected and reason.is_empty(),"lock_reason":reason})
		trees.append({"id":String(tree.class_id),"name":String(tree.name),"available":bool(tree.implemented) and String(tree.class_id) in context.unlocked_classes,"nodes":nodes})
	reading["trees"] = trees
	reading["stance_available"] = "ranger_near_far_hunting" in raw.allocated_ids
	return reading


func change_talent(action: String, value: String = "") -> Dictionary:
	if not has_profile(): return CoreResult.failure("profile_required")
	if not _active_session.is_empty() or not _pending_contract.is_empty(): return CoreResult.failure("talents_locked")
	var candidate: Dictionary = _profile.talents.duplicate(true)
	match action:
		"allocate":
			if value in candidate.allocated_ids: return CoreResult.failure("talent_already_allocated")
			candidate.allocated_ids.append(value)
		"refund":
			if value not in candidate.allocated_ids: return CoreResult.failure("talent_not_allocated")
			candidate.allocated_ids.erase(value)
		"reset": candidate = {"allocated_ids":[],"stance":"mid"}
		"stance": candidate.stance = value
		_: return CoreResult.failure("unknown_talent_action")
	var compiler := TalentBuildScript.new()
	var validated := compiler.validate(candidate, int(character_snapshot().points_earned), _profile.unlocked_classes)
	if not validated.ok: return {"ok":false,"error":"invalid_talent_allocation","details":validated.errors}
	_profile["talents"] = validated.talents.duplicate(true)
	return {"ok":true,"snapshot":growth_snapshot()}



func story_progress_snapshot() -> Dictionary:
	return _story_progress_for(_profile)


func _story_progress_for(source: Dictionary) -> Dictionary:
	var snapshot := (source.get("progression", {}) as Dictionary).duplicate(true)
	var records: Variant = source.get("discoveries", [])
	if records is Array:
		for record in records:
			if not record is Dictionary: continue
			if String(record.get("id", "")) == "first_equipment_find": snapshot["equipment_discovered"] = true
			if String(record.get("kind", "")) == "growth_state":
				snapshot["growth_observed"] = true
				if not snapshot.has("first_growth_state"): snapshot["first_growth_state"] = String(record.get("state", ""))
				if String(record.get("state", "")) == "exponential": snapshot["exponential_observed"] = true
	return snapshot


func story_snapshot() -> Dictionary:
	if not has_profile(): return {}
	return StoryProgressionScript.new().evaluate(story_progress_snapshot(), _profile.story)


func mark_story_read(entry_id: String) -> Dictionary:
	if not has_profile(): return CoreResult.failure("profile_required")
	if not _active_session.is_empty(): return CoreResult.failure("story_locked")
	var available := false
	var story_state := story_snapshot()
	for entry in story_state.get("journal_entries",[]) + story_state.get("available_conversations",[]):
		if String(entry.id) == entry_id: available = true
	if not available: return CoreResult.failure("story_entry_unavailable")
	_profile.story = StoryProgressionScript.new().mark_entry_read(story_progress_snapshot(), _profile.story, entry_id)
	return {"ok":true}


func _valid_story(source: Dictionary) -> bool:
	var story: Variant = source.get("story")
	if not source.get("progression") is Dictionary: return false
	if not story is Dictionary or not _has_exact_keys(story,["schema_version","read_entry_ids"]): return false
	if not _is_exact_integer(story.schema_version) or int(story.schema_version) != 1 or not story.read_entry_ids is Array: return false
	var available: Dictionary = {}
	var story_state := StoryProgressionScript.new().evaluate(_story_progress_for(source), {})
	for entry in story_state.get("journal_entries",[]) + story_state.get("available_conversations",[]):
		available[String(entry.id)] = true
	var seen := {}
	for value in story.read_entry_ids:
		if not _is_text(value) or not available.has(String(value)) or seen.has(String(value)): return false
		seen[String(value)] = true
	return true



func _apply_experience(amount: int) -> Dictionary:
	var change := CharacterProgressionScript.award(_profile.character, amount)
	_profile["character"] = (change.character as Dictionary).duplicate(true)
	return change



func select_ranger_build(preset_id: String) -> Dictionary:
	if not has_profile():
		return CoreResult.failure("profile_required")
	var fixture_id := _fixture_id_for_legacy_name(preset_id)
	if fixture_id.is_empty() or fixture_id == "fixed_start":
		return CoreResult.failure("unknown_preset")
	var selected := _fixture_state(fixture_id)
	if selected.is_empty():
		return CoreResult.failure("content_unavailable")
	_merge_equipment_inventory(selected.equipment)
	_profile["active_build"] = selected.active_build
	return active_build_snapshot()


func active_build_snapshot() -> Dictionary:
	if not has_profile():
		return CoreResult.failure("profile_required")
	var snapshot: Dictionary = (_profile.active_build as Dictionary).duplicate(true)
	var preset_id := _legacy_preset_for_active_build(snapshot)
	snapshot["preset_id"] = preset_id
	if preset_id in ["convergent", "critical", "exponential"]:
		var legacy := _legacy_build_from_preset(preset_id)
		if not legacy.is_empty():
			snapshot["equipment"] = legacy.equipment
	var resolved := _resolve_active_build(snapshot)
	if bool(resolved.get("ok", false)):
		snapshot["runes"] = (resolved.rune_ids as Array).duplicate()
		snapshot["laws"] = (resolved.law_ids as Array).duplicate()
	return {"ok": true, "active_build": snapshot}


func resolved_build_snapshot() -> Dictionary:
	if not has_profile():
		return CoreResult.failure("profile_required")
	return _resolve_active_build((_profile.active_build as Dictionary).duplicate(true))


func resolved_proxy_build_snapshot() -> Dictionary:
	if not has_profile():
		return CoreResult.failure("profile_required")
	var registry: Variant = _loaded_content_registry()
	if registry == null:
		return CoreResult.failure("content_unavailable")
	var raw_result := _raw_proxy_build_snapshot()
	if not bool(raw_result.get("ok", false)):
		return CoreResult.failure("invalid_proxy_build")
	var raw_build: Dictionary = raw_result.value
	var compiled: Dictionary = ProxyBuildScript.compile(_proxy_compile_input(raw_build), registry.cores)
	if not bool(compiled.get("ok", false)):
		return CoreResult.failure("proxy_build_%s" % String(compiled.get("error", "invalid")))
	return {
		"ok": true,
		"proxy_build": raw_build.duplicate(true),
		"resolved_proxy_build": (compiled.value as Dictionary).duplicate(true),
	}.duplicate(true)


func equip_proxy_core(core_id: String) -> Dictionary:
	if not has_profile():
		return CoreResult.failure("profile_required")
	if not bool((_profile.progression as Dictionary).get("proxy_unlocked", false)):
		return CoreResult.failure("proxy_locked")
	var normalized_id := core_id.strip_edges()
	if normalized_id.is_empty():
		return CoreResult.failure("invalid_core_id")
	var registry: Variant = _loaded_content_registry()
	if registry == null:
		return CoreResult.failure("content_unavailable")
	if normalized_id not in PROXY_CORE_CATALOG_IDS or not registry.cores.has(normalized_id):
		return CoreResult.failure("unsupported_proxy_core")
	if not _owns_proxy_core(normalized_id):
		return CoreResult.failure("proxy_core_not_owned")
	var raw_result := _raw_proxy_build_snapshot()
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
	return _commit_proxy_build_candidate(candidate, registry.cores)


func configure_proxy_core(core_id: String, settings: Dictionary) -> Dictionary:
	if not has_profile():
		return CoreResult.failure("profile_required")
	var normalized_id := core_id.strip_edges()
	var raw_result := _raw_proxy_build_snapshot()
	if not bool(raw_result.get("ok", false)):
		return CoreResult.failure("invalid_proxy_build")
	var candidate: Dictionary = raw_result.value
	if normalized_id.is_empty() or normalized_id not in (candidate.cores as Array):
		return CoreResult.failure("proxy_core_not_equipped")
	var registry: Variant = _loaded_content_registry()
	if registry == null:
		return CoreResult.failure("content_unavailable")
	(candidate.settings as Dictionary)[normalized_id] = settings.duplicate(true)
	return _commit_proxy_build_candidate(candidate, registry.cores)


func equip_item(instance_id: String) -> Dictionary:
	if not has_profile():
		return CoreResult.failure("profile_required")
	var normalized_id := instance_id.strip_edges()
	if normalized_id.is_empty():
		return CoreResult.failure("invalid_instance_id")
	var item := _owned_equipment(normalized_id)
	if item.is_empty():
		return CoreResult.failure("item_not_owned")
	var registry: Variant = _loaded_item_registry()
	if registry == null or not registry.validate_item_instance(item).is_empty():
		return CoreResult.failure("invalid_item_instance")
	var slot := String(item.slot)
	if slot not in EarlyItemRegistryScript.PROTOTYPE_OPEN_SLOTS:
		return CoreResult.failure("slot_not_prototype_open")
	var active: Dictionary = (_profile.active_build as Dictionary).duplicate(true)
	var equipped: Dictionary = active.equipped_item_ids
	for equipped_slot in EarlyItemRegistryScript.EQUIPMENT_SLOTS:
		if String(equipped.get(equipped_slot, "")) == normalized_id:
			return CoreResult.failure("item_already_equipped")
	equipped[slot] = normalized_id
	var resolved := _resolve_active_build(active)
	if not bool(resolved.get("ok", false)):
		return CoreResult.failure("build_resolution_failed")
	_profile["active_build"] = active
	return {"ok": true, "active_build": active.duplicate(true), "resolved_build": resolved.duplicate(true)}


## Read-only "try-on" preview for FacilityScreen's equip_previews contract.
## Validation order mirrors equip_item exactly. Nothing is persisted: the preview
## resolves a deep copy of active_build with the target slot replaced, through the
## single authoritative path _resolve_active_build. Deltas are computed against the
## current authoritative resolution; tags stay empty because the resolved Build
## exposes no authoritative tag set (never inferred from item affixes).
func preview_equip_item(instance_id: String) -> Dictionary:
	if not has_profile():
		return CoreResult.failure("profile_required")
	var normalized_id := instance_id.strip_edges()
	if normalized_id.is_empty():
		return CoreResult.failure("invalid_instance_id")
	var item := _owned_equipment(normalized_id)
	if item.is_empty():
		return CoreResult.failure("item_not_owned")
	var registry: Variant = _loaded_item_registry()
	if registry == null or not registry.validate_item_instance(item).is_empty():
		return CoreResult.failure("invalid_item_instance")
	var slot := String(item.slot)
	if slot not in EarlyItemRegistryScript.PROTOTYPE_OPEN_SLOTS:
		return CoreResult.failure("slot_not_prototype_open")
	var active: Dictionary = (_profile.active_build as Dictionary).duplicate(true)
	var equipped: Dictionary = active.equipped_item_ids
	for equipped_slot in EarlyItemRegistryScript.EQUIPMENT_SLOTS:
		if String(equipped.get(equipped_slot, "")) == normalized_id:
			return CoreResult.failure("item_already_equipped")
	var current_resolved := _resolve_active_build(active)
	if not bool(current_resolved.get("ok", false)):
		return CoreResult.failure("build_resolution_failed")
	equipped[slot] = normalized_id
	var next_resolved := _resolve_active_build(active)
	if not bool(next_resolved.get("ok", false)):
		return CoreResult.failure("build_resolution_failed")
	var current_connected := _resolved_connected_interfaces(current_resolved)
	var next_connected := _resolved_connected_interfaces(next_resolved)
	var current_tags := _resolved_tag_ids(current_resolved)
	var next_tags := _resolved_tag_ids(next_resolved)
	return {
		"ok": true,
		"instance_id": normalized_id,
		"slot": slot,
		"final_parameters": (next_resolved.final_parameters as Dictionary).duplicate(true),
		"growth_classification": String(next_resolved.growth_classification),
		"build_fingerprint": String(next_resolved.build_fingerprint),
		"interfaces_gained": Collections.string_array_difference(next_connected, current_connected),
		"interfaces_lost": Collections.string_array_difference(current_connected, next_connected),
		"tags_gained": Collections.string_array_difference(next_tags, current_tags),
		"tags_lost": Collections.string_array_difference(current_tags, next_tags),
		"current_resolved": current_resolved.duplicate(true),
		"resolved_build": next_resolved.duplicate(true),
	}


## Prototype equipment salvage truth chain.
## Every owned, registry-valid ItemInstance may be salvaged, including starting
## and calibration equipment. If the target is equipped, assessment first builds
## and resolves an unequipped active_build candidate. Commit publishes that valid
## build together with inventory removal, so no persisted slot can retain a
## dangling instance id. Preview and commit use the same assessment and the
## domain remains authoritative for the Law Tally refund.
func salvage_item_preview(instance_id: String) -> Dictionary:
	if not has_profile():
		return CoreResult.failure("profile_required")
	var normalized_id := instance_id.strip_edges()
	if normalized_id.is_empty():
		return CoreResult.failure("invalid_instance_id")
	var assessment := _salvage_assessment(normalized_id)
	if not bool(assessment.get("ok", false)):
		return assessment
	return {
		"ok": true,
		"instance_id": normalized_id,
		"operation": String(assessment.operation),
		"amount": SALVAGE_REFUND_TALLIES,
		"equipped_slot": String(assessment.get("equipped_slot", "")),
		"item": (assessment.item as Dictionary).duplicate(true),
	}


func salvage_item(instance_id: String) -> Dictionary:
	if not has_profile():
		return CoreResult.failure("profile_required")
	var normalized_id := instance_id.strip_edges()
	if normalized_id.is_empty():
		return CoreResult.failure("invalid_instance_id")
	var assessment := _salvage_assessment(normalized_id)
	if not bool(assessment.get("ok", false)):
		return assessment
	var equipment: Array = (_profile.inventory as Dictionary).equipment
	var inventory_index := -1
	for index in equipment.size():
		if equipment[index] is Dictionary and String((equipment[index] as Dictionary).get("instance_id", "")) == normalized_id:
			inventory_index = index
			break
	if inventory_index < 0:
		return CoreResult.failure("item_not_owned")
	var salvaged: Dictionary = (equipment[inventory_index] as Dictionary).duplicate(true)
	var next_active: Dictionary = (assessment.next_active_build as Dictionary).duplicate(true)
	equipment.remove_at(inventory_index)
	_profile["active_build"] = next_active
	var operation := String(assessment.operation)
	var tallies: Dictionary = (_profile.resources as Dictionary).law_tallies
	tallies[operation] = int(tallies.get(operation, 0)) + SALVAGE_REFUND_TALLIES
	_invalidate_forge_session()
	return {
		"ok": true,
		"instance_id": normalized_id,
		"operation": operation,
		"amount": SALVAGE_REFUND_TALLIES,
		"unequipped_slot": String(assessment.get("equipped_slot", "")),
		"active_build": next_active.duplicate(true),
		"salvaged_item": salvaged,
	}


## Shared read-only validation for preview and commit. Both surfaces must fail
## closed with the same codes and must never mutate profile state.
func _salvage_assessment(normalized_id: String) -> Dictionary:
	var item := _owned_equipment(normalized_id)
	if item.is_empty():
		return CoreResult.failure("item_not_owned")
	var registry: Variant = _loaded_item_registry()
	if registry == null or not registry.validate_item_instance(item).is_empty():
		return CoreResult.failure("invalid_item_instance")
	var active: Dictionary = (_profile.active_build as Dictionary).duplicate(true)
	var equipped: Dictionary = active.equipped_item_ids
	var equipped_slot := ""
	for loop_slot in EarlyItemRegistryScript.EQUIPMENT_SLOTS:
		if String(equipped.get(loop_slot, "")) == normalized_id:
			equipped_slot = String(loop_slot)
			break
	if not equipped_slot.is_empty():
		equipped[equipped_slot] = ""
		var resolved := _resolve_active_build(active)
		if not bool(resolved.get("ok", false)):
			return CoreResult.failure("build_resolution_failed")
	return {
		"ok": true,
		"item": item,
		"operation": _salvage_operation(item),
		"equipped_slot": equipped_slot,
		"next_active_build": active,
	}


## Deterministic cross-process refund track: stable item identity fields only.
## sha256(instance_id|law_seed) % 3 selects inscribe/rewrite/refine.
func _salvage_operation(item: Dictionary) -> String:
	var identity := "%s|%d" % [String(item.get("instance_id", "")), int(item.get("law_seed", 0))]
	var digest := identity.sha256_text()
	var bucket := int(("0x" + digest.substr(0, 8)).hex_to_int()) % FORGE_OPERATIONS.size()
	return FORGE_OPERATIONS[bucket]


func unequip_item(slot: String) -> Dictionary:
	if not has_profile():
		return CoreResult.failure("profile_required")
	var normalized_slot := slot.strip_edges().to_lower()
	if normalized_slot not in EarlyItemRegistryScript.PROTOTYPE_OPEN_SLOTS:
		return CoreResult.failure("slot_not_prototype_open")
	var active: Dictionary = (_profile.active_build as Dictionary).duplicate(true)
	(active.equipped_item_ids as Dictionary)[normalized_slot] = ""
	var resolved := _resolve_active_build(active)
	if not bool(resolved.get("ok", false)):
		return CoreResult.failure("build_resolution_failed")
	_profile["active_build"] = active
	return {"ok": true, "active_build": active.duplicate(true), "resolved_build": resolved.duplicate(true)}


func early_game_snapshot() -> Dictionary:
	if not has_profile():
		return CoreResult.failure("profile_required")
	var registry: Variant = _loaded_content_registry()
	var item_registry: Variant = _loaded_item_registry()
	if registry == null or item_registry == null:
		return CoreResult.failure("content_unavailable")
	var available: Array = []
	var selected_id := _legacy_preset_for_active_build(_profile.active_build)
	var reports_by_fingerprint: Dictionary = (_profile.training as Dictionary).reports_by_fingerprint
	for preset_index in registry.preset_order.size():
		var preset_id: String = registry.preset_order[preset_index]
		var preset: Dictionary = registry.presets[preset_id]
		var fixture_id := _fixture_id_for_legacy_name(preset_id)
		var fingerprint := _fingerprint_for_fixture(fixture_id)
		var resolved_fixture: Dictionary = BuildResolverScript.new(item_registry).resolve_fixture(fixture_id)
		var rune_view: Array = []
		var law_view: Array = []
		if bool(resolved_fixture.get("ok", false)):
			for rune_id in (resolved_fixture.get("rune_ids", []) as Array):
				if item_registry.runes.has(String(rune_id)):
					rune_view.append((item_registry.runes[String(rune_id)] as Dictionary).duplicate(true))
			for law_id in (resolved_fixture.get("law_ids", []) as Array):
				if item_registry.laws.has(String(law_id)):
					law_view.append((item_registry.laws[String(law_id)] as Dictionary).duplicate(true))
		var is_verified := not fingerprint.is_empty() and reports_by_fingerprint.has(fingerprint)
		var neutral_name := "Preset %s" % String.chr(65 + preset_index)
		available.append({
			"id": preset_id,
			"name": neutral_name,
			"neutral_name": neutral_name,
			"verified_growth_name": String(preset.name) if is_verified else "",
			"p": float(preset.p),
			"selected": preset_id == selected_id,
			"verified": is_verified,
			"skills": (preset.skills as Array).duplicate(true),
			"runes": rune_view,
			"laws": law_view,
			"equipment": (preset.equipment as Dictionary).duplicate(true),
		})
	var training_snapshot: Dictionary = (_profile.training as Dictionary).duplicate(true)
	var proxy_resolved := resolved_proxy_build_snapshot()
	return {
		"ok": true,
		"available_builds": available,
		"active_build": active_build_snapshot().active_build,
		"training": training_snapshot,
		"proxy": {
			"build": (_profile.proxy_build as Dictionary).duplicate(true),
			"unlocked": is_auto_mode_unlocked(),
			"inventory": ((_profile.inventory as Dictionary).proxy_components as Array).duplicate(true),
			"catalog": _proxy_catalog_snapshot(registry.cores),
			"resolved_build": (proxy_resolved.get("resolved_proxy_build", {}) as Dictionary).duplicate(true) if bool(proxy_resolved.get("ok", false)) else {},
		},
		"progression": (_profile.progression as Dictionary).duplicate(true),
	}.duplicate(true)


func campaign_progress_snapshot() -> Dictionary:
	if not has_profile():
		return CoreResult.failure("profile_required")
	var registry: Variant = _loaded_early_campaign_registry()
	if registry == null:
		return CoreResult.failure("content_unavailable")
	var completed: Array = ((_profile.progression as Dictionary).completed_node_ids as Array).duplicate()
	var completed_lookup := {}
	for node_id_value in completed:
		completed_lookup[String(node_id_value)] = true
	var available: Array = []
	var locked: Array = []
	var fixed_order: Array[String] = registry.mainline_order()
	var ordered_ids: Array = fixed_order.duplicate()
	ordered_ids.append_array(_repeatable_campaign_node_ids(registry))
	for node_id_value in ordered_ids:
		var node_id := String(node_id_value)
		var node: Dictionary = registry.get_node(node_id)
		if completed_lookup.has(node_id) and not bool(node.get("repeatable", false)):
			continue
		var unlocked := false
		for mode_value in (node.get("allowed_modes", []) as Array):
			if registry.is_unlocked(node_id, completed, String(mode_value)):
				unlocked = true
				break
		if unlocked:
			available.append(node_id)
		else:
			locked.append(node_id)
	var next_mainline_node_id := ""
	for node_id in fixed_order:
		if not completed_lookup.has(node_id):
			next_mainline_node_id = node_id
			break
	return {
		"ok": true,
		"completed_node_ids": completed,
		"earned_reward_tags": _earned_campaign_reward_tags(registry, completed),
		"available_node_ids": available,
		"locked_node_ids": locked,
		"next_mainline_node_id": next_mainline_node_id,
		"early_game_complete": bool((_profile.progression as Dictionary).early_game_complete),
	}.duplicate(true)


func run_training_trial() -> Dictionary:
	if not has_profile():
		return CoreResult.failure("profile_required")
	var resolved := resolved_build_snapshot()
	if not bool(resolved.get("ok", false)):
		return CoreResult.failure("invalid_active_build")
	var preset_id := _legacy_preset_for_active_build(_profile.active_build)
	var fingerprint := String(resolved.build_fingerprint)
	var report: Dictionary = TrainingReportBuilderScript.build_report(resolved, preset_id)
	var training: Dictionary = _profile.training
	var reports_by_fingerprint: Dictionary = training.reports_by_fingerprint
	reports_by_fingerprint[fingerprint] = report.duplicate(true)
	_record_growth_discovery(report)
	_refresh_early_game_completion()
	return {"ok": true, "report": report.duplicate(true)}


func is_auto_mode_unlocked() -> bool:
	return has_profile() and bool((_profile.progression as Dictionary).get("proxy_unlocked", false))


func forge_ensure_context() -> Dictionary:
	if not has_profile():
		return CoreResult.failure("profile_required")
	var registry: Variant = _loaded_item_registry()
	if registry == null:
		return CoreResult.failure("content_unavailable")
	var inventory_items: Array = []
	for raw_item in ((_profile.inventory as Dictionary).equipment as Array):
		if raw_item is Dictionary and registry.validate_item_instance(raw_item).is_empty():
			inventory_items.append(_forge_item_view(raw_item as Dictionary, registry))
	if inventory_items.is_empty():
		return CoreResult.failure("item_not_owned")
	var target_id := String(_forge_context.get("target_instance_id", "")).strip_edges()
	if target_id.is_empty() or _owned_equipment(target_id).is_empty():
		target_id = _default_forge_target_id(inventory_items)
	var operation := String(_forge_context.get("operation", "inscribe"))
	if operation not in FORGE_OPERATIONS:
		operation = "inscribe"
	return _set_forge_context(target_id, operation)


func forge_select_target(instance_id: String, expected_revision: int = -1) -> Dictionary:
	if not has_profile():
		return CoreResult.failure("profile_required")
	var target_id := instance_id.strip_edges()
	if target_id.is_empty():
		return CoreResult.failure("invalid_instance_id")
	var item := _owned_equipment(target_id)
	if item.is_empty():
		return CoreResult.failure("item_not_owned")
	var registry: Variant = _loaded_item_registry()
	if registry == null:
		return CoreResult.failure("content_unavailable")
	if not registry.validate_item_instance(item).is_empty():
		return CoreResult.failure("invalid_item")
	var ensured := forge_ensure_context()
	if not bool(ensured.get("ok", false)):
		return ensured
	if expected_revision >= 0 and expected_revision != int(_forge_context.revision):
		return CoreResult.failure("stale_forge_context")
	return _set_forge_context(target_id, String(_forge_context.operation))


func forge_select_operation(operation: String, expected_revision: int = -1) -> Dictionary:
	if operation not in FORGE_OPERATIONS:
		return CoreResult.failure("unknown_operation")
	var ensured := forge_ensure_context()
	if not bool(ensured.get("ok", false)):
		return ensured
	if expected_revision >= 0 and expected_revision != int(_forge_context.revision):
		return CoreResult.failure("stale_forge_context")
	return _set_forge_context(String(_forge_context.target_instance_id), operation)


func forge_snapshot() -> Dictionary:
	var ensured := forge_ensure_context()
	if not bool(ensured.get("ok", false)):
		return ensured
	var registry: Variant = _loaded_item_registry()
	if registry == null:
		return CoreResult.failure("content_unavailable")
	var inventory_items: Array = []
	for raw_item in ((_profile.inventory as Dictionary).equipment as Array):
		if raw_item is Dictionary and registry.validate_item_instance(raw_item).is_empty():
			inventory_items.append(_forge_item_view(raw_item as Dictionary, registry))
	var target_id := String(_forge_context.target_instance_id)
	var target := _owned_equipment(target_id)
	if target.is_empty():
		return CoreResult.failure("item_not_owned")
	if not registry.validate_item_instance(target).is_empty():
		return CoreResult.failure("invalid_item")
	return {
		"ok": true,
		"unlocked": _is_law_forge_unlocked(),
		"locked_reason": "Complete Main Quest 04 to unlock Law Token forging" if not _is_law_forge_unlocked() else "",
		"law_tallies": ((_profile.resources as Dictionary).law_tallies as Dictionary).duplicate(true),
		"affix_families": registry.affix_families.duplicate(true),
		"target_item": _forge_item_view(target, registry),
		"inventory_items": inventory_items.duplicate(true),
		"target_instance_id": target_id,
		"affixes": (target.affixes as Array).duplicate(true),
		"operation": String(_forge_context.operation),
		"blocked": bool(_forge_context.blocked),
		"blocked_reason": String(_forge_context.blocked_reason),
		"revision": int(_forge_context.revision),
		"context": _forge_context.duplicate(true),
		"session": _forge_session_view(),
	}.duplicate(true)


func forge_reveal(limit: int = 8, expected_revision: int = -1) -> Dictionary:
	if not has_profile():
		return CoreResult.failure("profile_required")
	if not _is_law_forge_unlocked():
		return CoreResult.failure("forge_locked")
	if limit < 1:
		return CoreResult.failure("invalid_page")
	var ensured := forge_ensure_context()
	if not bool(ensured.get("ok", false)):
		return ensured
	if expected_revision >= 0 and expected_revision != int(_forge_context.revision):
		return CoreResult.failure("stale_forge_context")
	if bool(_forge_context.get("blocked", false)):
		return CoreResult.failure(String(_forge_context.get("blocked_reason", "invalid_forge_context")))
	var target_id := String(_forge_context.target_instance_id)
	var operation := String(_forge_context.operation)
	var item := _owned_equipment(target_id)
	if item.is_empty():
		return CoreResult.failure("item_not_owned")
	var registry: Variant = _loaded_item_registry()
	if registry == null:
		return CoreResult.failure("content_unavailable")
	var balance := int(((_profile.resources as Dictionary).law_tallies as Dictionary).get(operation, 0))
	if balance <= 0:
		return CoreResult.failure("insufficient_law_tallies")
	_forge_session_serial += 1
	var session_id := "%s|%s|%d" % [target_id, operation, _forge_session_serial]
	session_id = session_id.sha256_text()
	var revealed: Dictionary = LawForgeScript.new(registry).reveal(item, operation, 0, mini(limit, balance), session_id)
	if not bool(revealed.get("ok", false)):
		_invalidate_forge_session()
		return revealed
	var enriched_candidates := _enrich_forge_candidates(item, (revealed.candidates as Array).duplicate(true), registry)
	_forge_session = {
		"state": "revealed",
		"session_id": session_id,
		"target_instance_id": target_id,
		"target_item": item.duplicate(true),
		"operation": operation,
		"context_revision": int(_forge_context.revision),
		"candidates": enriched_candidates,
		"unique_count": int(revealed.get("unique_count", enriched_candidates.size())),
		"selected_candidate_id": "",
		"has_more": enriched_candidates.size() < mini(balance, int(revealed.get("unique_count", enriched_candidates.size()))),
	}
	_pending_forge_commit.clear()
	return {"ok": true, "session": _forge_session_view()}


func forge_reveal_more(session_id: String, limit: int = 8) -> Dictionary:
	if _forge_session.is_empty():
		return CoreResult.failure("forge_session_required")
	if session_id.strip_edges().is_empty() or session_id != String(_forge_session.get("session_id", "")):
		return CoreResult.failure("stale_forge_session")
	if String(_forge_session.get("state", "")) == "prepared":
		return CoreResult.failure("commit_pending")
	if limit < 1:
		return CoreResult.failure("invalid_page")
	var current := _owned_equipment(String(_forge_session.target_instance_id))
	if current.is_empty() or current != _forge_session.target_item:
		_invalidate_forge_session()
		return CoreResult.failure("stale_target")
	var registry: Variant = _loaded_item_registry()
	if registry == null:
		return CoreResult.failure("content_unavailable")
	var offset := (_forge_session.candidates as Array).size()
	var operation := String(_forge_session.operation)
	var balance := int(((_profile.resources as Dictionary).law_tallies as Dictionary).get(operation, 0))
	var unique_count := int(_forge_session.get("unique_count", 0))
	var remaining := mini(balance, unique_count) - offset
	if remaining <= 0:
		_forge_session["has_more"] = false
		return {"ok": true, "session": _forge_session_view()}
	var revealed: Dictionary = LawForgeScript.new(registry).reveal(
		current, operation, offset, mini(limit, remaining), String(_forge_session.session_id)
	)
	if not bool(revealed.get("ok", false)):
		return revealed
	(_forge_session.candidates as Array).append_array(_enrich_forge_candidates(current, (revealed.candidates as Array).duplicate(true), registry))
	_forge_session["has_more"] = (_forge_session.candidates as Array).size() < mini(balance, unique_count)
	return {"ok": true, "session": _forge_session_view()}


func forge_select_candidate(session_id: String, candidate_id: String) -> Dictionary:
	if _forge_session.is_empty():
		return CoreResult.failure("forge_session_required")
	if session_id.strip_edges().is_empty() or session_id != String(_forge_session.get("session_id", "")):
		return CoreResult.failure("stale_forge_session")
	if String(_forge_session.get("state", "")) == "prepared":
		return CoreResult.failure("commit_pending")
	var normalized_id := candidate_id.strip_edges()
	for candidate_value in (_forge_session.candidates as Array):
		var candidate: Dictionary = candidate_value
		if String(candidate.candidate_id) == normalized_id:
			_forge_session["state"] = "selected"
			_forge_session["selected_candidate_id"] = normalized_id
			return {"ok": true, "session": _forge_session_view()}
	return CoreResult.failure("candidate_not_revealed")


func forge_cancel(session_id: String = "") -> Dictionary:
	if not session_id.strip_edges().is_empty() and ( _forge_session.is_empty() or session_id != String(_forge_session.get("session_id", "")) ):
		return CoreResult.failure("stale_forge_session")
	_pending_forge_commit.clear()
	_forge_session.clear()
	return {"ok": true, "session": _forge_session_view()}


func forge_prepare_commit(session_id: String) -> Dictionary:
	if _forge_session.is_empty() or String(_forge_session.get("state", "")) != "selected":
		return CoreResult.failure("candidate_not_selected")
	if session_id.strip_edges().is_empty() or session_id != String(_forge_session.get("session_id", "")):
		return CoreResult.failure("stale_forge_session")
	if not _pending_forge_commit.is_empty():
		return CoreResult.failure("commit_pending")
	var target_id := String(_forge_session.target_instance_id)
	var current := _owned_equipment(target_id)
	if current.is_empty() or current != _forge_session.target_item:
		_invalidate_forge_session()
		return CoreResult.failure("stale_target")
	var selected := _selected_forge_candidate()
	if selected.is_empty():
		return CoreResult.failure("candidate_not_selected")
	var registry: Variant = _loaded_item_registry()
	if registry == null:
		return CoreResult.failure("content_unavailable")
	var verified: Dictionary = LawForgeScript.new(registry).validate_candidate(
		current, String(_forge_session.operation), selected, String(_forge_session.session_id)
	)
	if not bool(verified.get("ok", false)):
		_invalidate_forge_session()
		return verified
	var operation := String(_forge_session.operation)
	var cost := int(selected.cost)
	var tallies: Dictionary = (_profile.resources as Dictionary).law_tallies
	if int(tallies.get(operation, 0)) < cost:
		return CoreResult.failure("insufficient_law_tallies")
	var next_profile := _profile.duplicate(true)
	var equipment: Array = (next_profile.inventory as Dictionary).equipment
	var inventory_index := _equipment_index(equipment, target_id)
	if inventory_index < 0:
		_invalidate_forge_session()
		return CoreResult.failure("stale_target")
	equipment[inventory_index] = (selected.result_item as Dictionary).duplicate(true)
	var next_tallies: Dictionary = (next_profile.resources as Dictionary).law_tallies
	next_tallies[operation] = int(next_tallies[operation]) - cost
	var commit_token := "%s|%s" % [String(_forge_session.session_id), String(selected.candidate_id)]
	commit_token = commit_token.sha256_text()
	_pending_forge_commit = {
		"commit_token": commit_token,
		"next_profile": next_profile,
		"candidate": selected.duplicate(true),
	}
	_forge_session["state"] = "prepared"
	return {
		"ok": true,
		"commit_token": commit_token,
		"operation": operation,
		"cost": cost,
		"candidate": selected.duplicate(true),
		"next_payload": _persistent_payload_for_profile(next_profile, "base"),
		"session": _forge_session_view(),
	}.duplicate(true)


func forge_finalize_commit(commit_token: String) -> Dictionary:
	if _pending_forge_commit.is_empty() or String(_pending_forge_commit.commit_token) != commit_token:
		return CoreResult.failure("invalid_commit_token")
	var candidate: Dictionary = (_pending_forge_commit.candidate as Dictionary).duplicate(true)
	_profile = (_pending_forge_commit.next_profile as Dictionary).duplicate(true)
	_pending_forge_commit.clear()
	_forge_session.clear()
	return {
		"ok": true,
		"operation": String(candidate.operation),
		"cost": int(candidate.cost),
		"candidate": candidate,
		"result_item": (candidate.result_item as Dictionary).duplicate(true),
		"remaining_law_tallies": int(((_profile.resources as Dictionary).law_tallies as Dictionary).get(String(candidate.operation), 0)),
	}.duplicate(true)


func forge_abort_commit(commit_token: String) -> Dictionary:
	if _pending_forge_commit.is_empty() or String(_pending_forge_commit.commit_token) != commit_token:
		return CoreResult.failure("invalid_commit_token")
	_pending_forge_commit.clear()
	_forge_session["state"] = "selected"
	return {"ok": true, "session": _forge_session_view()}


func prepare_contract(config: Dictionary) -> Dictionary:
	if not has_profile():
		return CoreResult.failure("profile_required")
	if not _active_session.is_empty():
		return CoreResult.failure("active_session_exists")
	var contract_id_value: Variant = config.get("contract_id", "")
	if not _is_text(contract_id_value):
		return CoreResult.failure("invalid_contract_id")
	var contract_id := String(contract_id_value).strip_edges()
	if contract_id.is_empty():
		return CoreResult.failure("invalid_contract_id")
	var mode_value: Variant = config.get("mode", "")
	if not _is_text(mode_value):
		return CoreResult.failure("invalid_mode")
	var mode := _normalize_mode(String(mode_value))
	if mode.is_empty():
		return CoreResult.failure("invalid_mode")
	var seed: Variant = config.get("seed", null)
	if typeof(seed) != TYPE_INT or int(seed) < -MAX_SAFE_JSON_INTEGER or int(seed) > MAX_SAFE_JSON_INTEGER:
		return CoreResult.failure("invalid_seed")
	var room_count: Variant = config.get("room_count", null)
	if typeof(room_count) != TYPE_INT or int(room_count) < 1:
		return CoreResult.failure("invalid_room_count")
	var normalized := config.duplicate(true)
	normalized["contract_id"] = contract_id
	normalized["mode"] = mode
	normalized["seed"] = int(seed)
	normalized["room_count"] = int(room_count)
	_pending_contract = normalized
	return {"ok": true, "contract": _pending_contract.duplicate(true)}


func begin_session() -> Dictionary:
	if not _active_session.is_empty():
		return CoreResult.failure("active_session_exists")
	if _pending_contract.is_empty():
		return CoreResult.failure("pending_contract_required")
	_active_session = _pending_contract.duplicate(true)
	_active_session["room_index"] = 0
	_active_session["ticks"] = 0
	_pending_contract.clear()
	return {"ok": true, "session": _active_session.duplicate(true)}


func commit_room_victory_and_resolve_next_build(room_index: int, room_result: Dictionary) -> Dictionary:
	if _active_session.is_empty():
		return CoreResult.failure("active_session_required")
	if int(room_index) != int(_active_session.get("room_index", -1)):
		return CoreResult.failure("room_index_mismatch")
	if String(room_result.get("outcome", "")).to_lower() != "victory":
		return CoreResult.failure("room_victory_required")
	var settlement_value: Variant = room_result.get("room_loot_settlement", {})
	if not settlement_value is Dictionary:
		return CoreResult.failure("invalid_room_loot_settlement")
	var settlement: Dictionary = settlement_value
	var items_value: Variant = settlement.get("items", [])
	if not settlement.is_empty():
		if not bool(settlement.get("ok", false)) or String(settlement.get("outcome", "")) != "victory":
			return CoreResult.failure("invalid_room_loot_settlement")
		if not items_value is Array:
			return CoreResult.failure("invalid_room_loot_settlement")
	var registry: Variant = _loaded_item_registry()
	if registry == null:
		return CoreResult.failure("content_unavailable")
	var candidates: Array[Dictionary] = []
	var seen_ids: Dictionary = {}
	for item_value: Variant in items_value:
		if not item_value is Dictionary or not registry.validate_item_instance(item_value).is_empty():
			return CoreResult.failure("invalid_room_loot_item")
		var item: Dictionary = item_value
		var instance_id := String(item.get("instance_id", ""))
		if instance_id.is_empty() or seen_ids.has(instance_id):
			continue
		seen_ids[instance_id] = true
		candidates.append(item.duplicate(true))
	var next_profile := _profile.duplicate(true)
	var equipment: Array = (next_profile.inventory as Dictionary).equipment
	var committed: Array = []
	for item in candidates:
		if not _owned_equipment(String(item.get("instance_id", ""))).is_empty():
			continue
		equipment.append(item.duplicate(true))
		committed.append(item.duplicate(true))
	var resolved := _resolve_build_with_inventory(
		next_profile.active_build, (next_profile.inventory as Dictionary).equipment, next_profile
	)
	if not bool(resolved.get("ok", false)):
		return CoreResult.failure("invalid_next_build")
	_profile = next_profile
	_active_session["room_index"] = int(room_index) + 1
	_active_session["resolved_build"] = (resolved as Dictionary).duplicate(true)
	return {
		"ok": true,
		"error": "",
		"committed_items": committed.duplicate(true),
		"resolved_build": (resolved as Dictionary).duplicate(true),
		"active_build": (_profile.active_build as Dictionary).duplicate(true),
	}.duplicate(true)


func complete_session(result: Dictionary) -> Dictionary:
	if _active_session.is_empty():
		return CoreResult.failure("active_session_required")
	_last_result = result.duplicate(true)
	if _is_auto_certification_graduation(_last_result):
		_last_result["outcome"] = "final_victory"
	_settle_room_equipment_drops(_last_result)
	var first_clear := String(_active_session.get("contract_id", "")) not in (_profile.progression.completed_node_ids as Array)
	_apply_result_progression(_last_result)
	_record_story_result_evidence(_last_result)
	var xp := 0
	if String(_last_result.get("outcome", "")) in ["victory", "final_victory"]:
		xp = CharacterProgressionScript.contract_experience(String(_active_session.get("contract_id", "")), first_clear)
	_last_result["character_growth"] = _apply_experience(xp)
	_attach_boss_defeat_diagnosis(_last_result)
	_active_session.clear()
	_pending_contract.clear()
	return {"ok": true, "result": _last_result.duplicate(true)}


func _record_story_result_evidence(result: Dictionary) -> void:
	var drops: Array = result.get("rewards", {}).get("equipment_drops", [])
	if not drops.is_empty():
		var already_seen := false
		for record in _profile.discoveries:
			if record is Dictionary and String(record.get("id", "")) == "first_equipment_find": already_seen = true
		if not already_seen:
			_profile.discoveries.append({"id":"first_equipment_find", "kind":"equipment_find", "instance_id":String(drops[0].get("instance_id", ""))})
	var frozen: Dictionary = _active_session.get("resolved_build", {})
	if String(frozen.get("build_fingerprint", "")).is_empty(): return
	for room in result.get("room_results", []):
		if not room is Dictionary: continue
		if int(room.get("arrow_hits", 0)) <= 0 or String(room.get("build_fingerprint", "")) != String(frozen.get("build_fingerprint", "")): continue
		var parameters: Dictionary = frozen.get("final_parameters", {})
		_record_growth_discovery({"state":String(frozen.get("growth_classification", "")), "preset_id":String(_active_session.get("preset_id", "")), "p":float(parameters.get("p", 0)), "R":float(frozen.get("R", 0)), "build_fingerprint":String(frozen.build_fingerprint), "source":"combat"})
		break


func abandon_session() -> void:
	_pending_contract.clear()
	_active_session.clear()


func persistent_payload(safe_route: String = "base") -> Dictionary:
	return _persistent_payload_for_profile(_profile, safe_route)


func _persistent_payload_for_profile(profile_value: Dictionary, safe_route: String) -> Dictionary:
	var route := safe_route if safe_route in SAFE_ROUTES else "base"
	if profile_value.is_empty():
		route = "title"
	return {
		"schema_version": PROFILE_SCHEMA_VERSION,
		"profile": profile_value.duplicate(true),
		"last_result": _last_result.duplicate(true),
		"safe_route": route,
	}.duplicate(true)


func restore_persistent_payload(payload: Variant) -> Dictionary:
	if not (payload is Dictionary):
		return CoreResult.failure("invalid_payload")
	var candidate: Dictionary = payload
	var schema: Variant = candidate.get("schema_version", null)
	if not _is_exact_integer(schema) or int(schema) != PROFILE_SCHEMA_VERSION:
		return CoreResult.failure("unsupported_schema_version")
	var candidate_profile: Variant = candidate.get("profile", null)
	if not (candidate_profile is Dictionary):
		return CoreResult.failure("invalid_profile")
	var restored_profile: Dictionary = (candidate_profile as Dictionary).duplicate(true)
	if not restored_profile.is_empty() and not _is_valid_profile(restored_profile):
		return CoreResult.failure("invalid_profile")
	if not restored_profile.is_empty():
		_normalize_current_profile_numbers(restored_profile)
	var candidate_result: Variant = candidate.get("last_result", {})
	if not (candidate_result is Dictionary):
		return CoreResult.failure("invalid_last_result")
	var route_value: Variant = candidate.get("safe_route", "title")
	if not _is_text(route_value) or String(route_value) not in SAFE_ROUTES:
		return CoreResult.failure("invalid_safe_route")
	var route := String(route_value)
	if restored_profile.is_empty():
		route = "title"
	_profile = restored_profile.duplicate(true)
	_last_result = (candidate_result as Dictionary).duplicate(true)
	_pending_contract.clear()
	_active_session.clear()
	_forge_context.clear()
	_forge_session.clear()
	_pending_forge_commit.clear()
	return {"ok": true, "route": route}


func _is_valid_profile(candidate: Dictionary) -> bool:
	var profile_schema: Variant = candidate.get("schema_version", null)
	if not _is_exact_integer(profile_schema) or int(profile_schema) != PROFILE_SCHEMA_VERSION:
		return false
	if String(candidate.get("profile_id", "")).strip_edges().is_empty():
		return false
	var initial_class: Variant = candidate.get("initial_class", null)
	if not _is_text(initial_class) or String(initial_class) not in SUPPORTED_CLASSES:
		return false
	if typeof(candidate.get("tutorial_complete", null)) != TYPE_BOOL:
		return false
	if not _valid_story(candidate):
		return false
	if not CharacterProgressionScript.is_valid_state(candidate.get("character")):
		return false
	var talents_value: Variant = candidate.get("talents")
	if not talents_value is Dictionary or not _has_exact_keys(talents_value, ["allocated_ids", "stance"]):
		return false
	if not talents_value.get("allocated_ids") is Array or String(talents_value.get("stance", "")) not in ["near", "mid", "far"]:
		return false
	var unlocked: Variant = candidate.get("unlocked_classes", null)
	if not (unlocked is Array) or (unlocked as Array).is_empty():
		return false
	var seen := {}
	for unlocked_class in (unlocked as Array):
		if not _is_text(unlocked_class) or String(unlocked_class) not in SUPPORTED_CLASSES or seen.has(String(unlocked_class)):
			return false
		seen[String(unlocked_class)] = true
	if not seen.has(String(initial_class)):
		return false
	var resources: Variant = candidate.get("resources", null)
	if not (resources is Dictionary) or not _has_exact_keys(resources as Dictionary, ["law_tallies"]):
		return false
	var tallies: Variant = (resources as Dictionary).get("law_tallies", null)
	if not (tallies is Dictionary) or not _has_exact_keys(tallies as Dictionary, FORGE_OPERATIONS):
		return false
	for operation in FORGE_OPERATIONS:
		if not _is_non_negative_integer((tallies as Dictionary).get(operation, null)):
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
	if not (proxy_build is Dictionary) or not _has_exact_keys(proxy_build as Dictionary, ["cores", "settings", "attachments"]):
		return false
	if not ((proxy_build as Dictionary).get("cores", null) is Array) or ((proxy_build as Dictionary).get("cores") as Array).size() != 4:
		return false
	if not ((proxy_build as Dictionary).get("settings", null) is Dictionary):
		return false
	if not ((proxy_build as Dictionary).get("attachments", null) is Array) or ((proxy_build as Dictionary).get("attachments") as Array).size() != 3:
		return false
	for core_id in (proxy_build as Dictionary).cores:
		if not _is_text(core_id):
			return false
	for attachment_id in (proxy_build as Dictionary).attachments:
		if not _is_text(attachment_id) or not String(attachment_id).is_empty():
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
		var proxy_registry: Variant = _loaded_content_registry()
		if proxy_registry == null or not bool(ProxyBuildScript.compile(_proxy_compile_input(proxy_build as Dictionary), proxy_registry.cores).get("ok", false)):
			return false
	elif not (proxy_build as Dictionary).settings.is_empty():
		return false
	if not (candidate.get("discoveries", null) is Array):
		return false
	var immortality: Variant = candidate.get("immortality", null)
	if not (immortality is Dictionary) or typeof((immortality as Dictionary).get("unlocked", null)) != TYPE_BOOL or not ((immortality as Dictionary).get("proofs", null) is Array):
		return false
	var progression: Variant = candidate.get("progression", null)
	if not (progression is Dictionary) or not _is_non_negative_integer((progression as Dictionary).get("contract_wins", null)):
		return false
	if typeof((progression as Dictionary).get("ending_unlocked", null)) != TYPE_BOOL:
		return false
	if not _is_valid_active_build(active_build as Dictionary):
		return false
	if not bool(_resolve_build_with_inventory(active_build, (inventory as Dictionary).equipment, candidate).get("ok", false)):
		return false
	var training: Variant = candidate.get("training", null)
	if not (training is Dictionary) or not _has_exact_keys(training as Dictionary, ["reports_by_fingerprint"]):
		return false
	var reports_by_fingerprint: Variant = (training as Dictionary).get("reports_by_fingerprint", null)
	if not (reports_by_fingerprint is Dictionary):
		return false
	for fingerprint: Variant in (reports_by_fingerprint as Dictionary):
		if not _is_fingerprint(fingerprint):
			return false
		var report: Variant = (reports_by_fingerprint as Dictionary)[fingerprint]
		if not (report is Dictionary) or String((report as Dictionary).get("build_fingerprint", "")) != String(fingerprint):
			return false
	for flag in ["threshold_colossus_defeated", "proxy_unlocked", "early_game_complete"]:
		if typeof((progression as Dictionary).get(flag, null)) != TYPE_BOOL:
			return false
	if not _is_non_negative_integer((progression as Dictionary).get("auto_contract_wins", null)):
		return false
	if not _is_valid_repeatable_completion_counts((progression as Dictionary).get("repeatable_completion_counts", null)):
		return false
	if not _is_valid_completed_node_ids((progression as Dictionary).get("completed_node_ids", null)):
		return false
	return true


func _normalize_current_profile_numbers(candidate: Dictionary) -> void:
	candidate["schema_version"] = PROFILE_SCHEMA_VERSION
	candidate.character.experience = int(candidate.character.experience)
	var tallies: Dictionary = (candidate.resources as Dictionary).law_tallies
	for operation in FORGE_OPERATIONS:
		tallies[operation] = int(tallies[operation])
	var progression: Dictionary = candidate.progression
	progression["contract_wins"] = int(progression.contract_wins)
	progression["auto_contract_wins"] = int(progression.auto_contract_wins)
	var counts: Dictionary = progression.repeatable_completion_counts
	for contract_id in counts:
		counts[contract_id] = int(counts[contract_id])


func _loaded_content_registry() -> Variant:
	var registry := ContentRegistryScript.new()
	if not registry.load_all().is_empty():
		return null
	return registry


func _raw_proxy_build_snapshot() -> Dictionary:
	var stored_value: Variant = _profile.get("proxy_build", null)
	if not stored_value is Dictionary:
		return CoreResult.failure("invalid_proxy_build")
	var stored: Dictionary = stored_value
	if not _has_exact_keys(stored, ["cores", "settings", "attachments"]):
		return CoreResult.failure("invalid_proxy_build")
	if not stored.cores is Array or (stored.cores as Array).size() != ProxyBuildScript.SLOT_ORDER.size():
		return CoreResult.failure("invalid_proxy_build")
	if not stored.settings is Dictionary:
		return CoreResult.failure("invalid_proxy_build")
	if not stored.attachments is Array or (stored.attachments as Array).size() != 3:
		return CoreResult.failure("invalid_proxy_build")
	for core_id in (stored.cores as Array):
		if not _is_text(core_id):
			return CoreResult.failure("invalid_proxy_build")
	for attachment_id in (stored.attachments as Array):
		if not _is_text(attachment_id) or not String(attachment_id).is_empty():
			return CoreResult.failure("invalid_proxy_build")
	return {"ok": true, "value": stored.duplicate(true)}


func _proxy_compile_input(raw_build: Dictionary) -> Dictionary:
	return {
		"cores": (raw_build.cores as Array).duplicate(),
		"settings": (raw_build.settings as Dictionary).duplicate(true),
	}


func _commit_proxy_build_candidate(candidate: Dictionary, core_catalog: Dictionary) -> Dictionary:
	var compiled: Dictionary = ProxyBuildScript.compile(_proxy_compile_input(candidate), core_catalog)
	if not bool(compiled.get("ok", false)):
		return CoreResult.failure("proxy_build_%s" % String(compiled.get("error", "invalid")))
	_profile["proxy_build"] = candidate.duplicate(true)
	return {
		"ok": true,
		"proxy_build": candidate.duplicate(true),
		"resolved_proxy_build": (compiled.value as Dictionary).duplicate(true),
	}.duplicate(true)


func _owns_proxy_core(core_id: String) -> bool:
	for component in ((_profile.inventory as Dictionary).proxy_components as Array):
		if component is Dictionary and String((component as Dictionary).get("id", "")) == core_id:
			return true
	return false


func _proxy_catalog_snapshot(core_catalog: Dictionary) -> Dictionary:
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


func _loaded_early_campaign_registry() -> Variant:
	var registry := EarlyCampaignRegistryScript.new()
	if not registry.load_campaign().is_empty():
		return null
	return registry


func _repeatable_campaign_node_ids(registry: Variant) -> Array:
	var file := FileAccess.open(EarlyCampaignRegistryScript.DEFAULT_PATH, FileAccess.READ)
	if file == null:
		return []
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not (data is Dictionary):
		return []
	var templates: Variant = (data as Dictionary).get("repeatable_templates", [])
	if not (templates is Array):
		return []
	var result: Array = []
	for node_value in (templates as Array):
		if not (node_value is Dictionary):
			continue
		var node_id := String((node_value as Dictionary).get("id", ""))
		if not node_id.is_empty() and not registry.get_node(node_id).is_empty():
			result.append(node_id)
	return result


func _repeatable_side_template_ids() -> Array:
	var registry: Variant = _loaded_early_campaign_registry()
	if registry == null:
		return []
	return _repeatable_campaign_node_ids(registry)


func _is_valid_repeatable_completion_counts(value: Variant) -> bool:
	if not (value is Dictionary):
		return false
	var allowed := {}
	for node_id in _repeatable_side_template_ids():
		allowed[node_id] = true
	for key in (value as Dictionary):
		if not _is_text(key) or not allowed.has(String(key)):
			return false
		if not _is_non_negative_integer((value as Dictionary)[key]):
			return false
	return true


func _repeatable_attempt_for_session() -> int:
	if not has_profile():
		return 0
	var contract_id := String(_active_session.get("contract_id", ""))
	if contract_id not in _repeatable_side_template_ids():
		return 0
	var progression: Dictionary = _profile.progression
	var counts_value: Variant = progression.get("repeatable_completion_counts", {})
	var prior := 0
	if counts_value is Dictionary:
		var prior_value: Variant = (counts_value as Dictionary).get(contract_id, 0)
		prior = int(prior_value) if _is_non_negative_integer(prior_value) else 0
	return prior + 1


func _legacy_build_from_preset(preset_id: String) -> Dictionary:
	var registry: Variant = _loaded_content_registry()
	if registry == null or not registry.presets.has(preset_id):
		return {}
	var preset: Dictionary = registry.presets[preset_id]
	var equipment: Dictionary = (preset.equipment as Dictionary).duplicate(true)
	equipment["parameters"] = registry.preset_equipped_parameters.duplicate(true)
	return {
		"preset_id": preset_id,
		"equipment": equipment,
	}.duplicate(true)


func _is_valid_active_build(build: Dictionary) -> bool:
	if not _has_exact_keys(build, ["skills", "equipped_item_ids"]):
		return false
	var skills: Variant = build.get("skills", null)
	if not (skills is Array) or (skills as Array).size() != 3:
		return false
	for skill in (skills as Array):
		if not _is_text(skill):
			return false
	var equipped: Variant = build.get("equipped_item_ids", null)
	if not (equipped is Dictionary) or not _has_exact_keys(equipped, EarlyItemRegistryScript.EQUIPMENT_SLOTS):
		return false
	var seen_ids := {}
	for slot in EarlyItemRegistryScript.EQUIPMENT_SLOTS:
		var instance_id: Variant = (equipped as Dictionary).get(slot, null)
		if not _is_text(instance_id):
			return false
		var id := String(instance_id)
		if slot not in EarlyItemRegistryScript.PROTOTYPE_OPEN_SLOTS and not id.is_empty():
			return false
		if not id.is_empty() and seen_ids.has(id):
			return false
		seen_ids[id] = true
	return true


func _is_valid_completed_node_ids(value: Variant) -> bool:
	if not (value is Array):
		return false
	var registry: Variant = _loaded_early_campaign_registry()
	if registry == null:
		return false
	var fixed_order: Array[String] = registry.mainline_order()
	var previous_index := -1
	for node_id_value in (value as Array):
		if not _is_text(node_id_value):
			return false
		var node_id := String(node_id_value)
		var node_index := fixed_order.find(node_id)
		if node_index < 0 or node_index <= previous_index:
			return false
		previous_index = node_index
	return true


func _loaded_item_registry() -> Variant:
	var registry := EarlyItemRegistryScript.new()
	if not registry.load_all().is_empty():
		return null
	return registry


func _fixture_state(fixture_id: String) -> Dictionary:
	var registry: Variant = _loaded_item_registry()
	if registry == null or not registry.build_fixtures.has(fixture_id):
		return {}
	var fixture: Dictionary = registry.build_fixtures[fixture_id]
	var by_slot: Dictionary = registry.equipment_for_fixture(fixture_id)
	if by_slot.size() != EarlyItemRegistryScript.PROTOTYPE_OPEN_SLOTS.size():
		return {}
	var ids := _empty_equipped_item_ids()
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


func _empty_equipped_item_ids() -> Dictionary:
	var result := {}
	for slot in EarlyItemRegistryScript.EQUIPMENT_SLOTS:
		result[slot] = ""
	return result


func _fixture_id_for_legacy_name(value: String) -> String:
	var normalized := value.strip_edges().to_lower()
	if normalized.begins_with("calibration_"):
		return normalized if normalized in PRESET_FIXTURES.values() else ""
	return String(PRESET_FIXTURES.get(normalized, ""))


func _legacy_preset_for_active_build(build: Dictionary) -> String:
	match _exact_fixture_for_build(build):
		"fixed_start", "calibration_convergent":
			return "convergent"
		"calibration_critical":
			return "critical"
		"calibration_exponential":
			return "exponential"
	return "custom"


func _exact_fixture_for_build(build: Dictionary) -> String:
	var equipped_value: Variant = build.get("equipped_item_ids", {})
	if not equipped_value is Dictionary:
		return ""
	var equipped: Dictionary = equipped_value
	var registry: Variant = _loaded_item_registry()
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


func _resolve_active_build(build: Dictionary) -> Dictionary:
	var inventory: Dictionary = _profile.inventory
	return _resolve_build_with_inventory(build, inventory.equipment)


func _resolve_build_with_inventory(build: Dictionary, equipment_inventory: Array, character_profile: Dictionary = {}) -> Dictionary:
	var registry: Variant = _loaded_item_registry()
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
		var item := _owned_equipment_from(equipment_inventory, instance_id)
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
		_talent_context(_profile if character_profile.is_empty() else character_profile)
	)


func _resolved_connected_interfaces(resolved: Dictionary) -> Array[String]:
	var interfaces: Array[String] = []
	var value: Variant = resolved.get("connected_interfaces", null)
	if value is Array:
		for entry in value:
			if _is_text(entry):
				interfaces.append(String(entry))
	return interfaces


func _resolved_tag_ids(resolved: Dictionary) -> Array[String]:
	# The resolved Build currently exposes no authoritative tag set; never infer
	# tags from item affixes. Only honor a future explicit "tags" array.
	var tags: Array[String] = []
	var value: Variant = resolved.get("tags", null)
	if value is Array:
		for entry in value:
			if _is_text(entry):
				tags.append(String(entry))
	tags.sort()
	return tags


func _owned_equipment(instance_id: String) -> Dictionary:
	if not has_profile():
		return {}
	var inventory_value: Variant = _profile.get("inventory", {})
	if not inventory_value is Dictionary:
		return {}
	var equipment_value: Variant = (inventory_value as Dictionary).get("equipment", [])
	if not equipment_value is Array:
		return {}
	return _owned_equipment_from(equipment_value, instance_id)


func _owned_equipment_from(equipment: Array, instance_id: String) -> Dictionary:
	for item in equipment:
		if item is Dictionary and String((item as Dictionary).get("instance_id", "")) == instance_id:
			return (item as Dictionary).duplicate(true)
	return {}


func _merge_equipment_inventory(items: Array) -> void:
	var equipment: Array = (_profile.inventory as Dictionary).equipment
	for item in items:
		_append_unique_equipment(equipment, item)


func _append_unique_equipment(equipment: Array, item: Variant) -> void:
	if not item is Dictionary:
		return
	var instance_id := String((item as Dictionary).get("instance_id", ""))
	for existing in equipment:
		if existing is Dictionary and String((existing as Dictionary).get("instance_id", "")) == instance_id:
			return
	equipment.append((item as Dictionary).duplicate(true))


func _is_valid_item_instance(value: Variant) -> bool:
	var registry: Variant = _loaded_item_registry()
	return registry != null and registry.validate_item_instance(value).is_empty()


func _is_proxy_component(value: Variant) -> bool:
	if not value is Dictionary or not _has_exact_keys(value as Dictionary, ["id", "name", "slot", "rarity", "type", "protocol", "source_contract"]):
		return false
	var component: Dictionary = value
	var registry: Variant = _loaded_content_registry()
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
		and _is_text(component.get("source_contract", null)) \
		and not String(component.source_contract).strip_edges().is_empty()


func _is_valid_partitioned_inventory(value: Variant) -> bool:
	if not value is Dictionary or not _has_exact_keys(value, ["equipment", "proxy_components", "legacy_drops"]):
		return false
	for field in ["equipment", "proxy_components", "legacy_drops"]:
		if not (value as Dictionary).get(field, null) is Array:
			return false
	var seen := {}
	for item in ((value as Dictionary).equipment as Array):
		if not _is_valid_item_instance(item):
			return false
		var instance_id := String((item as Dictionary).instance_id)
		if seen.has(instance_id):
			return false
		seen[instance_id] = true
	var proxy_seen := {}
	for component in ((value as Dictionary).proxy_components as Array):
		if not _is_proxy_component(component):
			return false
		var component_id := String((component as Dictionary).id)
		if proxy_seen.has(component_id):
			return false
		proxy_seen[component_id] = true
	return true


func _is_fingerprint(value: Variant) -> bool:
	if not _is_text(value):
		return false
	var fingerprint := String(value)
	if fingerprint.length() != 64:
		return false
	for character in fingerprint:
		if character not in "0123456789abcdef":
			return false
	return true


func _fingerprint_for_fixture(fixture_id: String) -> String:
	if fixture_id.is_empty():
		return ""
	var registry: Variant = _loaded_item_registry()
	if registry == null:
		return ""
	var fixture: Dictionary = registry.build_fixtures.get(fixture_id, {})
	if fixture.is_empty(): return ""
	var resolved: Dictionary = BuildResolverScript.new(registry).resolve(
		fixture.base_parameters, registry.equipment_for_fixture(fixture_id), String(fixture.skill_id), _talent_context(_profile)
	)
	return String(resolved.get("build_fingerprint", "")) if bool(resolved.get("ok", false)) else ""


func _record_growth_discovery(report: Dictionary) -> void:
	if String(report.get("state", "")) not in ["convergent", "critical", "exponential"]: return
	var discovery_id := "growth_%s" % String(report.state)
	for existing in (_profile.discoveries as Array):
		if existing is Dictionary and String((existing as Dictionary).get("id", "")) == discovery_id:
			return
	(_profile.discoveries as Array).append({
		"id": discovery_id,
		"kind": "growth_state",
		"state": String(report.state),
		"preset_id": String(report.preset_id),
		"p": float(report.p),
		"R": float(report.R),
		"build_fingerprint": String(report.get("build_fingerprint", "")),
		"source": String(report.get("source", "training")),
	})


func _refresh_early_game_completion() -> void:
	var progression: Dictionary = _profile.progression
	if "auto_certification" in (progression.completed_node_ids as Array):
		progression["early_game_complete"] = true


func _record_completed_campaign_node(node_id: String, completed_mode: String = "") -> bool:
	var registry: Variant = _loaded_early_campaign_registry()
	if registry == null:
		return false
	var fixed_order: Array[String] = registry.mainline_order()
	if node_id not in fixed_order:
		return false
	var node: Dictionary = registry.get_node(node_id)
	if not completed_mode.is_empty() and completed_mode not in (node.get("allowed_modes", []) as Array):
		return false
	var progression: Dictionary = _profile.progression
	var completed: Array = progression.completed_node_ids
	for prerequisite_value in (node.get("unlock_prerequisites", []) as Array):
		if String(prerequisite_value) not in completed:
			return false
	if node_id in completed:
		return false
	completed.append(node_id)
	completed.sort_custom(func(a: Variant, b: Variant) -> bool:
		return fixed_order.find(String(a)) < fixed_order.find(String(b))
	)
	return true


func _earned_campaign_reward_tags(registry: Variant, completed_node_ids: Array) -> Array:
	var completed := {}
	for node_id_value in completed_node_ids:
		completed[String(node_id_value)] = true
	var seen := {}
	var earned: Array = []
	for node_id in registry.mainline_order():
		if not completed.has(node_id):
			continue
		var node: Dictionary = registry.get_node(node_id)
		for tag_value in (node.get("first_reward_tags", []) as Array):
			var tag := String(tag_value)
			if not seen.has(tag):
				seen[tag] = true
				earned.append(tag)
	return earned


func _apply_first_reward_tags(tags: Array) -> Array:
	var active: Dictionary = _profile.active_build
	var stable_item_ids: Array[String] = []
	for tag_value in tags:
		var tag := String(tag_value)
		match tag:
			"hunter_mark_skill":
				_grant_skill_slot(active.skills as Array, "hunter_mark", 1)
			"dash_skill":
				_grant_skill_slot(active.skills as Array, "dash", 2)
		if STABLE_FIRST_REWARD_ITEMS.has(tag):
			stable_item_ids.append(String(STABLE_FIRST_REWARD_ITEMS[tag]))
	return _grant_stable_reward_items(stable_item_ids)


## Stable semantic rewards enter inventory as immutable ItemInstance snapshots.
## They never write rune/law fields into active_build and only affect resolution
## after the player equips their instance_id in the matching slot.
func _grant_stable_reward_items(instance_ids: Array[String]) -> Array:
	if instance_ids.is_empty():
		return []
	var registry: Variant = _loaded_item_registry()
	if registry == null:
		return []
	var equipment: Array = ((_profile.inventory as Dictionary).equipment as Array)
	var owned_ids := {}
	for value in equipment:
		if value is Dictionary:
			owned_ids[String((value as Dictionary).get("instance_id", ""))] = true
	var candidates: Array = []
	for instance_id in instance_ids:
		if owned_ids.has(instance_id):
			continue
		var item_value: Variant = registry.item_instances.get(instance_id, {})
		if not (item_value is Dictionary):
			return []
		var item: Dictionary = (item_value as Dictionary).duplicate(true)
		if not registry.validate_item_instance(item).is_empty():
			return []
		candidates.append(item)
	for item_value in candidates:
		var item: Dictionary = item_value
		equipment.append(item.duplicate(true))
	return candidates.duplicate(true)


func _append_granted_equipment_to_result(result: Dictionary, granted: Array) -> void:
	if granted.is_empty():
		return
	var rewards_value: Variant = result.get("rewards", {})
	var rewards: Dictionary = rewards_value.duplicate(true) if rewards_value is Dictionary else {}
	var drops_value: Variant = rewards.get("equipment_drops", [])
	var drops: Array = drops_value.duplicate(true) if drops_value is Array else []
	for item in granted:
		drops.append((item as Dictionary).duplicate(true))
	rewards["equipment_drops"] = drops
	rewards["equipment_drop_count"] = drops.size()
	result["rewards"] = rewards


func _grant_skill_slot(skills: Array, skill_id: String, slot_index: int) -> void:
	if slot_index < 0 or slot_index >= skills.size() or String(skills[slot_index]) == skill_id:
		return
	if not String(skills[slot_index]).is_empty():
		return
	var existing_index := skills.find(skill_id)
	if existing_index >= 0:
		skills[existing_index] = ""
	skills[slot_index] = skill_id


func _normalize_mode(value: String) -> String:
	match value.strip_edges().to_lower():
		"manual":
			return "Manual"
		"auto":
			return "Auto"
	return ""


func _is_text(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME


func _is_non_negative_integer(value: Variant) -> bool:
	return _is_exact_integer(value) and int(value) >= 0


func _is_exact_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var number := float(value)
	return not is_nan(number) and not is_inf(number) and floor(number) == number


func _settle_room_equipment_drops(result: Dictionary) -> void:
	var rewards_value: Variant = result.get("rewards", {})
	var rewards: Dictionary = rewards_value if rewards_value is Dictionary else {}
	var added: Array = []
	var ledger_room_indices: Dictionary = {}
	var ledger_items := _collect_room_loot_items(result, ledger_room_indices)
	for item_value: Variant in ledger_items:
		if item_value is Dictionary:
			var item: Dictionary = (item_value as Dictionary).duplicate(true)
			var registry: Variant = _loaded_item_registry()
			if registry != null and registry.validate_item_instance(item).is_empty():
				var instance_id := String(item.get("instance_id", ""))
				if not instance_id.is_empty() and _owned_equipment(instance_id).is_empty():
					(((_profile.inventory as Dictionary).equipment) as Array).append(item.duplicate(true))
					added.append(item.duplicate(true))
	var attempt_number := _repeatable_attempt_for_session()
	var pity_family := ""
	if attempt_number > 0:
		rewards["repeatable_attempt_number"] = attempt_number
		if String(_active_session.get("contract_id", "")) == PITY_SIDE_CONTRACT_ID and attempt_number % PITY_TRIGGER_PERIOD == 0:
			var resolved_value: Variant = _active_session.get("resolved_build", {})
			var resolved_build: Dictionary = resolved_value if resolved_value is Dictionary else {}
			pity_family = _pity_family_for_resolved_build(resolved_build)
	var outcome := String(result.get("outcome", "")).to_lower()
	if has_profile() and outcome in ["victory", "final_victory"] and _equipment_drops_unlocked_for_session():
		added.append_array(_generate_new_room_equipment(result, attempt_number, pity_family, rewards, ledger_room_indices))
	rewards["equipment_drops"] = added.duplicate(true)
	rewards["equipment_drop_count"] = added.size()
	result["rewards"] = rewards


func _equipment_drops_unlocked_for_session() -> bool:
	if not bool(_profile.get("tutorial_complete", false)):
		return false
	var registry: Variant = _loaded_early_campaign_registry()
	if registry == null:
		return false
	var contract_id := String(_active_session.get("contract_id", ""))
	if contract_id == "tutorial_ranger_basics":
		return false
	return registry.get_node(contract_id).is_empty() or registry.is_unlocked(
		contract_id, _profile.progression.completed_node_ids, String(_active_session.get("mode", ""))
	)


func _generate_new_room_equipment(result: Dictionary, attempt_number: int = 0, pity_family: String = "", rewards: Dictionary = {}, skip_room_indices: Dictionary = {}) -> Array:
	var plan_value: Variant = _active_session.get("room_plan", {})
	if not plan_value is Dictionary:
		return []
	var rooms_value: Variant = (plan_value as Dictionary).get("rooms", [])
	if not rooms_value is Array:
		return []
	var rooms: Array = rooms_value
	var room_limit := rooms.size()
	if result.has("rooms_completed"):
		var completed_value: Variant = result.get("rooms_completed")
		room_limit = clampi(int(completed_value), 0, rooms.size()) if _is_exact_integer(completed_value) else 0
	var registry: Variant = _loaded_item_registry()
	if registry == null:
		return []
	var generator: RefCounted = EquipmentDropGeneratorScript.new(registry)
	var equipment: Array = ((_profile.inventory as Dictionary).equipment as Array)
	var owned_ids := {}
	for existing in equipment:
		if existing is Dictionary:
			owned_ids[String((existing as Dictionary).get("instance_id", ""))] = true
	var seed := int(_active_session.get("seed", 0))
	var pity_pending := not pity_family.is_empty()
	var added: Array = []
	for room_index in range(room_limit):
		if skip_room_indices.has(room_index):
			continue
		var room_value: Variant = rooms[room_index]
		if not room_value is Dictionary:
			continue
		var room: Dictionary = room_value
		var tags_value: Variant = room.get("drop_tags", [])
		if not tags_value is Array:
			continue
		var tags: Array = (tags_value as Array).duplicate()
		var room_id := String(room.get("room_id", "")).strip_edges()
		if room_id.is_empty():
			room_id = "room_%d" % room_index
		var source_id := "room_%s_%d" % [room_id.sha256_text(), room_index]
		if attempt_number > 0:
			source_id = "%s_attempt_%d" % [source_id, attempt_number]
		var guarantee := ""
		var guarantee_value: Variant = room.get("guarantee_family", "")
		if _is_text(guarantee_value):
			guarantee = String(guarantee_value)
		if pity_pending:
			if not _has_recognized_equipment_tag(tags):
				tags.append(EquipmentDropGeneratorScript.GENERAL_TAGS[0])
			guarantee = pity_family
		var item: Dictionary = generator.generate_drop(
			seed, source_id, ROOM_EQUIPMENT_DROP_INDEX, tags, guarantee
		)
		if item.is_empty() or not registry.validate_item_instance(item).is_empty():
			continue
		var instance_id := String(item.get("instance_id", ""))
		if instance_id.is_empty() or owned_ids.has(instance_id):
			continue
		var snapshot := item.duplicate(true)
		equipment.append(snapshot.duplicate(true))
		added.append(snapshot)
		owned_ids[instance_id] = true
		if pity_pending:
			pity_pending = false
			rewards["pity_guarantee_family"] = pity_family
	return added


func _collect_room_loot_items(result: Dictionary, room_indices: Dictionary) -> Array[Dictionary]:
	var collected: Array[Dictionary] = []
	var room_results_value: Variant = result.get("room_results", [])
	if not room_results_value is Array:
		return collected
	for room_index in (room_results_value as Array).size():
		var room_value: Variant = (room_results_value as Array)[room_index]
		if not room_value is Dictionary:
			continue
		var settlement_value: Variant = (room_value as Dictionary).get("room_loot_settlement", {})
		if not settlement_value is Dictionary or (settlement_value as Dictionary).is_empty():
			continue
		room_indices[room_index] = true
		var items_value: Variant = (settlement_value as Dictionary).get("items", [])
		if items_value is Array:
			for item_value: Variant in items_value:
				if item_value is Dictionary:
					collected.append((item_value as Dictionary).duplicate(true))
	return collected


func _has_recognized_equipment_tag(tags: Array) -> bool:
	for value in tags:
		if not (value is String):
			continue
		var tag := String(value).strip_edges()
		if tag in EquipmentDropGeneratorScript.GENERAL_TAGS or EquipmentDropGeneratorScript.SLOT_TAGS.has(tag) or EquipmentDropGeneratorScript.FAMILY_TAGS.has(tag):
			return true
	return false


func _pity_family_for_resolved_build(resolved_build: Dictionary) -> String:
	var classification := String(resolved_build.get("growth_classification", "")).to_lower()
	var parameters_value: Variant = resolved_build.get("final_parameters", {})
	var parameters: Dictionary = parameters_value if parameters_value is Dictionary else {}
	var growth_p := _boss_parameter(parameters, "p", 0.0)
	if classification != "exponential" or growth_p <= PITY_EXPONENTIAL_P_THRESHOLD:
		return PITY_TARGET_GROWTH
	if _boss_parameter(parameters, "d", INF) < BOSS_DIAGNOSIS_RANGE_MIN:
		return PITY_TARGET_RANGE
	if _boss_parameter(parameters, "T", INF) < BOSS_DIAGNOSIS_LIFETIME_MIN:
		return PITY_TARGET_LIFETIME
	return PITY_TARGET_POWER


func _is_auto_certification_eligible() -> bool:
	if String(_active_session.get("contract_id", "")) != "auto_certification":
		return false
	if String(_active_session.get("mode", "")) != "Auto":
		return false
	if not has_profile():
		return false
	var completed_value: Variant = (_profile.progression as Dictionary).get("completed_node_ids", [])
	return completed_value is Array and "threshold_colossus" in (completed_value as Array)


func _is_auto_certification_graduation(result: Dictionary) -> bool:
	if String(result.get("outcome", "")).to_lower() != "victory":
		return false
	if not _is_auto_certification_eligible():
		return false
	var completed: Array = (_profile.progression as Dictionary).completed_node_ids
	return "auto_certification" not in completed


func _apply_result_progression(result: Dictionary) -> void:
	result["first_reward_tags"] = []
	result["proxy_component_drops"] = []
	var outcome := String(result.get("outcome", "")).to_lower()
	if not has_profile() or outcome not in ["victory", "final_victory"]:
		return
	var progression: Dictionary = _profile.progression
	var completed_mode := String(_active_session.get("mode", ""))
	var completed_contract_id := String(_active_session.get("contract_id", ""))
	var rewards_value: Variant = result.get("rewards", {})
	var rewards: Dictionary = rewards_value if rewards_value is Dictionary else {}
	var wins_delta := _safe_reward_delta(rewards.get("contract_wins_delta", 1))
	var tallies_delta_value: Variant = rewards.get("law_tallies_delta", {})
	var tallies_delta: Dictionary = tallies_delta_value if tallies_delta_value is Dictionary else {}
	progression["contract_wins"] = int(progression.get("contract_wins", 0)) + wins_delta
	if completed_contract_id in _repeatable_side_template_ids():
		if not progression.has("repeatable_completion_counts") or not (progression.repeatable_completion_counts is Dictionary):
			progression["repeatable_completion_counts"] = {}
		var counts: Dictionary = progression.repeatable_completion_counts
		var prior: Variant = counts.get(completed_contract_id, 0)
		counts[completed_contract_id] = (int(prior) if _is_non_negative_integer(prior) else 0) + 1
	if outcome == "final_victory":
		progression["ending_unlocked"] = true
	var first_fixed_completion := _record_completed_campaign_node(completed_contract_id, completed_mode)
	if first_fixed_completion:
		var registry: Variant = _loaded_early_campaign_registry()
		if registry != null:
			var completed_node: Dictionary = registry.get_node(completed_contract_id)
			var first_reward_tags: Array = (completed_node.get("first_reward_tags", []) as Array).duplicate(true)
			result["first_reward_tags"] = first_reward_tags.duplicate(true)
			var granted_items := _apply_first_reward_tags(first_reward_tags)
			_append_granted_equipment_to_result(result, granted_items)
	if completed_contract_id == "threshold_colossus" and completed_mode == "Manual" and first_fixed_completion:
		progression["threshold_colossus_defeated"] = true
		progression["proxy_unlocked"] = true
		var granted := _grant_initial_proxy()
		result["unlock"] = {
			"proxy_unlocked": true,
			"title": "First-kill proxy unlocked",
			"components": granted.duplicate(true),
		}
	if completed_mode == "Auto" and bool(progression.get("proxy_unlocked", false)):
		progression["auto_contract_wins"] = int(progression.get("auto_contract_wins", 0)) + 1
		var auto_win_number := int(progression.auto_contract_wins)
		if auto_win_number <= AUTO_PROXY_REWARD_IDS.size():
			var dropped := _grant_proxy_core(AUTO_PROXY_REWARD_IDS[auto_win_number - 1], completed_contract_id)
			if not dropped.is_empty():
				result["proxy_component_drops"] = [dropped.duplicate(true)]
		progression["early_game_complete"] = "auto_certification" in (progression.completed_node_ids as Array)
	var law_tallies: Dictionary = (_profile.resources as Dictionary).law_tallies
	for operation in FORGE_OPERATIONS:
		law_tallies[operation] = int(law_tallies.get(operation, 0)) + _safe_reward_delta(tallies_delta.get(operation, 0))
	var drop_id := String(rewards.get("drop_id", "")).strip_edges()
	if not drop_id.is_empty():
		((_profile.inventory as Dictionary).legacy_drops as Array).append({
			"id": drop_id,
			"label": String(rewards.get("drop_label", drop_id)),
			"source_contract": String(_active_session.get("contract_id", "")),
		})


func _attach_boss_defeat_diagnosis(result: Dictionary) -> void:
	if String(_active_session.get("contract_id", "")) != BOSS_DIAGNOSIS_CONTRACT_ID:
		return
	if String(_active_session.get("mode", "")) != BOSS_DIAGNOSIS_MODE:
		return
	if String(result.get("outcome", "")).to_lower() != "defeat":
		return
	var resolved_value: Variant = _active_session.get("resolved_build", {})
	var resolved_build: Dictionary = resolved_value if resolved_value is Dictionary else {}
	result["primary_bottleneck"] = _classify_boss_bottleneck(resolved_build)


func _classify_boss_bottleneck(resolved_build: Dictionary) -> Dictionary:
	var classification := String(resolved_build.get("growth_classification", "")).to_lower()
	if classification == "convergent":
		return BOSS_BOTTLENECK_GROWTH_CONVERGENT.duplicate(true)
	if classification == "critical":
		return BOSS_BOTTLENECK_GROWTH_CRITICAL.duplicate(true)
	if classification == "exponential":
		var parameters_value: Variant = resolved_build.get("final_parameters", {})
		var parameters: Dictionary = parameters_value if parameters_value is Dictionary else {}
		if _boss_parameter(parameters, "d", INF) < BOSS_DIAGNOSIS_RANGE_MIN:
			return BOSS_BOTTLENECK_TARGETING_RANGE_SHORT.duplicate(true)
		if _boss_parameter(parameters, "T", INF) < BOSS_DIAGNOSIS_LIFETIME_MIN:
			return BOSS_BOTTLENECK_PROJECTILE_LIFETIME_SHORT.duplicate(true)
	return BOSS_BOTTLENECK_BOSS_PATTERN_SURVIVAL.duplicate(true)


func _boss_parameter(parameters: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = parameters.get(key, null)
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return fallback
	var number := float(value)
	if is_nan(number) or is_inf(number):
		return fallback
	return number


func _grant_initial_proxy() -> Array:
	(_profile.proxy_build as Dictionary)["cores"] = INITIAL_PROXY_CORE_IDS.duplicate()
	(_profile.proxy_build as Dictionary)["settings"] = {}
	var granted: Array = []
	for core_id in INITIAL_PROXY_CORE_IDS:
		var item := _grant_proxy_core(core_id, String(_active_session.get("contract_id", "")))
		if not item.is_empty():
			granted.append(item)
	return granted


func _add_proxy_cores_to_inventory(inventory: Array, source_contract: String) -> Array:
	var granted: Array = []
	for core_id in INITIAL_PROXY_CORE_IDS:
		var item := _proxy_component_item(core_id, source_contract)
		if item.is_empty():
			continue
		var exists := false
		for owned in inventory:
			if owned is Dictionary and String((owned as Dictionary).get("id", "")) == core_id:
				exists = true
				break
		if not exists:
			inventory.append(item.duplicate(true))
		granted.append(item)
	return granted


func _grant_proxy_core(core_id: String, source_contract: String) -> Dictionary:
	if _owns_proxy_core(core_id):
		return {}
	var item := _proxy_component_item(core_id, source_contract)
	if item.is_empty():
		return {}
	((_profile.inventory as Dictionary).proxy_components as Array).append(item.duplicate(true))
	return item


func _proxy_component_item(core_id: String, source_contract: String) -> Dictionary:
	var registry: Variant = _loaded_content_registry()
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


func _safe_reward_delta(value: Variant) -> int:
	return int(value) if typeof(value) == TYPE_INT and int(value) >= 0 else 0


func _is_law_forge_unlocked() -> bool:
	var progress := campaign_progress_snapshot()
	return bool(progress.get("ok", false)) and "law_forge_unlock" in (progress.earned_reward_tags as Array)


func _default_forge_target_id(inventory_items: Array) -> String:
	var equipped: Dictionary = _profile.active_build.equipped_item_ids
	var main_hand_id := String(equipped.get("main_hand", ""))
	if not main_hand_id.is_empty():
		for item in inventory_items:
			if String((item as Dictionary).get("instance_id", "")) == main_hand_id:
				return main_hand_id
	return String((inventory_items[0] as Dictionary).get("instance_id", "")) if not inventory_items.is_empty() else ""


func _set_forge_context(target_id: String, operation: String) -> Dictionary:
	var item := _owned_equipment(target_id)
	if item.is_empty():
		return CoreResult.failure("item_not_owned")
	var affixes: Array = item.get("affixes", [])
	var affix_count := affixes.size()
	var blocked_reason := ""
	if operation == "inscribe":
		if affix_count >= LawForgeScript.MAX_AFFIXES:
			blocked_reason = "affix_limit_reached"
	elif operation in ["rewrite", "refine"]:
		if affix_count == 0:
			blocked_reason = "affix_required"
		elif operation == "rewrite":
			var registry: Variant = _loaded_item_registry()
			if registry == null or not bool(LawForgeScript.new(registry).validate_request(item, operation).get("ok", false)):
				blocked_reason = "rewrite_not_legal"
		elif operation == "refine":
			var has_eligible_affix := false
			for affix in affixes:
				if int((affix as Dictionary).get("tier", 0)) < LawForgeScript.MAX_TIER:
					has_eligible_affix = true
					break
			if not has_eligible_affix:
				blocked_reason = "max_tier"
	else:
		return CoreResult.failure("unknown_operation")
	var previous_revision := int(_forge_context.get("revision", 0))
	var changed := _forge_context.is_empty() \
		or String(_forge_context.get("target_instance_id", "")) != target_id \
		or String(_forge_context.get("operation", "")) != operation \
		or String(_forge_context.get("blocked_reason", "")) != blocked_reason
	if changed:
		_invalidate_forge_session()
		_forge_context = {
			"target_instance_id": target_id,
			"operation": operation,
			"blocked": not blocked_reason.is_empty(),
			"blocked_reason": blocked_reason,
			"revision": previous_revision + 1,
		}
	return {"ok": true, "context": _forge_context.duplicate(true)}


func _forge_item_view(item: Dictionary, registry: Variant) -> Dictionary:
	var view := item.duplicate(true)
	var base: Dictionary = registry.base_items.get(String(item.base_item_id), {})
	view["base_name"] = String(base.get("name", item.base_item_id))
	var visible_affixes: Array = []
	for raw_affix in (item.affixes as Array):
		var affix: Dictionary = raw_affix
		var family: Dictionary = registry.affix_families.get(String(affix.family_id), {})
		visible_affixes.append({
			"family_id": String(affix.family_id),
			"family_name": String(family.get("name", affix.family_id)),
			"tier": int(affix.tier),
		})
	view["affixes"] = visible_affixes
	return view


func _forge_session_view() -> Dictionary:
	if _forge_session.is_empty():
		return {
			"state": "idle",
			"session_id": "",
			"target_instance_id": "",
			"operation": "",
			"candidates": [],
			"selected_candidate_id": "",
			"revealed_count": 0,
			"affordable_count": 0,
			"has_more": false,
		}
	var view := _forge_session.duplicate(true)
	view.erase("target_item")
	var operation := String(view.get("operation", ""))
	var balance := int(((_profile.resources as Dictionary).law_tallies as Dictionary).get(operation, 0))
	var unique_count := int(view.get("unique_count", 0))
	var affordable_count := mini(balance, unique_count)
	view["revealed_count"] = (view.candidates as Array).size()
	view["affordable_count"] = affordable_count
	view["has_more"] = (view.candidates as Array).size() < affordable_count
	return view.duplicate(true)


func _selected_forge_candidate() -> Dictionary:
	var selected_id := String(_forge_session.get("selected_candidate_id", ""))
	for candidate_value in (_forge_session.get("candidates", []) as Array):
		var candidate: Dictionary = candidate_value
		if String(candidate.get("candidate_id", "")) == selected_id:
			return candidate.duplicate(true)
	return {}


func _enrich_forge_candidates(target_item: Dictionary, candidates: Array, registry: Variant) -> Array:
	var result: Array = candidates.duplicate(true)
	# Candidate result_item stays the exact LawForge authority payload. The sibling
	# view is deliberately presentation-only so validation and commit keep comparing
	# and applying the complete raw ItemInstance.
	for index in result.size():
		if not result[index] is Dictionary:
			continue
		var candidate: Dictionary = result[index]
		var result_item: Variant = candidate.get("result_item", {})
		if result_item is Dictionary:
			candidate["result_item_view"] = _forge_item_view(result_item as Dictionary, registry)
			result[index] = candidate
	var slot := String(target_item.get("slot", ""))
	if slot not in EarlyItemRegistryScript.PROTOTYPE_OPEN_SLOTS:
		return result
	var inventory: Array = ((_profile.inventory as Dictionary).equipment as Array).duplicate(true)
	var target_index := _equipment_index(inventory, String(target_item.get("instance_id", "")))
	if target_index < 0:
		return result
	var active_build: Dictionary = (_profile.active_build as Dictionary).duplicate(true)
	var equipped_ids: Variant = active_build.get("equipped_item_ids", {})
	if not equipped_ids is Dictionary:
		return result
	var target_is_equipped := String((equipped_ids as Dictionary).get(slot, "")) == String(target_item.get("instance_id", ""))
	var current_resolved := _resolve_build_with_inventory(active_build, inventory)
	if not bool(current_resolved.get("ok", false)):
		return result
	var current_parameters: Dictionary = (current_resolved.get("final_parameters", {}) as Dictionary).duplicate(true)
	var comparison_build: Dictionary = active_build.duplicate(true)
	if not target_is_equipped:
		(comparison_build.equipped_item_ids as Dictionary)[slot] = String(target_item.get("instance_id", ""))
	for index in result.size():
		if not result[index] is Dictionary:
			continue
		var candidate: Dictionary = result[index]
		var result_item: Variant = candidate.get("result_item", {})
		if not result_item is Dictionary:
			continue
		var result_inventory := inventory.duplicate(true)
		result_inventory[target_index] = (result_item as Dictionary).duplicate(true)
		var result_resolved := _resolve_build_with_inventory(comparison_build, result_inventory)
		if not bool(result_resolved.get("ok", false)):
			continue
		var result_parameters: Dictionary = (result_resolved.get("final_parameters", {}) as Dictionary).duplicate(true)
		candidate["target_is_equipped"] = target_is_equipped
		candidate["preview_impact"] = "current_build_immediate" if target_is_equipped else "equip_after_commit"
		var current_interfaces := _resolved_connected_interfaces(current_resolved)
		var result_interfaces := _resolved_connected_interfaces(result_resolved)
		candidate["build_comparison"] = {
			"current_parameters": current_parameters.duplicate(true),
			"result_parameters": result_parameters.duplicate(true),
			"interfaces_gained": Collections.string_array_difference(result_interfaces, current_interfaces),
			"interfaces_lost": Collections.string_array_difference(current_interfaces, result_interfaces),
		}
		result[index] = candidate
	return result


func _equipment_index(equipment: Array, instance_id: String) -> int:
	for index in equipment.size():
		if equipment[index] is Dictionary and String((equipment[index] as Dictionary).get("instance_id", "")) == instance_id:
			return index
	return -1


func _invalidate_forge_session() -> void:
	_forge_session.clear()
	_pending_forge_commit.clear()


func _has_exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key in expected:
		if not value.has(key):
			return false
	return true
