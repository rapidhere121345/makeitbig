extends RefCounted
## Objective, progress and navigation-copy derivations extracted from BaseHubScreen.
## Every line is derived from the save/campaign/story snapshots the hub was
## handed, reached through the owner reference; nothing here writes state.

const UiKit := preload("res://src/presentation/ui_kit.gd")
const PlayerFacingStatusScript = preload("res://src/presentation/player_facing_status.gd")

## Short player-facing names of the authored mainline nodes. Shared by the next
## objective line and the contract marker so the two can never disagree.
const _SHORT_NODE_LABELS := {
	"tutorial_ranger_basics": "Tutorial",
	"mainline_01_first_hunt": "Main Quest 01",
	"mainline_02_priority_under_pressure": "Main Quest 02",
	"mainline_03_first_elite": "Main Quest 03",
	"mainline_04_hazard_and_forge": "Main Quest 04",
	"mainline_05_growth_gate": "Main Quest 05",
	"threshold_colossus": "Threshold Colossus",
	"auto_certification": "AUTO Trial",
}
## While the first hunt is pending, the header goal names the stand and the
## contract itself; the authored story line stays reachable as tooltip context.
const FIRST_HUNT_OBJECTIVE_TEXT := "Contract Board: First Hunt"
## The authored reward a locked page is waiting for. Both the card and the world
## marker read this table, so "locked" always names the one real gate.
const _UNLOCK_REASONS := {
	"forge": "Needs forge reward",
	"proxy": "First Colossus Kill",
}
## Stable outcome/status tokens become readable copy; anything the
## tables do not name is passed through verbatim, so a new save state is never
## renamed by a guess. The hub and its read-back API share the same two tables.
const _KNOWN_OUTCOMES := {
	"victory": "Victory",
	"defeat": "Failure",
	"final_victory": "Final Victory",
	"error": "Error",
	"aborted": "Aborted",
}
## The published non-colour state marks: the filled diamond the world markers
## already use for a route that is open and highlighted, and the hollow one for a
## station the player cannot open yet.
const FILLED_MARK := "\u25c6"
const LOCK_MARK := "\u25c7"

var _hub: BaseHubScreen


func _init(hub: BaseHubScreen) -> void:
	_hub = hub


func _derive_unlock_reasons() -> Dictionary:
	## Lock reasons are read back from the same snapshot the cards use: a page is
	## only ever "locked" while the authored reward that opens it is genuinely
	## absent, and the reason names that reward instead of the current picture.
	var earned_rewards := UiKit.as_array(_hub._campaign_snapshot.get("earned_reward_tags", []))
	var progression := UiKit.as_dictionary(_hub._profile.get("progression", {}))
	var reasons := _UNLOCK_REASONS.duplicate()
	if "law_forge_unlock" in earned_rewards:
		reasons.erase("forge")
	if bool(progression.get("proxy_unlocked", false)):
		reasons.erase("proxy")
	return reasons


func _settlement_text() -> String:
	if _hub._last_result.is_empty():
		return "Latest Result: No Contract Record"
	var rewards := UiKit.as_dictionary(_hub._last_result.get("rewards", {}))
	var equipment_count := maxi(0, int(rewards.get("equipment_drop_count", 0)))
	var drop_summary := "Equipment: %d Items" % equipment_count if equipment_count > 0 else String(_hub._last_result.get("drop", _hub._last_result.get("last_drop", rewards.get("drop_label", rewards.get("drop_id", "None")))))
	return "Latest: %s\nDrops: %s" % [_localized_outcome(String(_hub._last_result.get("outcome", "Unknown"))), drop_summary]


func _localized_outcome(outcome: String) -> String:
	return String(_KNOWN_OUTCOMES.get(outcome, outcome))


func _localized_status(message: String) -> String:
	return PlayerFacingStatusScript.message(message)


func _nav_title(feature_id: String) -> String:
	return String({
		"contract": "Contract Board",
		"loadout": "Loadout",
		"forge": "Tempering Anvil",
		"training": "Training",
		"proxy": "Proxy Bay",
	}.get(feature_id, feature_id))


func _nav_locked(feature_id: String, progression: Dictionary, earned_rewards: Array) -> bool:
	match feature_id:
		"loadout":
			return false # The rack already allows viewing the starter loadout.
		"forge":
			return not ("law_forge_unlock" in earned_rewards)
		"proxy":
			return not bool(progression.get("proxy_unlocked", false))
	return false


func _nav_status_text(feature_id: String) -> String:
	## The one line a player reads on a card. A locked page leads with the
	## published non-colour lock mark and then names the single authored gate that
	## opens it; an open page shows the same note its world marker carries.
	var progression := UiKit.as_dictionary(_hub._profile.get("progression", {}))
	var earned_rewards := UiKit.as_array(_hub._campaign_snapshot.get("earned_reward_tags", []))
	if _nav_locked(feature_id, progression, earned_rewards):
		var reason := String(_hub._unlock_reasons.get(feature_id, ""))
		return LOCK_MARK if reason.is_empty() else "%s %s" % [LOCK_MARK, reason]
	return _nav_detail(feature_id, progression, earned_rewards)


func _nav_detail(feature_id: String, progression: Dictionary, earned_rewards: Array) -> String:
	## The short note the world marker shows. It carries the next objective for the
	## contract board and the exact reason for every page that is not open yet.
	match feature_id:
		"contract":
			return _player_nav_node_label()
		"loadout":
			return "Compare Gear" if "equipment_compare_unlock" in earned_rewards else "Inspect Starter Gear"
		"forge":
			return "Unlocked" if "law_forge_unlock" in earned_rewards else "Sealed"
		"training":
			return "Verified" if _training_verified(progression) else "Unverified"
		"proxy":
			if bool(progression.get("proxy_unlocked", false)):
				return "Unlocked"
			var proxy_reason := String(_hub._unlock_reasons.get("proxy", ""))
			if proxy_reason.is_empty():
				return "Sealed"
			return "Sealed · %s" % proxy_reason
	return ""


func _player_nav_node_label() -> String:
	## Only an authored objective reaches the player; an unauthored or side node
	## keeps the existing neutral wording instead of leaking an internal id.
	var next_id := String(_hub._campaign_snapshot.get("next_mainline_node_id", ""))
	if _SHORT_NODE_LABELS.has(next_id):
		return String(_SHORT_NODE_LABELS[next_id])
	return "Side-Contract Retest" if next_id.is_empty() else "Ready to Challenge"


func _early_progress_text(progression: Dictionary) -> String:
	var colossus_done := bool(progression.get("threshold_colossus_defeated", false))
	var auto_wins := maxi(0, int(progression.get("auto_contract_wins", 0)))
	var complete := bool(progression.get("early_game_complete", false))
	var training_done := _training_verified(progression)
	return "Build %s · Colossus %s · Auto %s" % [
		"✓" if training_done else "…",
		"✓" if colossus_done or auto_wins > 0 or complete else "…",
		"✓" if auto_wins > 0 or complete else "…",
	]


## One derivation for every "training verified" read: the world nameplate used
## to check only the exponential-report heuristic while the progress line read
## the authored completion keys, so a finished training still read Unverified.
func _training_verified(progression: Dictionary) -> bool:
	return bool(progression.get(
		"build_training_complete",
		progression.get("training_complete",
		progression.get("all_builds_verified",
			_profile_training_complete()
			or bool(progression.get("threshold_colossus_defeated", false))
			or maxi(0, int(progression.get("auto_contract_wins", 0))) > 0
			or bool(progression.get("early_game_complete", false))
		))
	))


func _next_objective_text() -> String:
	var next_id := String(_hub._campaign_snapshot.get("next_mainline_node_id", ""))
	match next_id:
		"tutorial_ranger_basics":
			return "Complete Ranger Basics"
		"mainline_01_first_hunt":
			return FIRST_HUNT_OBJECTIVE_TEXT
		"mainline_02_priority_under_pressure":
			return "Contract Board: ranged and charging foes"
		"mainline_03_first_elite":
			return "Defeat your first elite for Breeding Split"
		"mainline_04_hazard_and_forge":
			return "Cross the hazards to unlock Law Token forging"
		"mainline_05_growth_gate":
			return "Fix your build and pass the growth threshold"
		"threshold_colossus":
			return "Prepare to challenge the Threshold Colossus"
		"auto_certification":
			return "Install four Common cores; complete an Auto trial"
	if bool(_hub._campaign_snapshot.get("early_game_complete", false)):
		return "Chapter complete: try side contracts"
	return "Visit the Contract Board"


func _first_hunt_pending() -> bool:
	## The one window where the broad story objective used to hide the actual
	## departure step. Completed or later nodes fall through to their own copy.
	if String(_hub._campaign_snapshot.get("next_mainline_node_id", "")) != "mainline_01_first_hunt":
		return false
	return not UiKit.as_array(UiKit.as_dictionary(_hub._profile.get("progression", {})).get("completed_node_ids", [])).has("mainline_01_first_hunt")


func _displayed_objective_text() -> String:
	var story_objective := UiKit.as_dictionary(_hub._story_snapshot.get("current_objective", {}))
	var story_text := String(story_objective.get("text", ""))
	if _first_hunt_pending():
		return FIRST_HUNT_OBJECTIVE_TEXT
	## A story objective whose own campaign node is already complete is stale:
	## the requirements only look backward, so fall through to the live
	## campaign step instead of pinning an already-done goal on the header.
	var story_node := String(story_objective.get("campaign_node", ""))
	var completed_nodes := UiKit.as_array(UiKit.as_dictionary(_hub._profile.get("progression", {})).get("completed_node_ids", []))
	if not story_text.is_empty() and (story_node.is_empty() or not completed_nodes.has(story_node)):
		return story_text
	return _next_objective_text()


func _profile_training_complete() -> bool:
	var training := UiKit.as_dictionary(_hub._profile.get("training", {}))
	var reports_by_fingerprint := UiKit.as_dictionary(training.get("reports_by_fingerprint", {}))
	for fingerprint: Variant in reports_by_fingerprint:
		var report := UiKit.as_dictionary(reports_by_fingerprint.get(fingerprint, {}))
		if String(fingerprint).strip_edges().is_empty():
			continue
		if String(report.get("build_fingerprint", "")).strip_edges() != String(fingerprint).strip_edges():
			continue
		if String(report.get("state", "")).strip_edges().to_lower() == "exponential":
			return true
	return false
