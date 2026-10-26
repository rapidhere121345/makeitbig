class_name ApplicationState
extends RefCounted

## Profile/progression authority. This owner keeps the profile, the contract
## and session lifecycle and the public API; the domain logic lives in the
## src/game/application collaborators. Stateless domains are static modules fed
## the live profile dictionary; ForgeSessions owns the transient forge state.
const TalentBuildScript = preload("res://src/systems/talent_build.gd")
const CharacterProgressionScript = preload("res://src/systems/character_progression.gd")
const BuildResolverScript = preload("res://src/systems/build_resolver.gd")
const TrainingReportBuilderScript = preload("res://src/systems/training_report_builder.gd")
const CoreResult := preload("res://src/core/result.gd")
const ProfileRules := preload("res://src/game/application/profile_rules.gd")
const ProfileCodec := preload("res://src/game/application/profile_codec.gd")
const BuildResolution := preload("res://src/game/application/build_resolution.gd")
const ProxyBuilds := preload("res://src/game/application/proxy_builds.gd")
const EquipmentOps := preload("res://src/game/application/equipment_ops.gd")
const CampaignProgress := preload("res://src/game/application/campaign_progress.gd")
const ForgeSessions := preload("res://src/game/application/forge_sessions.gd")
const RoomDropSettlement := preload("res://src/game/application/room_drop_settlement.gd")
const ResultProgression := preload("res://src/game/application/result_progression.gd")
const BossDiagnosis := preload("res://src/game/application/boss_diagnosis.gd")

const SCHEMA_VERSION := ProfileRules.SCHEMA_VERSION
const PROFILE_SCHEMA_VERSION := SCHEMA_VERSION
const SUPPORTED_CLASSES := ProfileCodec.SUPPORTED_CLASSES
const SUPPORTED_MODES := ["Manual", "Auto"]
const SAFE_ROUTES := ProfileCodec.SAFE_ROUTES
const MAX_SAFE_JSON_INTEGER := 9007199254740991
const ROOM_EQUIPMENT_DROP_INDEX := RoomDropSettlement.ROOM_EQUIPMENT_DROP_INDEX
const SALVAGE_REFUND_TALLIES := EquipmentOps.SALVAGE_REFUND_TALLIES
const FORGE_OPERATIONS := ProfileRules.FORGE_OPERATIONS
const DEFAULT_RANGER_PRESET := BuildResolution.DEFAULT_RANGER_PRESET
const LEGACY_RANGER_PRESET := BuildResolution.LEGACY_RANGER_PRESET
const BOSS_DIAGNOSIS_CONTRACT_ID := BossDiagnosis.BOSS_DIAGNOSIS_CONTRACT_ID
const BOSS_DIAGNOSIS_MODE := BossDiagnosis.BOSS_DIAGNOSIS_MODE
const BOSS_DIAGNOSIS_RANGE_MIN := BossDiagnosis.BOSS_DIAGNOSIS_RANGE_MIN
const BOSS_DIAGNOSIS_LIFETIME_MIN := BossDiagnosis.BOSS_DIAGNOSIS_LIFETIME_MIN
const PITY_SIDE_CONTRACT_ID := RoomDropSettlement.PITY_SIDE_CONTRACT_ID
const PITY_TRIGGER_PERIOD := RoomDropSettlement.PITY_TRIGGER_PERIOD
const PITY_EXPONENTIAL_P_THRESHOLD := RoomDropSettlement.PITY_EXPONENTIAL_P_THRESHOLD
const PITY_TARGET_GROWTH := RoomDropSettlement.PITY_TARGET_GROWTH
const PITY_TARGET_RANGE := RoomDropSettlement.PITY_TARGET_RANGE
const PITY_TARGET_LIFETIME := RoomDropSettlement.PITY_TARGET_LIFETIME
const PITY_TARGET_POWER := RoomDropSettlement.PITY_TARGET_POWER
const BOSS_BOTTLENECK_GROWTH_CONVERGENT := BossDiagnosis.BOSS_BOTTLENECK_GROWTH_CONVERGENT
const BOSS_BOTTLENECK_GROWTH_CRITICAL := BossDiagnosis.BOSS_BOTTLENECK_GROWTH_CRITICAL
const BOSS_BOTTLENECK_TARGETING_RANGE_SHORT := BossDiagnosis.BOSS_BOTTLENECK_TARGETING_RANGE_SHORT
const BOSS_BOTTLENECK_PROJECTILE_LIFETIME_SHORT := BossDiagnosis.BOSS_BOTTLENECK_PROJECTILE_LIFETIME_SHORT
const BOSS_BOTTLENECK_BOSS_PATTERN_SURVIVAL := BossDiagnosis.BOSS_BOTTLENECK_BOSS_PATTERN_SURVIVAL
const PRESET_FIXTURES := BuildResolution.PRESET_FIXTURES
const INITIAL_PROXY_CORE_IDS := ProxyBuilds.INITIAL_PROXY_CORE_IDS
const AUTO_PROXY_REWARD_IDS := ProxyBuilds.AUTO_PROXY_REWARD_IDS
const PROXY_CORE_CATALOG_IDS := ProxyBuilds.PROXY_CORE_CATALOG_IDS
const STABLE_FIRST_REWARD_ITEMS := ResultProgression.STABLE_FIRST_REWARD_ITEMS

var _profile: Dictionary = {}
var _pending_contract: Dictionary = {}
var _active_session: Dictionary = {}
var _last_result: Dictionary = {}
var _forge := ForgeSessions.new()

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
	_forge.clear()


func has_profile() -> bool:
	return not _profile.is_empty()


func start_new_profile(initial_class: String = "ranger") -> Dictionary:
	var normalized_class := initial_class.strip_edges().to_lower()
	if normalized_class not in SUPPORTED_CLASSES:
		return CoreResult.failure("invalid_class")
	var initial := BuildResolution.fixture_state(DEFAULT_RANGER_PRESET)
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
	_forge.clear()
	return {"ok": true, "profile": _profile.duplicate(true)}


func complete_tutorial() -> Dictionary:
	if not has_profile():
		return CoreResult.failure("profile_required")
	var first := not bool(_profile.get("tutorial_complete", false))
	_profile["tutorial_complete"] = true
	CampaignProgress.record_completed_node(_profile, "tutorial_ranger_basics")
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


func growth_snapshot() -> Dictionary:
	var reading := character_snapshot()
	if reading.is_empty(): return {}
	var compiler := TalentBuildScript.new()
	var context := BuildResolution.talent_context(_profile)
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
	return CampaignProgress.story_progress_for(_profile)


func story_snapshot() -> Dictionary:
	return CampaignProgress.story_snapshot(_profile)


func mark_story_read(entry_id: String) -> Dictionary:
	return CampaignProgress.mark_story_read(_profile, _active_session, entry_id)


func _apply_experience(amount: int) -> Dictionary:
	var change := CharacterProgressionScript.award(_profile.character, amount)
	_profile["character"] = (change.character as Dictionary).duplicate(true)
	return change


func select_ranger_build(preset_id: String) -> Dictionary:
	if not has_profile():
		return CoreResult.failure("profile_required")
	var fixture_id := BuildResolution.fixture_id_for_legacy_name(preset_id)
	if fixture_id.is_empty() or fixture_id == "fixed_start":
		return CoreResult.failure("unknown_preset")
	var selected := BuildResolution.fixture_state(fixture_id)
	if selected.is_empty():
		return CoreResult.failure("content_unavailable")
	EquipmentOps.merge_equipment_inventory(_profile, selected.equipment)
	_profile["active_build"] = selected.active_build
	return active_build_snapshot()


func active_build_snapshot() -> Dictionary:
	if not has_profile():
		return CoreResult.failure("profile_required")
	var snapshot: Dictionary = (_profile.active_build as Dictionary).duplicate(true)
	var preset_id := BuildResolution.legacy_preset_for_active_build(snapshot)
	snapshot["preset_id"] = preset_id
	if preset_id in ["convergent", "critical", "exponential"]:
		var legacy := BuildResolution.legacy_build_from_preset(preset_id)
		if not legacy.is_empty():
			snapshot["equipment"] = legacy.equipment
	var resolved := BuildResolution.resolve_active_build(_profile, snapshot)
	if bool(resolved.get("ok", false)):
		snapshot["runes"] = (resolved.rune_ids as Array).duplicate()
		snapshot["laws"] = (resolved.law_ids as Array).duplicate()
	return {"ok": true, "active_build": snapshot}


func resolved_build_snapshot() -> Dictionary:
	if not has_profile():
		return CoreResult.failure("profile_required")
	return BuildResolution.resolve_active_build(_profile, (_profile.active_build as Dictionary).duplicate(true))


func resolved_proxy_build_snapshot() -> Dictionary:
	return ProxyBuilds.resolved_snapshot(_profile)


func equip_proxy_core(core_id: String) -> Dictionary:
	return ProxyBuilds.equip_core(_profile, core_id)


func configure_proxy_core(core_id: String, settings: Dictionary) -> Dictionary:
	return ProxyBuilds.configure_core(_profile, core_id, settings)


func equip_item(instance_id: String) -> Dictionary:
	return EquipmentOps.equip_item(_profile, instance_id)


## Read-only "try-on" preview for FacilityScreen's equip_previews contract; see
## EquipmentOps.preview_equip_item. Nothing is persisted.
func preview_equip_item(instance_id: String) -> Dictionary:
	return EquipmentOps.preview_equip_item(_profile, instance_id)


func salvage_item_preview(instance_id: String) -> Dictionary:
	return EquipmentOps.salvage_item_preview(_profile, instance_id)


func salvage_item(instance_id: String) -> Dictionary:
	var salvaged := EquipmentOps.salvage_item(_profile, instance_id)
	if bool(salvaged.get("ok", false)):
		_forge.invalidate_session()
	return salvaged


func unequip_item(slot: String) -> Dictionary:
	return EquipmentOps.unequip_item(_profile, slot)


func early_game_snapshot() -> Dictionary:
	if not has_profile():
		return CoreResult.failure("profile_required")
	var registry: Variant = ProfileRules.loaded_content_registry()
	var item_registry: Variant = ProfileRules.loaded_item_registry()
	if registry == null or item_registry == null:
		return CoreResult.failure("content_unavailable")
	var available: Array = []
	var selected_id := BuildResolution.legacy_preset_for_active_build(_profile.active_build)
	var reports_by_fingerprint: Dictionary = (_profile.training as Dictionary).reports_by_fingerprint
	for preset_index in registry.preset_order.size():
		var preset_id: String = registry.preset_order[preset_index]
		var preset: Dictionary = registry.presets[preset_id]
		var fixture_id := BuildResolution.fixture_id_for_legacy_name(preset_id)
		var fingerprint := BuildResolution.fingerprint_for_fixture(_profile, fixture_id)
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
			"catalog": ProxyBuilds.catalog_snapshot(registry.cores),
			"resolved_build": (proxy_resolved.get("resolved_proxy_build", {}) as Dictionary).duplicate(true) if bool(proxy_resolved.get("ok", false)) else {},
		},
		"progression": (_profile.progression as Dictionary).duplicate(true),
	}.duplicate(true)


func campaign_progress_snapshot() -> Dictionary:
	return CampaignProgress.campaign_snapshot(_profile)


func run_training_trial() -> Dictionary:
	if not has_profile():
		return CoreResult.failure("profile_required")
	var resolved := resolved_build_snapshot()
	if not bool(resolved.get("ok", false)):
		return CoreResult.failure("invalid_active_build")
	var preset_id := BuildResolution.legacy_preset_for_active_build(_profile.active_build)
	var fingerprint := String(resolved.build_fingerprint)
	var report: Dictionary = TrainingReportBuilderScript.build_report(resolved, preset_id)
	var training: Dictionary = _profile.training
	var reports_by_fingerprint: Dictionary = training.reports_by_fingerprint
	reports_by_fingerprint[fingerprint] = report.duplicate(true)
	CampaignProgress.record_growth_discovery(_profile, report)
	CampaignProgress.refresh_early_game_completion(_profile)
	return {"ok": true, "report": report.duplicate(true)}


func is_auto_mode_unlocked() -> bool:
	return has_profile() and bool((_profile.progression as Dictionary).get("proxy_unlocked", false))


func forge_ensure_context() -> Dictionary:
	return _forge.ensure_context(self)


func forge_select_target(instance_id: String, expected_revision: int = -1) -> Dictionary:
	return _forge.select_target(self, instance_id, expected_revision)


func forge_select_operation(operation: String, expected_revision: int = -1) -> Dictionary:
	return _forge.select_operation(self, operation, expected_revision)


func forge_snapshot() -> Dictionary:
	return _forge.snapshot(self)


func forge_reveal(limit: int = 8, expected_revision: int = -1) -> Dictionary:
	return _forge.reveal(self, limit, expected_revision)


func forge_reveal_more(session_id: String, limit: int = 8) -> Dictionary:
	return _forge.reveal_more(self, session_id, limit)


func forge_select_candidate(session_id: String, candidate_id: String) -> Dictionary:
	return _forge.select_candidate(self, session_id, candidate_id)


func forge_cancel(session_id: String = "") -> Dictionary:
	return _forge.cancel(self, session_id)


func forge_prepare_commit(session_id: String) -> Dictionary:
	return _forge.prepare_commit(self, session_id)


func forge_finalize_commit(commit_token: String) -> Dictionary:
	return _forge.finalize_commit(self, commit_token)


func forge_abort_commit(commit_token: String) -> Dictionary:
	return _forge.abort_commit(self, commit_token)


func prepare_contract(config: Dictionary) -> Dictionary:
	if not has_profile():
		return CoreResult.failure("profile_required")
	if not _active_session.is_empty():
		return CoreResult.failure("active_session_exists")
	var contract_id_value: Variant = config.get("contract_id", "")
	if not ProfileRules.is_text(contract_id_value):
		return CoreResult.failure("invalid_contract_id")
	var contract_id := String(contract_id_value).strip_edges()
	if contract_id.is_empty():
		return CoreResult.failure("invalid_contract_id")
	var mode_value: Variant = config.get("mode", "")
	if not ProfileRules.is_text(mode_value):
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
	var registry: Variant = ProfileRules.loaded_item_registry()
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
		if not ProfileRules.owned_equipment(_profile, String(item.get("instance_id", ""))).is_empty():
			continue
		equipment.append(item.duplicate(true))
		committed.append(item.duplicate(true))
	var resolved := BuildResolution.resolve_with_inventory(
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
	if ResultProgression.is_auto_certification_graduation(_profile, _active_session, _last_result):
		_last_result["outcome"] = "final_victory"
	RoomDropSettlement.settle_room_equipment_drops(_profile, _active_session, _last_result)
	var first_clear := String(_active_session.get("contract_id", "")) not in (_profile.progression.completed_node_ids as Array)
	ResultProgression.apply_result_progression(_profile, _active_session, _last_result)
	ResultProgression.record_story_result_evidence(_profile, _active_session, _last_result)
	var xp := 0
	if String(_last_result.get("outcome", "")) in ["victory", "final_victory"]:
		xp = CharacterProgressionScript.contract_experience(String(_active_session.get("contract_id", "")), first_clear)
	_last_result["character_growth"] = _apply_experience(xp)
	BossDiagnosis.attach_defeat_diagnosis(_active_session, _last_result)
	_active_session.clear()
	_pending_contract.clear()
	return {"ok": true, "result": _last_result.duplicate(true)}


func abandon_session() -> void:
	_pending_contract.clear()
	_active_session.clear()


func persistent_payload(safe_route: String = "base") -> Dictionary:
	return ProfileCodec.payload_for_profile(_profile, _last_result, safe_route)


func restore_persistent_payload(payload: Variant) -> Dictionary:
	var parsed := ProfileCodec.parse_payload(payload)
	if not bool(parsed.get("ok", false)):
		return parsed
	_profile = (parsed.profile as Dictionary).duplicate(true)
	_last_result = (parsed.last_result as Dictionary).duplicate(true)
	_pending_contract.clear()
	_active_session.clear()
	_forge.clear()
	return {"ok": true, "route": String(parsed.route)}


func _normalize_mode(value: String) -> String:
	match value.strip_edges().to_lower():
		"manual":
			return "Manual"
		"auto":
			return "Auto"
	return ""
