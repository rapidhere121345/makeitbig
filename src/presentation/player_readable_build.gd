class_name PlayerReadableBuild
extends RefCounted

## Central player-facing vocabulary for build parameters and early equipment.
## Definitions and numeric effects stay owned by EarlyItemRegistry; this class
## only translates those definitions into readable Chinese.

const EarlyItemRegistryScript = preload("res://src/content/early_item_registry.gd")
const EarlyInterfaceVocabularyScript = preload("res://src/content/early_interface_vocabulary.gd")

const PARAMETER_ORDER: Array[String] = ["p", "T", "v", "d", "turn", "damage", "critical_chance", "max_health"]
const PARAMETER_LABELS := {
	"p": "穿刺箭续行概率",
	"T": "共享谱系寿命",
	"v": "投射物速度",
	"d": "寻敌与穿刺箭射程",
	"turn": "转向时间（数值越低越好）",
	"damage": "载体伤害",
	"critical_chance": "暴击率",
	"max_health": "最大生命",
}
const SLOT_LABELS := {
	"main_hand": "主手", "off_hand": "副手", "gloves": "手套", "ring_1": "戒指",
	"ring_2": "戒指", "necklace": "项链", "head": "头部", "chest": "胸甲",
	"pants": "裤甲", "leg_armor": "腿甲", "bracers": "护腕", "belt": "腰带",
}
const OPERATION_LABELS := {
	"add": "直接增加",
	"multiply": "乘算调整",
	"multiply_bonus": "提高",
	"reduce_percent": "降低",
}
const TIER_LABELS: Array[String] = ["", "I 阶", "II 阶", "III 阶", "IV 阶"]

var item_registry: Variant = null


func _init(registry: Variant = null) -> void:
	if registry != null:
		item_registry = registry
		return
	var loaded = EarlyItemRegistryScript.new()
	if loaded.load_all().is_empty():
		item_registry = loaded


func parameter_label(parameter: String) -> String:
	return String(PARAMETER_LABELS.get(parameter, "未识别参数"))


func parameter_name(parameter: String) -> String:
	return parameter_label(parameter)


func operation_label(operation: String) -> String:
	return String(OPERATION_LABELS.get(operation, "数值调整"))


func tier_label(tier: int) -> String:
	return TIER_LABELS[tier] if tier > 0 and tier < TIER_LABELS.size() else "未知阶级"


func slot_label(slot: String) -> String:
	return String(SLOT_LABELS.get(slot, "未知槽位"))


func format_parameters(parameters: Dictionary) -> String:
	var lines: Array[String] = []
	for parameter in PARAMETER_ORDER:
		if parameters.has(parameter):
			lines.append("%s：%s" % [parameter_label(parameter), format_parameter_value(parameter, parameters[parameter])])
	return "\n".join(lines)


func format_parameter_value(parameter: String, value: Variant) -> String:
	if not _is_number(value):
		return "未记录"
	var number := float(value)
	if parameter in ["p", "critical_chance"]:
		return "%s%%" % _number(number * 100.0, 2)
	if parameter == "T":
		return "%s 秒" % _number(number, 2)
	if parameter == "turn":
		return "%s 秒（越低越好）" % _number(number, 4)
	if parameter == "v":
		return "%s 单位/秒" % _number(number, 2)
	if parameter == "d":
		return "%s 距离单位" % _number(number, 2)
	return _number(number, 2)


func format_parameter(parameter: String, value: Variant) -> String:
	return "%s：%s" % [parameter_name(parameter), format_parameter_value(parameter, value)]


func format_comparison(current_values: Dictionary, equipped_values: Dictionary) -> String:
	var lines: Array[String] = []
	for parameter in PARAMETER_ORDER:
		if not current_values.has(parameter) or not equipped_values.has(parameter):
			continue
		if not _is_number(current_values[parameter]) or not _is_number(equipped_values[parameter]):
			continue
		lines.append("%s：%s → %s（%s）" % [
			parameter_label(parameter),
			format_parameter_value(parameter, current_values[parameter]),
			format_parameter_value(parameter, equipped_values[parameter]),
			_format_delta(parameter, float(current_values[parameter]), float(equipped_values[parameter])),
		])
	return "\n".join(lines)


## A compact decision surface for an authoritative equipment preview. It names
## every changed parameter and every gained/lost interface before the player is
## offered the equip action; it does not derive recommendations or recompute the
## preview. Unknown interface ids remain visible as ids instead of being hidden
## behind a count.
func format_candidate_decision_summary(current_values: Dictionary, preview: Dictionary, interface_names: Dictionary = {}) -> String:
	if preview.is_empty() or preview.get("ok", true) == false:
		return "变化未知 · 暂无可用对比"
	var resolved_interface_names := EarlyInterfaceVocabularyScript.player_names()
	resolved_interface_names.merge(interface_names, true)
	var lines: Array[String] = []
	var final_values: Dictionary = preview.get("final_parameters", {}) if preview.get("final_parameters", {}) is Dictionary else {}
	if not current_values.is_empty() and not final_values.is_empty():
		var parameter_changes: Array[String] = []
		for parameter in PARAMETER_ORDER:
			var before: Variant = current_values.get(parameter, null)
			var after: Variant = final_values.get(parameter, null)
			if not _is_number(before) or not _is_number(after):
				continue
			var before_number := float(before)
			var after_number := float(after)
			if absf(after_number - before_number) <= 0.0001:
				continue
			parameter_changes.append("%s %s" % [_decision_parameter_label(parameter), _format_delta(parameter, before_number, after_number)])
		if not parameter_changes.is_empty():
			lines.append("参数：" + " · ".join(parameter_changes))
	_append_named_preview_group(lines, preview, "interfaces_gained", "获得接口", resolved_interface_names)
	_append_named_preview_group(lines, preview, "interfaces_lost", "失去接口", resolved_interface_names)
	var tags_gained := _variant_array(preview.get("tags_gained", []))
	var tags_lost := _variant_array(preview.get("tags_lost", []))
	if not tags_gained.is_empty() or not tags_lost.is_empty():
		lines.append("标签 +%d / −%d" % [tags_gained.size(), tags_lost.size()])
	if not lines.is_empty():
		return "\n".join(lines)
	if final_values.is_empty() or current_values.is_empty():
		return "参数对比缺失 · 无已报告接口变化"
	return "参数与接口无变化"


func format_modifier(modifier: Dictionary) -> String:
	var parameter := String(modifier.get("parameter", ""))
	var operation := String(modifier.get("operation", ""))
	var value: Variant = modifier.get("value", null)
	if parameter.is_empty() or not _is_number(value):
		return "效果数据不完整"
	var number := float(value)
	var effect := ""
	match operation:
		"add":
			effect = "+%s 个百分点" % _number(number * 100.0, 2) if parameter in ["p", "critical_chance"] else "+%s" % _number(number, 2)
		"multiply":
			effect = "×%s" % _number(number, 3)
			if number >= 1.0:
				effect += "（提高 %s%%）" % _number((number - 1.0) * 100.0, 2)
			else:
				effect += "（降低 %s%%）" % _number((1.0 - number) * 100.0, 2)
		"multiply_bonus":
			effect = "+%s%%" % _number(number * 100.0, 2)
		"reduce_percent":
			effect = "-%s%%" % _number(number * 100.0, 2)
		_:
			effect = "%s %s" % [operation_label(operation), _number(number, 3)]
	return "%s：%s" % [parameter_label(parameter), effect]


func format_base_item(base_item_id: String) -> String:
	var definition := _definition("base_items", base_item_id)
	if definition.is_empty():
		return "底材：未知底材\n底材属性：数据未接入"
	var effects: Array[String] = []
	for raw_modifier in definition.get("modifiers", []):
		if raw_modifier is Dictionary:
			effects.append(format_modifier(raw_modifier))
	return "底材：%s\n底材属性：%s" % [
		String(definition.get("name", "未知底材")),
		"；".join(effects) if not effects.is_empty() else "无",
	]


func format_affix(affix: Dictionary) -> String:
	var family_id := String(affix.get("family_id", affix.get("family", "")))
	var tier := int(affix.get("tier", 0))
	var definition := _definition("affix_families", family_id)
	if definition.is_empty():
		var fallback_name := String(affix.get("name", "未识别词条")).strip_edges()
		return "%s %s：效果数据未接入" % [fallback_name if not fallback_name.is_empty() else "未识别词条", tier_label(tier)]
	var modifier: Dictionary = item_registry.modifier_for_affix(family_id, tier)
	var effect := format_modifier(modifier) if not modifier.is_empty() else "效果数据不完整"
	return "%s %s：%s" % [String(definition.get("name", "未识别词条")), tier_label(tier), effect]


func format_rune(rune_id: String) -> String:
	if rune_id.strip_edges().is_empty():
		return "符文：无"
	var definition := _definition("runes", rune_id)
	return "符文：%s｜%s" % [String(definition.get("name", "未识别符文")), String(definition.get("semantics", "说明数据未接入"))]


func format_law(law_id: String) -> String:
	if law_id.strip_edges().is_empty():
		return "法则：无"
	var definition := _definition("laws", law_id)
	return "法则：%s｜%s" % [String(definition.get("name", "未识别法则")), String(definition.get("semantics", "说明数据未接入"))]


func format_item(entry: Dictionary, current_values: Dictionary = {}, equipped_values: Dictionary = {}) -> String:
	var lines: Array[String] = ["槽位：%s" % slot_label(String(entry.get("slot", "")))]
	lines.append(format_base_item(String(entry.get("base_item_id", ""))))
	var affix_lines: Array[String] = []
	var affixes_value: Variant = entry.get("affixes", [])
	if affixes_value is Array:
		for raw_affix in affixes_value:
			if raw_affix is Dictionary:
				affix_lines.append("· %s" % format_affix(raw_affix))
	lines.append("词条：\n%s" % ("\n".join(affix_lines) if not affix_lines.is_empty() else "无"))
	lines.append(format_rune(String(entry.get("rune_id", ""))))
	lines.append(format_law(String(entry.get("law_id", ""))))
	var comparison := format_comparison(current_values, equipped_values)
	if not comparison.is_empty():
		lines.append("当前值 → 装备后值：\n%s" % comparison)
	return "\n".join(lines)


func format_skill(skill: Dictionary) -> String:
	if skill.is_empty():
		return "技能说明暂不可用"
	var parameters: Array[String] = []
	for parameter in skill.get("equipment_parameters", []):
		parameters.append(parameter_label(String(parameter)))
	var duration := "无持续时间"
	var duration_ticks := int(skill.get("duration_ticks", 0))
	var displacement := float(skill.get("displacement_units", 0.0))
	var speed := float(skill.get("speed_units_per_second", 0.0))
	if displacement > 0.0:
		duration = "%d tick 内位移 %s" % [duration_ticks, _number(displacement, 1)]
	elif speed > 0.0:
		duration = "%d tick，移动速度 %s" % [duration_ticks, _number(speed, 1)]
	elif duration_ticks > 0:
		duration = "%d tick（%s 秒）" % [duration_ticks, _number(float(duration_ticks) / 30.0, 2)]
	var cooldown_ticks := int(skill.get("cooldown_ticks", 0))
	return "\n".join([
		"%s｜%s" % [String(skill.get("name", "技能")), " / ".join(skill.get("key_bindings", []))],
		"类型：%s" % String(skill.get("type", "未记录")),
		"目标规则：%s" % String(skill.get("target_rule", "未记录")),
		"射程：%s" % String(skill.get("range_rule", "未记录")),
		"完整效果：%s" % String(skill.get("full_effect", "未记录")),
		"冷却：%d tick（%s 秒，30Hz）" % [cooldown_ticks, _number(float(cooldown_ticks) / 30.0, 2)],
		"持续/位移：%s" % duration,
		"受装备参数影响：%s" % ("、".join(parameters) if not parameters.is_empty() else "无"),
		"联动：%s" % "；".join(skill.get("synergies", [])),
		"限制：%s" % "；".join(skill.get("limitations", [])),
	])


func diagnostic_ids(entry: Dictionary) -> String:
	var affix_ids: Array[String] = []
	for raw_affix in entry.get("affixes", []):
		if raw_affix is Dictionary:
			affix_ids.append("%s T%d" % [String(raw_affix.get("family_id", raw_affix.get("family", ""))), int(raw_affix.get("tier", 0))])
	return "instance=%s base=%s affixes=%s rune=%s law=%s" % [
		String(entry.get("instance_id", "")), String(entry.get("base_item_id", "")),
		", ".join(affix_ids), String(entry.get("rune_id", "")), String(entry.get("law_id", "")),
	]


func _definition(table: String, id: String) -> Dictionary:
	if item_registry == null or id.strip_edges().is_empty():
		return {}
	var rows: Dictionary = item_registry.get(table)
	return (rows[id] as Dictionary).duplicate(true) if rows.has(id) else {}


func _is_number(value: Variant) -> bool:
	return (value is int or value is float) and not (value is bool) and is_finite(float(value))


func _append_named_preview_group(lines: Array[String], preview: Dictionary, key: String, label: String, interface_names: Dictionary) -> void:
	var values := _variant_array(preview.get(key, []))
	if values.is_empty():
		return
	var names: Array[String] = []
	for value in values:
		var interface_id := String(value)
		var readable_name := String(interface_names.get(interface_id, "")).strip_edges()
		names.append(readable_name if not readable_name.is_empty() else "未收录接口（%s）" % interface_id)
	lines.append("%s：%s" % [label, "，".join(names)])


func _decision_parameter_label(parameter: String) -> String:
	return String({
		"p": "续行概率", "T": "谱系寿命", "v": "投射速度", "d": "射程",
		"turn": "转向时间", "damage": "载体伤害", "critical_chance": "暴击率", "max_health": "最大生命",
	}.get(parameter, parameter_label(parameter)))


func _variant_array(value: Variant) -> Array:
	return value if value is Array else []


func _format_delta(parameter: String, before: float, after: float) -> String:
	var delta := after - before
	var sign_text := "+" if delta > 0.0 else ""
	if parameter in ["p", "critical_chance"]:
		return "%s%s 个百分点" % [sign_text, _number(delta * 100.0, 2)]
	if parameter in ["T", "turn"]:
		return "%s%s 秒" % [sign_text, _number(delta, 4)]
	if parameter == "v":
		return "%s%s 单位/秒" % [sign_text, _number(delta, 2)]
	if parameter == "d":
		return "%s%s 距离单位" % [sign_text, _number(delta, 2)]
	return "%s%s" % [sign_text, _number(delta, 2)]


func _number(value: float, decimals: int) -> String:
	var rendered := String.num(value, decimals)
	while rendered.contains(".") and rendered.ends_with("0"):
		rendered = rendered.trim_suffix("0")
	return rendered.trim_suffix(".")
