extends RefCounted

## Threshold Colossus defeat diagnosis extracted from ApplicationState: the
## primary-bottleneck classification attached to a Manual boss defeat, plus the
## numeric parameter reader the pity-family choice shares.
const BOSS_DIAGNOSIS_CONTRACT_ID := "threshold_colossus"
const BOSS_DIAGNOSIS_MODE := "Manual"
const BOSS_DIAGNOSIS_RANGE_MIN := 120.0
const BOSS_DIAGNOSIS_LIFETIME_MIN := 24.0
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


static func attach_defeat_diagnosis(active_session: Dictionary, result: Dictionary) -> void:
	if String(active_session.get("contract_id", "")) != BOSS_DIAGNOSIS_CONTRACT_ID:
		return
	if String(active_session.get("mode", "")) != BOSS_DIAGNOSIS_MODE:
		return
	if String(result.get("outcome", "")).to_lower() != "defeat":
		return
	var resolved_value: Variant = active_session.get("resolved_build", {})
	var resolved_build: Dictionary = resolved_value if resolved_value is Dictionary else {}
	result["primary_bottleneck"] = classify_bottleneck(resolved_build)


static func classify_bottleneck(resolved_build: Dictionary) -> Dictionary:
	var classification := String(resolved_build.get("growth_classification", "")).to_lower()
	if classification == "convergent":
		return BOSS_BOTTLENECK_GROWTH_CONVERGENT.duplicate(true)
	if classification == "critical":
		return BOSS_BOTTLENECK_GROWTH_CRITICAL.duplicate(true)
	if classification == "exponential":
		var parameters_value: Variant = resolved_build.get("final_parameters", {})
		var parameters: Dictionary = parameters_value if parameters_value is Dictionary else {}
		if boss_parameter(parameters, "d", INF) < BOSS_DIAGNOSIS_RANGE_MIN:
			return BOSS_BOTTLENECK_TARGETING_RANGE_SHORT.duplicate(true)
		if boss_parameter(parameters, "T", INF) < BOSS_DIAGNOSIS_LIFETIME_MIN:
			return BOSS_BOTTLENECK_PROJECTILE_LIFETIME_SHORT.duplicate(true)
	return BOSS_BOTTLENECK_BOSS_PATTERN_SURVIVAL.duplicate(true)


static func boss_parameter(parameters: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = parameters.get(key, null)
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return fallback
	var number := float(value)
	if is_nan(number) or is_inf(number):
		return fallback
	return number
