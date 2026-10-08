class_name EarlyInterfaceVocabulary
extends RefCounted

## The single shared player-facing vocabulary for early build interfaces.
## Systems keep raw ids for resolution and diagnostics; player copy asks here.

const PLAYER_NAMES := {
	"piercing_continuation": "穿刺续行",
	"breedable_event": "可繁殖子箭",
	"branch_hit_counter": "分支命中计数",
	"branch_target_history": "分支目标记录",
	"lineage_lifetime_pause": "谱系寿命暂停",
}


static func player_name(raw_id: String) -> String:
	var normalized_id := raw_id.strip_edges()
	var known_name := String(PLAYER_NAMES.get(normalized_id, "")).strip_edges()
	return known_name if not known_name.is_empty() else "未收录接口（%s）" % normalized_id


static func player_names() -> Dictionary:
	return PLAYER_NAMES.duplicate()
