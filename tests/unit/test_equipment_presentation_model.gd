extends SceneTree

const ReadableScript = preload("res://src/presentation/player_readable_build.gd")
const ModelScript = preload("res://src/presentation/models/equipment_presentation_model.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var readable = ReadableScript.new()
	var model = ModelScript.new(readable, {
		"ashwood_longbow": {"name": "白蜡长弓", "modifiers": [{"parameter": "damage", "operation": "multiply", "value": 1.12}]},
	}, {
		"piercing_continuation": {"name": "穿刺箭续行概率"},
		"maximum_health": {"name": "最大生命"},
	}, {
		"salvage": {"ok": true, "operation": "refine", "amount": 2},
		"protected": {"ok": true, "operation": "rewrite", "amount": 1},
	})
	var inventory: Array[Dictionary] = [
		{"instance_id": "equipped", "base_item_id": "ashwood_longbow", "slot": "main_hand", "affixes": []},
		{"instance_id": "salvage", "base_item_id": "ashwood_longbow", "slot": "main_hand", "affixes": [{"family_id": "maximum_health", "tier": 3}], "rune_id": ""},
		{"instance_id": "review", "name": "显式名称", "base_item_id": "unknown", "slot": "main_hand", "affixes": [{"family_id": "piercing_continuation", "tier": 2}], "rune_id": "breeding_split", "law_id": ""},
		{"instance_id": "other", "base_item_id": "unknown", "slot": "off_hand", "affixes": []},
	]
	var candidates := model.same_slot_candidates("main_hand", "equipped", inventory)
	_expect(candidates.size() == 2, "same-slot query included another slot or the equipped item", failures)
	var filtered := model.filter_sort(candidates, {"keyword": "续行", "sort": "highest_tier", "reviewed_instance_id": "review"})
	_expect(filtered.size() == 1 and String(filtered[0].get("instance_id")) == "review", "filter/sort query lost keyword match or review pinning", failures)
	var tier_sorted := model.filter_sort(candidates, {"sort": "highest_tier"})
	_expect(String(tier_sorted[0].get("instance_id")) == "salvage", "highest-tier sort did not rank T3 first", failures)
	var rune_only := model.filter_sort(candidates, {"requires_rune": true})
	_expect(rune_only.size() == 1 and rune_only[0].instance_id == "review", "rune filter admitted an item without a rune", failures)
	_expect(model.filter_sort(candidates, {"requires_law": true}).is_empty(), "law filter admitted an item without a law", failures)
	var salvage := model.filter_sort(candidates, {"requires_salvage": true})
	_expect(salvage.size() == 1 and String(salvage[0].get("instance_id")) == "salvage", "salvage query did not use the authoritative preview", failures)
	_expect(String(model.display_name(inventory[2])) == "显式名称" and String(model.display_name(inventory[0])) == "白蜡长弓", "display-name precedence is wrong", failures)
	_expect(model.compact_difference(inventory[2]).contains("穿刺箭续行概率") and not model.compact_difference(inventory[2]).contains("breeding_split"), "compact difference leaked a raw id", failures)
	_expect(model.current_inline_summary(inventory[0]).contains("主手 · 底材 白蜡长弓") and model.current_inline_summary(inventory[0]).contains("载体伤害：×1.12"), "current inline summary lost slot/base/effect: " + model.current_inline_summary(inventory[0]), failures)
	_expect(model.candidate_inline_facts(inventory[1]).contains("最大生命 III 阶"), "candidate inline facts lost named affix", failures)
	var drop := inventory[2].duplicate(true)
	drop["instance_id"] = "drop_full_id"
	drop["current_parameters"] = {"damage": 100.0}
	drop["equipped_parameters"] = {"damage": 112.0}
	_expect(model.result_face(drop).contains("主手 · 收入库存") and model.result_face(drop).contains("穿刺箭续行概率 II 阶"), "settlement face lost shared slot/affix data", failures)
	_expect(model.result_full(drop).contains("当前值 → 装备后值") and model.result_full(drop).contains("载体伤害"), "settlement full text lost shared readable build data", failures)
	var audit := model.result_audit(drop)
	_expect(audit.contains("ID: drop_full_id") and audit.contains("piercing_continuation T2") and audit.contains("符文: breeding_split"), "settlement audit lost authoritative fields: " + audit, failures)
	if failures.is_empty():
		print("PASS  test_equipment_presentation_model.gd")
		quit(0)
		return
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
