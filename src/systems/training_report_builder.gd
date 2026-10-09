class_name TrainingReportBuilder
extends RefCounted

const EarlyInterfaceVocabularyScript = preload("res://src/content/early_interface_vocabulary.gd")


static func build_report(resolved: Dictionary, preset_id: String) -> Dictionary:
	var fingerprint := String(resolved.build_fingerprint)
	var event_data: Dictionary = resolved.total_events
	var event_value := BigValue.from_components(int(event_data.get("layer", 0)), float(event_data.get("magnitude", 0.0)))
	var event_display := event_value.to_short_string(4) if event_value != null else str(float(resolved.total_events_float))
	return {
		"preset_id": preset_id,
		"build_fingerprint": fingerprint,
		"training_seed": training_seed(fingerprint),
		"p": float(resolved.final_parameters.p),
		"R": float(resolved.R),
		"g": int(resolved.generation_count),
		"event_count": float(resolved.total_events_float),
		"event_count_display": event_display,
		"event_count_value": event_data.duplicate(true),
		"growth_curve": growth_curve(resolved, event_display),
		"action": action(resolved),
		"state": String(resolved.growth_classification),
		"report": "p=%.2f, R=%.2f, g=%d, events=%s: %s" % [float(resolved.final_parameters.p), float(resolved.R), int(resolved.generation_count), event_display, String(resolved.growth_classification)],
	}


## Deterministic, non-negative training seed derived only from the resolved
## build fingerprint. A fingerprint is SHA-256 hex, so its first 52 bits are
## already uniformly distributed; taking them verbatim keeps the mapping stable
## across processes and restarts without wall-clock time or global RNG while
## staying below JSON's 53-bit exact-integer ceiling for persisted reports.
static func training_seed(fingerprint: String) -> int:
	if fingerprint.length() < 13:
		return 0
	return ("0x" + fingerprint.substr(0, 13)).hex_to_int()


## Training-page growth curve: 4-6 strictly increasing, de-duplicated sample
## generations across 0..g that always include G0 and Gg. Every point is a
## fresh dictionary carrying generation:int and events_display:String (plus
## events_float when the value is a finite host float). The final point reuses
## the authoritative event_count_display verbatim; intermediate points are the
## expected cumulative event count through that generation, derived only from
## the same resolved Build's R and g, so the curve never aliases stored state.
static func growth_curve(resolved: Dictionary, final_display: String) -> Array:
	var R := float(resolved.get("R", 0.0))
	var g := maxi(0, int(resolved.get("generation_count", 0)))
	var curve: Array = []
	for generation_value in growth_sample_generations(g):
		var generation := int(generation_value)
		var point := {"generation": generation, "events_display": ""}
		if generation == g:
			point["events_display"] = final_display
			var final_float := float(resolved.get("total_events_float", 0.0))
			if is_finite(final_float) and not is_nan(final_float):
				point["events_float"] = final_float
		else:
			var cumulative: BigValue = expected_cumulative_events(R, generation)
			if cumulative == null:
				point["events_display"] = "0"
			else:
				point["events_display"] = cumulative.to_short_string(4)
				if cumulative.layer == 0:
					point["events_float"] = cumulative.magnitude
		curve.append(point)
	return curve


## Distinct ascending generations across 0..g: six evenly spaced samples when
## g >= 5, every generation for shorter runs, and just [0] when g == 0.
static func growth_sample_generations(g: int) -> Array:
	if g < 0:
		return [0]
	var count := mini(g + 1, 6)
	if count <= 1:
		return [0]
	var generations: Array = []
	for index in count:
		generations.append(roundi(float(index) * float(g) / float(count - 1)))
	return generations


## Expected cumulative events through generation k: sum_{i=0}^{k} R^i, matching
## the authoritative ArrowModel finite-series semantics (linear inside the
## critical epsilon, 1.0 when R <= 0). Returns a BigValue so astronomically
## large totals never overflow into INF or NaN.
static func expected_cumulative_events(R: float, generation: int) -> BigValue:
	if generation < 0:
		return BigValue.from_float(0.0)
	if R <= 0.0:
		return BigValue.from_float(1.0)
	if absf(R - 1.0) <= PiercingArrowModel.EPSILON:
		return BigValue.from_float(float(generation + 1))
	var terms := generation + 1
	var ordinary := (pow(R, float(terms)) - 1.0) / (R - 1.0)
	if is_finite(ordinary) and not is_nan(ordinary):
		return BigValue.from_float(ordinary)
	# log10((R^terms - 1) / (R - 1)) stays representable once pow() overflows.
	var leading_log := float(terms) * log(R) / log(10.0)
	var correction := 0.0
	if leading_log < 16.0:
		correction = log(1.0 - pow(10.0, -leading_log)) / log(10.0)
	return BigValue.from_power10(leading_log + correction - log(R - 1.0) / log(10.0))


## Exactly one executable sentence for the training page. Missing interfaces
## win over the growth-state sentence in breedable_event then
## branch_target_history order; remaining gaps are listed in one sentence.
## No full formulas and no power/TTK/range recommendations.
static func action(resolved: Dictionary) -> String:
	var missing_ids := {}
	for entry in (resolved.get("missing_interfaces", []) as Array):
		if _is_text(entry):
			missing_ids[String(entry)] = true
	if missing_ids.has("breedable_event"):
		return "补齐%s接口，让后代能继续分叉。" % EarlyInterfaceVocabularyScript.player_name("breedable_event")
	if missing_ids.has("branch_target_history"):
		return "补齐%s接口，让分叉后代被持续追踪。" % EarlyInterfaceVocabularyScript.player_name("branch_target_history")
	if not missing_ids.is_empty():
		var ids := missing_ids.keys()
		ids.sort()
		var names: Array[String] = []
		for id in ids:
			names.append(EarlyInterfaceVocabularyScript.player_name(String(id)))
		return "补齐缺失的接口%s。" % "、".join(names)
	match String(resolved.get("growth_classification", "")):
		"convergent":
			return "寻找能提高续生概率的词条，再回来重新训练验证。"
		"critical":
			return "尝试小幅提高续生概率，再回来验证是否突破临界增长。"
		"exponential":
			return "进入实战，确认生存与命中稳定性。"
		_:
			return "重新训练，确认当前方案的续生增长。"


static func _is_text(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME
