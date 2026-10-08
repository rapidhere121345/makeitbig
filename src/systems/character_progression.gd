class_name CharacterProgression
extends RefCounted

## Level and talent budget are derived from a single persisted XP total.
## XP never changes damage, growth class or equipment on its own.
const RULES_PATH := "res://content/character_progression.json"
static var _rules: Dictionary = {}

static func rules() -> Dictionary:
	if _rules.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RULES_PATH))
		if parsed is Dictionary:
			_rules = parsed
	return _rules.duplicate(true)

static func threshold(level: int) -> int:
	var data := rules()
	var total := 0
	for prior in range(1, clampi(level, 1, int(data.max_level))):
		total += int(data.first_level_cost) + (prior - 1) * int(data.level_cost_step)
	return total

static func maximum_experience() -> int:
	return threshold(int(rules().max_level))

static func is_valid_state(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 1:
		return false
	var xp: Variant = value.get("experience")
	return (xp is int or xp is float) and is_finite(float(xp)) and float(xp) == floorf(float(xp)) and float(xp) >= 0.0 and float(xp) <= maximum_experience()

static func snapshot(state: Dictionary) -> Dictionary:
	var data := rules()
	var xp := clampi(int(state.get("experience", 0)), 0, maximum_experience())
	var level := 1
	while level < int(data.max_level) and xp >= threshold(level + 1):
		level += 1
	var points := 0
	for earned_level in data.talent_point_levels:
		if level >= int(earned_level): points += 1
	return {
		"level": level, "max_level": int(data.max_level), "experience": xp,
		"level_experience": xp - threshold(level),
		"next_level_experience": threshold(level + 1) - threshold(level) if level < int(data.max_level) else 0,
		"points_earned": points,
	}

static func award(state: Dictionary, amount: int) -> Dictionary:
	var before := snapshot(state)
	var next := {"experience": mini(maximum_experience(), int(before.experience) + maxi(0, amount))}
	var after := snapshot(next)
	return {
		"character": next, "experience_delta": int(after.experience) - int(before.experience),
		"level_before": before.level, "level_after": after.level,
		"talent_points_delta": int(after.points_earned) - int(before.points_earned),
		"points_available_total": after.points_earned,
	}

static func contract_experience(contract_id: String, first_clear: bool) -> int:
	var reward: Dictionary = rules().contracts.get(contract_id, {})
	return int(reward.get("completion", 0)) + (int(reward.get("first_clear", 0)) if first_clear else 0)
