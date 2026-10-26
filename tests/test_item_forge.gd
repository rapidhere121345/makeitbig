extends SceneTree

const LawForgeScript = preload("res://src/systems/law_forge.gd")
const EarlyItemRegistryScript = preload("res://src/content/early_item_registry.gd")
const Assert := preload("res://tests/helpers/assert.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var registry := EarlyItemRegistryScript.new()
	_expect(registry.load_all().is_empty(), "law forge: registry did not load", failures)
	var forge := LawForgeScript.new(registry)
	var item: Dictionary = registry.item_instances.fixed_start_main_hand.duplicate(true)
	var original := item.duplicate(true)
	var first := forge.reveal(item, "inscribe", 0, 8, "session-a")
	var second := forge.reveal(item, "inscribe", 0, 8, "session-a")
	_expect(first == second and first.candidates.size() == mini(8, int(first.unique_count)), "law forge: identical reveal was not deterministic", failures)
	var candidate: Dictionary = first.candidates[mini(4, first.candidates.size() - 1)]
	_expect(candidate.sequence_number == candidate.choice_number and candidate.cost == candidate.choice_number and candidate.result_item.affixes.size() == 1,
		"law forge: sequence cost or full result_item is wrong", failures)
	_expect(String(candidate.candidate_id).length() == 64 and String(candidate.quote_id).length() == 64,
		"law forge: candidate/quote ids are not opaque hashes", failures)
	_expect(not candidate.has("affix_index") and int(candidate.affected_affix_index) == item.affixes.size(),
		"law forge: candidate retained player-selected affix state", failures)
	_expect(bool(forge.validate_candidate(item, "inscribe", candidate, "session-a").get("ok", false)),
		"law forge: authentic candidate was rejected", failures)
	var tampered := candidate.duplicate(true)
	tampered.result_item.affixes[0].tier = int(tampered.result_item.affixes[0].tier) + 1
	_expect(String(forge.validate_candidate(item, "inscribe", tampered, "session-a").get("error", "")) == "stale_candidate",
		"law forge: tampered result_item was accepted", failures)
	_expect(String(forge.validate_candidate(item, "inscribe", candidate, "session-b").get("error", "")) == "stale_candidate",
		"law forge: candidate from another quote was accepted", failures)
	var page_two := forge.reveal(item, "inscribe", 1, 8, "session-a")
	_expect(page_two.candidates[0].sequence_number == 2 and page_two.candidates[0].cost == 2,
		"law forge: pagination reset the global sequence", failures)
	var all_results := forge.reveal(item, "inscribe", 0, 100, "session-a")
	var paged_candidates: Array = []
	var page_offset := 0
	while true:
		var page := forge.reveal(item, "inscribe", page_offset, 3, "session-a")
		paged_candidates.append_array(page.candidates as Array)
		if (page.candidates as Array).is_empty():
			break
		page_offset = int(page.next_offset)
	_expect(paged_candidates == all_results.candidates,
		"law forge: paged candidates diverged from the complete unique result list", failures)
	var semantic_results := {}
	for result_candidate_value in paged_candidates:
		var result_candidate: Dictionary = result_candidate_value
		var semantic_key := JSON.stringify({
			"instance_id": String(result_candidate.result_item.instance_id),
			"base_item_id": String(result_candidate.result_item.base_item_id),
			"slot": String(result_candidate.result_item.slot),
			"affixes": result_candidate.result_item.affixes,
			"rune_id": String(result_candidate.result_item.rune_id),
			"law_id": String(result_candidate.result_item.law_id),
		}, "", true)
		_expect(not semantic_results.has(semantic_key), "law forge: semantically identical results received multiple prices", failures)
		semantic_results[semantic_key] = int(result_candidate.cost)
	var refine_item: Dictionary = registry.item_instances.calibration_exponential_main_hand.duplicate(true)
	var refine := forge.reveal(refine_item, "refine", 0, 8, "session-refine")
	_expect(bool(refine.get("ok", false)) and int(refine.unique_count) == 1 and refine.candidates.size() == 1
		and int((refine.candidates[0] as Dictionary).result_item.affixes[0].tier) == 4
		and String((refine.candidates[0] as Dictionary).result_item.instance_id) == String(refine_item.instance_id),
		"law forge: T3 refine did not expose exactly one in-place T4 result", failures)
	_expect(item == original, "law forge: pure calculation mutated input", failures)
	var multi_affix := refine_item.duplicate(true)
	multi_affix.affixes.append({"family_id": "projectile_speed", "tier": 1})
	var rewrite := forge.reveal(multi_affix, "rewrite", 0, 100, "session-rewrite")
	var affected_slots := {}
	for raw_rewrite in (rewrite.get("candidates", []) as Array):
		var rewrite_candidate: Dictionary = raw_rewrite
		affected_slots[int(rewrite_candidate.affected_affix_index)] = true
		_expect(bool(forge.validate_candidate(multi_affix, "rewrite", rewrite_candidate, "session-rewrite").get("ok", false)),
			"law forge: deterministic complete rewrite result failed validation", failures)
	_expect(bool(rewrite.get("ok", false)) and affected_slots.has(0) and affected_slots.has(1),
		"law forge: rewrite futures did not deterministically cover automatic affix choices", failures)
	var mixed_refine := multi_affix.duplicate(true)
	(mixed_refine.affixes[0] as Dictionary)["tier"] = LawForgeScript.MAX_TIER
	var eligible_refine := forge.reveal(mixed_refine, "refine", 0, 100, "session-eligible-refine")
	for raw_refine in (eligible_refine.get("candidates", []) as Array):
		var refine_candidate: Dictionary = raw_refine
		_expect(int(refine_candidate.affected_affix_index) == 1
			and String(refine_candidate.family_id) == "projectile_speed"
			and int(refine_candidate.tier) > 1,
			"law forge: refine future chose an ineligible affix or changed its family", failures)
	_expect(String(forge.reveal(item, "rewrite").get("error", "")) == "affix_required", "law forge: rewrite without an affix was accepted", failures)
	_expect(String(forge.reveal(item, "inscribe", -1).get("error", "")) == "invalid_page", "law forge: invalid reveal page was accepted", failures)
	_finish(failures)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("PASS  test_item_forge.gd")
		quit(0)
		return
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _expect(condition: bool, message: String, failures: Array[String]) -> void: Assert.expect(condition, message, failures)
