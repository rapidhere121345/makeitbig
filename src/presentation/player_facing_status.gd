class_name PlayerFacingStatus
extends RefCounted

## Single boundary between stable internal result codes and text shown to a
## player. Domain code keeps emitting compact machine-readable errors for tests,
## logs and transactions; every screen passes its status through this formatter.

const GENERIC_FAILURE := "操作未完成，请重新选择后再试。"

const ERROR_MESSAGES := {
	"wrong_route": "当前页面已经变化，请返回后重新操作。",
	"unknown_facility": "该设施当前不可用。",
	"action_unavailable": "该操作尚未开放。",
	"profile_required": "没有可用档案，请先开始新游戏。",
	"invalid_profile": "档案数据无效，请开始新的测试档案。",
	"unsupported_schema_version": "该测试档案来自旧版本，请开始新游戏。",
	"invalid_class": "当前职业尚未开放。",
	"unknown_preset": "没有找到该构筑方案。",
	"invalid_active_build": "当前装备无法形成有效构筑，请调整装备。",
	"active_build_invalid": "当前装备无法形成有效构筑，请调整装备。",
	"build_resolution_failed": "当前装备解析失败，请重新选择装备。",
	"content_unavailable": "玩法内容未能载入，请返回后重试。",
	"invalid_instance_id": "装备编号无效，请重新选择。",
	"invalid_item": "该装备的数据不完整，无法使用。",
	"invalid_item_instance": "该装备的数据不完整，无法使用。",
	"item_not_owned": "该装备已不在仓库中，请刷新列表。",
	"equipped_item_not_owned": "当前穿戴记录失效，请重新选择装备。",
	"item_already_equipped": "该装备已经穿戴。",
	"item_equipped": "请先卸下这件装备，再进行拆解。",
	"protected_item": "起步装备受保护，不能拆解。",
	"slot_not_prototype_open": "该装备槽尚未开放。",
	"forge_locked": "完成主线 04 后才能使用律筹锻造。",
	"unknown_operation": "请选择添铸、改写或精炼。",
	"inscribe_not_legal": "当前装备没有可合法添铸的新词条。",
	"rewrite_not_legal": "当前词条没有可合法改写的家族。",
	"refine_not_legal": "当前词条已是最高阶，无法再精炼。",
	"invalid_page": "候选页已失效，请重新开始推演。",
	"insufficient_law_tallies": "对应律筹不足，无法揭示或落锤。",
	"forge_session_required": "请先开始一次律筹推演。",
	"stale_forge_session": "这次推演已经过期，请重新推演。",
	"stale_target": "目标装备已经变化，请重新选择。",
	"candidate_not_revealed": "该未来结果尚未揭示。",
	"candidate_not_selected": "请先选择一个已揭示的未来结果。",
	"commit_pending": "上一笔落锤仍在处理，请稍候。",
	"invalid_commit_token": "落锤确认已失效，请重新选择结果。",
	"save_failed": "档案写入失败；装备和律筹均未改变，请重试。",
	"invalid_contract_id": "请选择一个可进入的契约。",
	"invalid_mode": "请选择 Manual 或 Auto 模式。",
	"invalid_seed": "契约种子必须是有效整数。",
	"invalid_room_count": "契约房间数量无效。",
	"contract_locked": "该契约尚未满足解锁条件。",
	"mode_not_allowed": "该契约不允许当前模式。",
	"proxy_locked": "Auto 尚未解锁，请先以 Manual 击败阈门巨像。",
	"pending_contract_required": "请先选择并准备一份契约。",
	"active_session_required": "当前没有进行中的契约。",
	"active_session_exists": "已有契约正在进行。",
	"result_pending": "本次契约仍在结算。",
	"ending_locked": "完成前期毕业契约后才能进入终章。",
	"no_pending_route": "当前没有等待中的页面。",
	"invalid_payload": "操作数据无效，请重新操作。",
	"invalid_last_result": "最近一次契约结果无效。",
	"invalid_safe_route": "存档返回位置无效。",
	"room_runtime_factory_failed": "战斗场景未能建立，请返回契约台重试。",
	"room_runtime_start_failed": "战斗未能开始，请返回契约台重试。",
	"profile_creation_failed": "新档案建立失败，请重试。",
	"campaign_progress_invalid": "主线进度无法读取，请开始新的测试档案。",
	"contract_plan_failed": "契约内容未能生成，请重新选择契约。",
	"contract_prepare_failed": "契约准备失败，请重新选择契约。",
	"session_start_failed": "契约未能开始，请重新进入。",
	"session_complete_failed": "契约结算失败，请重试。",
	"unknown_error": GENERIC_FAILURE,
}

const STATUS_MESSAGES := {
	"Tutorial complete": "游侠基础教程已完成",
	"New profile saved": "新档案已保存",
	"Profile saved": "档案已保存",
	"Contract result saved": "契约结果已保存",
	"Epilogue checkpoint saved": "终章进度已保存",
	"Contract preparation cancelled.": "契约准备已取消。",
	"No valid profile is available.": "没有可继续的有效档案。",
}

const FAILURE_PREFIXES := {
	"锻造拒绝：": "锻造",
	"目标选择失败：": "选择锻造目标",
	"Build 选择失败：": "切换构筑",
	"训练失败：": "训练",
	"换装失败：": "换装",
	"拆解失败：": "拆解",
}

## Settlement keeps these source ids as authority/telemetry data. This table is
## the presentation boundary: no entity number or machine token reaches a player.
const ENEMY_FAILURE_SOURCE_LABELS := {
	"melee_pursuer": "近战追猎者",
	"charging_raider": "冲锋掠袭者",
	"fan_ranged": "扇射游猎者",
}
const BOSS_FAILURE_SOURCE_LABELS := {
	"slam": "阈门巨像的重击",
	"sweep": "阈门巨像的横扫",
	"lane": "阈门巨像的火线",
}
const HAZARD_FAILURE_SOURCE_LABELS := {
	"exposed_ground_zone": "裸露地面危险区",
	"moving_fireline": "移动火线",
}
const UNKNOWN_FAILURE_SOURCE := "未知终止来源"


static func error_message(error_code: String) -> String:
	var code := error_code.strip_edges()
	if code.is_empty():
		return GENERIC_FAILURE
	return String(ERROR_MESSAGES.get(code, GENERIC_FAILURE))


static func failure(action: String, error_code: String) -> String:
	var label := action.strip_edges()
	if label.is_empty():
		return error_message(error_code)
	return "%s未完成：%s" % [label, error_message(error_code)]


## Formats only the damage-source shapes emitted by combat settlement. The raw
## string remains with the result payload; callers use this only for copy shown to
## a player.
static func failure_source_label(value: String) -> String:
	var source := value.strip_edges()
	if source.is_empty():
		return UNKNOWN_FAILURE_SOURCE
	var parts := source.split("/", false)
	if parts.size() == 3 and parts[0] == "enemy" and String(parts[1]).is_valid_int():
		return String(ENEMY_FAILURE_SOURCE_LABELS.get(String(parts[2]), UNKNOWN_FAILURE_SOURCE))
	if parts.size() == 2 and parts[0] == "boss":
		return String(BOSS_FAILURE_SOURCE_LABELS.get(String(parts[1]), UNKNOWN_FAILURE_SOURCE))
	if parts.size() == 2 and parts[0] == "hazard":
		return String(HAZARD_FAILURE_SOURCE_LABELS.get(String(parts[1]), UNKNOWN_FAILURE_SOURCE))
	return UNKNOWN_FAILURE_SOURCE


static func message(value: String) -> String:
	var text := value.strip_edges()
	if text.is_empty():
		return ""
	if STATUS_MESSAGES.has(text):
		return String(STATUS_MESSAGES[text])
	if ERROR_MESSAGES.has(text):
		return error_message(text)

	## Normal persistence appends this exact diagnostic suffix. Keep its useful
	## generation/slot evidence while translating the state sentence.
	for raw_status: String in STATUS_MESSAGES:
		if text.begins_with(raw_status + " (generation "):
			var suffix := text.substr(raw_status.length())
			return String(STATUS_MESSAGES[raw_status]) + suffix.replace("(generation ", "（存档代 ").replace(" / slot ", "／槽位 ").replace(").", "）")

	for raw_prefix: String in FAILURE_PREFIXES:
		if text.begins_with(raw_prefix):
			return failure(String(FAILURE_PREFIXES[raw_prefix]), text.trim_prefix(raw_prefix))

	if text.begins_with("SAVE FAILED:"):
		return error_message("save_failed")
	if text.begins_with("Save unavailable: "):
		return "存档不可用：%s" % _detail_message(text.trim_prefix("Save unavailable: "))
	if text.begins_with("Save ignored: "):
		return "已忽略无效存档：%s" % _detail_message(text.trim_prefix("Save ignored: "))
	return GENERIC_FAILURE if _looks_like_internal_code(text) else text


static func _detail_message(detail: String) -> String:
	var normalized := detail.strip_edges()
	return error_message(normalized) if ERROR_MESSAGES.has(normalized) or _looks_like_internal_code(normalized) else normalized


static func _looks_like_internal_code(text: String) -> bool:
	if text.is_empty() or not text.contains("_"):
		return false
	for index in text.length():
		var character := text[index]
		if (character >= "a" and character <= "z") or (character >= "0" and character <= "9") or character == "_":
			continue
		return false
	return true
