class_name ContractPlan
extends RefCounted

const DeterministicRng = preload("res://src/core/deterministic_rng.gd")
const EarlyCampaignRegistryScript = preload("res://src/content/early_campaign_registry.gd")

const layouts: Array[String] = [
	"arena",
	"corridor",
	"cross",
	"ring",
	"twin_islands",
	"concentric",
	"fork",
]
const objectives: Array[String] = ["clear", "hold", "hunt_elite", "timed_break"]
const drop_tags: Array[String] = ["projectile_law", "toxic_parameter", "proxy_memory", "inscribe_tally", "rewrite_tally", "refine_tally"]
const risk_tags: Array[String] = ["swarm", "control", "elite", "environment"]


static func build(config: Dictionary) -> Dictionary:
	var raw_contract_id: Variant = config.get("contract_id")
	if typeof(raw_contract_id) != TYPE_STRING and typeof(raw_contract_id) != TYPE_STRING_NAME:
		return {"ok": false, "error": "invalid_contract_id"}
	var contract_id := String(raw_contract_id).strip_edges()
	if contract_id.is_empty():
		return {"ok": false, "error": "invalid_contract_id"}

	var raw_seed: Variant = config.get("seed")
	if typeof(raw_seed) != TYPE_INT:
		return {"ok": false, "error": "invalid_seed"}
	var seed: int = raw_seed

	var campaign_result := _build_early_campaign_contract(contract_id, seed, config)
	if not bool(campaign_result.get("not_found", false)):
		return campaign_result

	var raw_room_count: Variant = config.get("room_count")
	if typeof(raw_room_count) != TYPE_INT:
		return {"ok": false, "error": "invalid_room_count"}
	var room_count: int = raw_room_count
	var is_first_contract_single_room := contract_id == "first_contract" and room_count == 1
	if not is_first_contract_single_room and (room_count < 6 or room_count > 12):
		return {"ok": false, "error": "invalid_room_count"}

	var rng = DeterministicRng.create(seed, "contract_plan/%s" % contract_id)
	var rooms: Array[Dictionary] = []
	for index in range(room_count):
		var is_boss := index == room_count - 1
		var room_id := "contract_plan/%s/%s/room_%02d" % [contract_id, str(seed), index]
		var room := {
			"index": index,
			"room_id": room_id,
			"layout": layouts[rng.next_int(layouts.size())],
			"objective": "hunt_elite" if is_boss else objectives[rng.next_int(objectives.size())],
			"drop_tag": drop_tags[rng.next_int(drop_tags.size())],
			"risk_tag": risk_tags[rng.next_int(risk_tags.size())],
			"is_boss": is_boss,
		}
		if not is_boss and (index + 1) % 3 == 0:
			room["branches"] = _build_branches(rng, room_id)
		rooms.append(room)

	var plan := {
		"version": 1,
		"contract_id": contract_id,
		"seed": seed,
		"room_count": room_count,
		"rooms": rooms,
	}
	return {"ok": true, "plan": plan.duplicate(true)}


static func _build_early_campaign_contract(contract_id: String, seed: int, config: Dictionary) -> Dictionary:
	var registry = EarlyCampaignRegistryScript.new()
	var load_errors: Array[String] = registry.load_campaign()
	if not load_errors.is_empty():
		return {"ok": false, "error": "campaign_content_invalid", "details": load_errors.duplicate()}
	var node: Dictionary = registry.get_node(contract_id)
	if node.is_empty():
		return {"not_found": true}
	var mode_value: Variant = config.get("mode", "Manual")
	if typeof(mode_value) != TYPE_STRING and typeof(mode_value) != TYPE_STRING_NAME:
		return {"ok": false, "error": "invalid_mode"}
	var mode := String(mode_value)
	if mode not in (node.allowed_modes as Array):
		return {"ok": false, "error": "mode_not_allowed"}
	if config.has("completed_node_ids"):
		var completed_value: Variant = config.completed_node_ids
		if not completed_value is Array:
			return {"ok": false, "error": "invalid_completed_node_ids"}
		if not registry.is_unlocked(contract_id, completed_value as Array, mode):
			return {"ok": false, "error": "contract_locked"}

	var source_rooms: Array = []
	if String(node.kind) == "side_template":
		var branch: Dictionary = registry.instantiate_branch(contract_id, seed, mode)
		if not bool(branch.get("ok", false)):
			return branch
		source_rooms = (branch.plan.rooms as Array).duplicate(true)
	else:
		source_rooms = (node.room_sequence as Array).duplicate(true)
	var rooms: Array[Dictionary] = []
	for index in source_rooms.size():
		var source: Dictionary = source_rooms[index]
		var room_id := String(source.get("id", "%s/%s/room_%02d" % [contract_id, str(seed), index]))
		var drop_tags_value: Variant = source.get("drop_tags", [])
		var drop_tags_for_room: Array = (drop_tags_value as Array).duplicate() if drop_tags_value is Array else []
		var boss_id := String(source.get("boss_id", ""))
		var layout_id := String(source.get("layout_id", "rectangle_arena"))
		var layout_info := registry.layout_info(layout_id)
		rooms.append({
			"index": index,
			"room_id": room_id,
			"layout": layout_id,
			"layout_id": layout_id,
			"display_name": String(layout_info.get("display_name", layout_id)),
			"concept": String(layout_info.get("concept", "")),
			"landmark": String(layout_info.get("landmark", "")),
			"entry_hint": String(layout_info.get("entry_hint", "")),
			"exit_hint": String(layout_info.get("exit_hint", "")),
			"objective": String(source.get("objective_id", "clear")),
			"objective_id": String(source.get("objective_id", "clear")),
			"hazard_ids": (source.get("hazard_ids", []) as Array).duplicate(),
			# Preserve roster multiplicity and order; these are kind references, not entity IDs.
			"enemy_ids": (source.get("enemy_ids", []) as Array).duplicate(),
			"elite_rule_ids": (source.get("elite_rule_ids", []) as Array).duplicate(),
			"boss_id": boss_id,
			"drop_tags": drop_tags_for_room,
			"drop_tag": String(drop_tags_for_room[0]) if not drop_tags_for_room.is_empty() else "",
			"new_problem_id": String(source.get("new_problem_id", "")),
			"is_boss": not boss_id.is_empty(),
		})
	var plan := {
		"version": 2,
		"source": "early_campaign",
		"contract_id": contract_id,
		"kind": String(node.kind),
		"mode": mode,
		"seed": seed,
		"room_count": rooms.size(),
		"repeatable": bool(node.repeatable),
		"first_reward_tags": (node.first_reward_tags as Array).duplicate(),
		"rooms": rooms,
	}
	return {"ok": true, "plan": plan.duplicate(true)}


static func _build_branches(rng: DeterministicRng, room_id: String) -> Array[Dictionary]:
	var first_drop_index := rng.next_int(drop_tags.size())
	var first_risk_index := rng.next_int(risk_tags.size())
	var second_drop_index := rng.next_int(drop_tags.size())
	var second_risk_index := rng.next_int(risk_tags.size())
	if first_drop_index == second_drop_index and first_risk_index == second_risk_index:
		second_risk_index = (second_risk_index + 1) % risk_tags.size()
	return [
		{
			"id": "%s/branch_a" % room_id,
			"drop_tag": drop_tags[first_drop_index],
			"risk_tag": risk_tags[first_risk_index],
		},
		{
			"id": "%s/branch_b" % room_id,
			"drop_tag": drop_tags[second_drop_index],
			"risk_tag": risk_tags[second_risk_index],
		},
	]
