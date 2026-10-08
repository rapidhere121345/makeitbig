class_name EquipmentComparison
extends GridContainer
## A same-context comparison of the authoritative current and replacement builds.
const LABELS := {"p":"续行概率", "T":"箭链寿命", "v":"箭速", "d":"射程", "turn":"转向耗时", "damage":"伤害", "critical_chance":"暴击率", "max_health":"生命"}
const ORDER := ["p", "damage", "max_health", "T", "v", "d", "turn", "critical_chance"]

func present(current: Dictionary, replacement: Dictionary, result_heading: String = "换装后") -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	columns = 4
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("h_separation", 8)
	add_theme_constant_override("v_separation", 2)
	var rows := comparison_rows(current, replacement)
	if rows.is_empty():
		_cell("暂无可用对比", ShellTheme.NEUTRAL)
		return
	for title in ["构筑属性", "当前", result_heading, "变化"]:
		_cell(title, ShellTheme.NEUTRAL)
	var changes := 0
	for row in rows:
		if not bool(row.changed): continue
		changes += 1
		var color: Color = ShellTheme.PROXY if bool(row.improves) else ShellTheme.WARNING
		_cell(row.label, ShellTheme.BONE)
		_cell(row.before_text, ShellTheme.NEUTRAL)
		_cell(row.after_text, color)
		_cell(row.delta_text, color)
	if changes == 0:
		_cell("属性数值相同", ShellTheme.NEUTRAL)
		_cell("—", ShellTheme.NEUTRAL)
		_cell("看符文与法则", ShellTheme.BONE)
		_cell("—", ShellTheme.NEUTRAL)


## Compare only shared, finite values published by the domain preview. A missing
## value is unknown, not zero; a shorter turn time is an improvement.
static func comparison_rows(current: Dictionary, replacement: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for key: String in ORDER:
		if not _finite_number(current.get(key)) or not _finite_number(replacement.get(key)):
			continue
		var before := float(current[key])
		var after := float(replacement[key])
		var delta := after - before
		var delta_text := ("+" if delta > 0 else "−") + _number(absf(delta), 2)
		if key in ["p", "critical_chance"]:
			delta_text = ("+" if delta > 0 else "−") + _number(absf(delta) * 100.0, 1) + "百分点"
		elif key == "turn":
			delta_text = ("快 " if delta < 0 else "慢 ") + _number(absf(delta), 2) + "秒"
		elif key == "T":
			delta_text += "秒"
		rows.append({"key": key, "label": LABELS[key], "changed": not is_equal_approx(before, after),
			"before_text": _value(key, before), "after_text": ("↑ " if after > before else "↓ ") + _value(key, after),
			"delta_text": delta_text, "improves": after < before if key == "turn" else after > before})
	return rows

static func _finite_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func _value(key: String, value: float) -> String:
	if key in ["p", "critical_chance"]: return _number(value * 100.0, 1) + "%"
	if key in ["turn", "T"]: return _number(value, 2) + "秒"
	return _number(value, 1)

static func _number(value: float, decimals: int) -> String:
	var text := String.num(value, decimals)
	return text.rstrip("0").rstrip(".") if text.contains(".") else text

func _cell(text_value: String, color: Color) -> void:
	var label := Label.new()
	label.text = text_value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(label)
