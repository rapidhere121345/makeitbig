class_name LawForge
extends RefCounted

## Pure deterministic forging authority over real ItemInstance snapshots.

const OPERATIONS: Array[String] = ["inscribe", "rewrite", "refine"]
const MAX_AFFIXES := 4
const MAX_TIER := 4

var registry


func _init(item_registry) -> void:
	registry = item_registry


func reveal(item: Variant, operation: String, offset: int = 0, limit: int = 3, quote_nonce: String = "") -> Dictionary:
	var validation := validate_request(item, operation)
	if not bool(validation.get("ok", false)):
		return validation
	if offset < 0 or limit < 0:
		return _failure("invalid_page")
	var unique_results := _ordered_unique_results(item as Dictionary, operation)
	var candidates: Array[Dictionary] = []
	for result_index in range(offset, mini(offset + limit, unique_results.size())):
		var future: Dictionary = unique_results[result_index]
		candidates.append(_candidate(item as Dictionary, operation, int(future.affected_affix_index), result_index + 1, quote_nonce, future.result_item))
	return {
		"ok": true,
		"operation": operation,
		"offset": offset,
		"next_offset": offset + candidates.size(),
		"unique_count": unique_results.size(),
		"candidates": candidates.duplicate(true),
	}


func validate_candidate(item: Variant, operation: String, candidate: Variant, quote_nonce: String) -> Dictionary:
	var request_validation := validate_request(item, operation)
	if not bool(request_validation.get("ok", false)):
		return request_validation
	if not candidate is Dictionary:
		return _failure("invalid_candidate")
	var choice_number := int((candidate as Dictionary).get("choice_number", 0))
	if choice_number < 1:
		return _failure("invalid_candidate")
	var unique_results := _ordered_unique_results(item as Dictionary, operation)
	if choice_number > unique_results.size():
		return _failure("stale_candidate")
	var future: Dictionary = unique_results[choice_number - 1]
	var expected := _candidate(item as Dictionary, operation, int(future.affected_affix_index), choice_number, quote_nonce, future.result_item)
	if expected.is_empty() or not _same_candidate(expected, candidate as Dictionary):
		return _failure("stale_candidate")
	return {"ok": true, "candidate": expected.duplicate(true)}


func validate_request(item: Variant, operation: String) -> Dictionary:
	if registry == null or not registry.has_method("validate_item_instance"):
		return _failure("invalid_item")
	if not item is Dictionary or not registry.validate_item_instance(item).is_empty():
		return _failure("invalid_item")
	if operation not in OPERATIONS:
		return _failure("unknown_operation")
	var affixes: Array = (item as Dictionary).affixes
	if operation == "inscribe":
		if affixes.size() >= MAX_AFFIXES or _legal_families(item as Dictionary, -1).is_empty():
			return _failure("inscribe_not_legal")
		return {"ok": true}
	if affixes.is_empty():
		return _failure("affix_required")
	if operation == "rewrite":
		for affix_index in affixes.size():
			if not _legal_rewrite_families(item as Dictionary, affix_index).is_empty():
				return {"ok": true}
		return _failure("rewrite_not_legal")
	if operation == "refine":
		for affix in affixes:
			if int((affix as Dictionary).tier) < MAX_TIER:
				return {"ok": true}
		return _failure("refine_not_legal")
	return {"ok": true}


func _candidate(item: Dictionary, operation: String, affix_index: int, choice_number: int, quote_nonce: String, result_item: Dictionary) -> Dictionary:
	var result_affix: Dictionary = (result_item.affixes as Array)[affix_index if operation != "inscribe" else (result_item.affixes as Array).size() - 1]
	var family_id := String(result_affix.family_id)
	var tier := int(result_affix.tier)
	var target_fingerprint := _item_fingerprint(item)
	var result_fingerprint := _item_fingerprint(result_item)
	var candidate_id := ("%s|%s|%d|%d|%s" % [target_fingerprint, operation, affix_index, choice_number, result_fingerprint]).sha256_text()
	var quote_id := "%s|%s" % [quote_nonce, candidate_id]
	quote_id = quote_id.sha256_text()
	var family: Dictionary = registry.affix_families[family_id]
	return {
		"candidate_id": candidate_id,
		"quote_id": quote_id,
		"sequence_number": choice_number,
		"choice_number": choice_number,
		"cost": choice_number,
		"operation": operation,
		"affected_affix_index": affix_index,
		"previous_family_id": String(((item.affixes as Array)[affix_index] as Dictionary).family_id) if operation != "inscribe" else "",
		"previous_family_name": String((registry.affix_families[String(((item.affixes as Array)[affix_index] as Dictionary).family_id)] as Dictionary).name) if operation != "inscribe" else "",
		"previous_tier": int(((item.affixes as Array)[affix_index] as Dictionary).tier) if operation != "inscribe" else 0,
		"family_id": family_id,
		"family_name": String(family.name),
		"tier": tier,
		"target_fingerprint": target_fingerprint,
		"result_item": result_item.duplicate(true),
	}


func _ordered_unique_results(item: Dictionary, operation: String) -> Array[Dictionary]:
	var results_by_semantic_key := {}
	if operation == "refine":
		for affix_index in (item.affixes as Array).size():
			var current: Dictionary = item.affixes[affix_index]
			var family_id := String(current.family_id)
			for raw_tier in (registry.affix_families[family_id] as Dictionary).tiers:
				var tier := int((raw_tier as Dictionary).tier)
				if tier > int(current.tier):
					_add_unique_result(results_by_semantic_key, item, operation, affix_index, family_id, tier)
	elif operation == "rewrite":
		for affix_index in (item.affixes as Array).size():
			for family_id in _legal_rewrite_families(item, affix_index):
				for raw_tier in (registry.affix_families[family_id] as Dictionary).tiers:
					_add_unique_result(results_by_semantic_key, item, operation, affix_index, family_id, int((raw_tier as Dictionary).tier))
	else:
		var affix_index := (item.affixes as Array).size()
		for family_id in _legal_families(item, -1):
			for raw_tier in (registry.affix_families[family_id] as Dictionary).tiers:
				_add_unique_result(results_by_semantic_key, item, operation, affix_index, family_id, int((raw_tier as Dictionary).tier))
	var order_keys: Array[String] = []
	for semantic_key in results_by_semantic_key:
		var future: Dictionary = results_by_semantic_key[semantic_key]
		var order_key := "%d|%s|%s|%d|%s" % [int(item.get("law_seed", 0)), _item_fingerprint(item), operation, int(future.affected_affix_index), String(semantic_key)]
		order_keys.append("%s|%s" % [order_key.sha256_text(), String(semantic_key)])
	order_keys.sort()
	var ordered: Array[Dictionary] = []
	for order_key in order_keys:
		var semantic_key := String(order_key).substr(65)
		ordered.append((results_by_semantic_key[semantic_key] as Dictionary).duplicate(true))
	return ordered


func _add_unique_result(results_by_semantic_key: Dictionary, item: Dictionary, operation: String, affix_index: int, family_id: String, tier: int) -> void:
	var result_item := item.duplicate(true)
	var result_affix := {"family_id": family_id, "tier": tier}
	if operation == "inscribe":
		(result_item.affixes as Array).append(result_affix)
	else:
		(result_item.affixes as Array)[affix_index] = result_affix
	if not registry.validate_item_instance(result_item).is_empty():
		return
	var semantic_key := _semantic_result_key(result_item)
	if not results_by_semantic_key.has(semantic_key):
		results_by_semantic_key[semantic_key] = {
			"affected_affix_index": affix_index,
			"result_item": result_item.duplicate(true),
		}


func _legal_families(item: Dictionary, ignored_index: int) -> Array[String]:
	var used := {}
	for index in (item.affixes as Array).size():
		if index != ignored_index:
			used[String((item.affixes[index] as Dictionary).family_id)] = true
	var legal: Array[String] = []
	for raw_family_id in registry.affix_families:
		var family_id := String(raw_family_id)
		var family: Dictionary = registry.affix_families[family_id]
		if String(item.slot) in (family.compatible_slots as Array) and not used.has(family_id):
			legal.append(family_id)
	legal.sort()
	return legal


func _legal_rewrite_families(item: Dictionary, affix_index: int) -> Array[String]:
	var current_family := String(((item.affixes as Array)[affix_index] as Dictionary).family_id)
	var legal := _legal_families(item, affix_index)
	legal.erase(current_family)
	return legal


func _item_fingerprint(item: Dictionary) -> String:
	return JSON.stringify(item, "", true).sha256_text()


func _semantic_result_key(item: Dictionary) -> String:
	return JSON.stringify({
		"instance_id": String(item.get("instance_id", "")),
		"base_item_id": String(item.get("base_item_id", "")),
		"slot": String(item.get("slot", "")),
		"affixes": (item.get("affixes", []) as Array).duplicate(true),
		"rune_id": String(item.get("rune_id", "")),
		"law_id": String(item.get("law_id", "")),
	}, "", true)


func _same_candidate(left: Dictionary, right: Dictionary) -> bool:
	for key in [
		"candidate_id", "quote_id", "sequence_number", "choice_number", "cost", "operation",
		"affected_affix_index", "previous_family_id", "previous_family_name", "previous_tier",
		"family_id", "family_name", "tier", "target_fingerprint",
	]:
		if left.get(key) != right.get(key):
			return false
	return left.get("result_item") == right.get("result_item")


func _failure(code: String) -> Dictionary:
	return {"ok": false, "error": code}
