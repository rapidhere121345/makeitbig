class_name EarlyInterfaceVocabulary
extends RefCounted

## The single shared player-facing vocabulary for early build interfaces.
## Systems keep raw ids for resolution and diagnostics; player copy asks here.

const PLAYER_NAMES := {
	"piercing_continuation": "Piercing Continuation",
	"breedable_event": "Breedable Child Arrows",
	"branch_hit_counter": "Branch Hit Counter",
	"branch_target_history": "Branch Target History",
	"lineage_lifetime_pause": "Lineage Lifetime Pause",
}


static func player_name(raw_id: String) -> String:
	var normalized_id := raw_id.strip_edges()
	var known_name := String(PLAYER_NAMES.get(normalized_id, "")).strip_edges()
	return known_name if not known_name.is_empty() else "Unknown Interface (%s)" % normalized_id


static func player_names() -> Dictionary:
	return PLAYER_NAMES.duplicate()
