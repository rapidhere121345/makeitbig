class_name PlayerFacingStatus
extends RefCounted

## Single boundary between stable internal result codes and text shown to a
## player. Domain code keeps emitting compact machine-readable errors for tests,
## logs and transactions; every screen passes its status through this formatter.

const GENERIC_FAILURE := "The action could not be completed. Select again and retry."

const ERROR_MESSAGES := {
	"wrong_route": "This page has changed. Go back and try again.",
	"unknown_facility": "This facility is currently unavailable.",
	"action_unavailable": "This action is not yet available.",
	"profile_required": "No profile is available. Start a new game first.",
	"invalid_profile": "Invalid profile data. Start a new test profile.",
	"unsupported_schema_version": "This test profile is from an older version. Start a new game.",
	"invalid_class": "This class is not yet available.",
	"unknown_preset": "This build preset could not be found.",
	"invalid_active_build": "Your equipment cannot form a valid build. Adjust your loadout.",
	"active_build_invalid": "Your equipment cannot form a valid build. Adjust your loadout.",
	"build_resolution_failed": "Your equipment could not be resolved. Select it again.",
	"content_unavailable": "Game content could not be loaded. Go back and retry.",
	"invalid_instance_id": "Invalid equipment ID. Select the item again.",
	"invalid_item": "This item's data is incomplete and it cannot be used.",
	"invalid_item_instance": "This item's data is incomplete and it cannot be used.",
	"item_not_owned": "This item is no longer in storage. Refresh the list.",
	"equipped_item_not_owned": "Your equipped-item record is outdated. Select your equipment again.",
	"item_already_equipped": "This item is already equipped.",
	"item_equipped": "Unequip this item before salvaging it.",
	"protected_item": "Starter equipment is protected and cannot be salvaged.",
	"slot_not_prototype_open": "This equipment slot is not yet available.",
	"forge_locked": "Complete Main Quest 04 to unlock Law Token forging.",
	"unknown_operation": "Choose Inscribe, Rewrite, or Refine.",
	"inscribe_not_legal": "This item has no eligible new affix to inscribe.",
	"rewrite_not_legal": "This affix has no eligible family to rewrite.",
	"refine_not_legal": "This affix is already at its highest tier and cannot be refined.",
	"invalid_page": "This candidate page has expired. Start a new forecast.",
	"insufficient_law_tallies": "Not enough matching Law Tokens to reveal or commit.",
	"forge_session_required": "Start a Law Token forecast first.",
	"stale_forge_session": "This forecast has expired. Start a new one.",
	"stale_target": "The target item has changed. Select it again.",
	"candidate_not_revealed": "This future outcome has not been revealed.",
	"candidate_not_selected": "Select a revealed future outcome first.",
	"commit_pending": "The previous commit is still processing. Please wait.",
	"invalid_commit_token": "This commit confirmation has expired. Select the outcome again.",
	"save_failed": "The profile could not be saved. Equipment and Law Tokens are unchanged; please retry.",
	"invalid_contract_id": "Select an available contract.",
	"invalid_mode": "Choose Manual or Auto mode.",
	"invalid_seed": "The contract seed must be a valid integer.",
	"invalid_room_count": "Invalid contract room count.",
	"contract_locked": "This contract's unlock requirements have not been met.",
	"mode_not_allowed": "This contract does not allow the selected mode.",
	"proxy_locked": "Auto is locked. Defeat the Threshold Colossus in Manual first.",
	"pending_contract_required": "Select and prepare a contract first.",
	"active_session_required": "No contract is currently in progress.",
	"active_session_exists": "A contract is already in progress.",
	"result_pending": "This contract is still being settled.",
	"ending_locked": "Complete the early graduation contract to enter the epilogue.",
	"no_pending_route": "No page is pending.",
	"invalid_payload": "Invalid action data. Please try again.",
	"invalid_last_result": "The latest contract result is invalid.",
	"invalid_safe_route": "The saved return location is invalid.",
	"room_runtime_factory_failed": "The combat scene could not be created. Return to the Contract Board and retry.",
	"room_runtime_start_failed": "Combat could not start. Return to the Contract Board and retry.",
	"profile_creation_failed": "The new profile could not be created. Please retry.",
	"campaign_progress_invalid": "Campaign progress could not be read. Start a new test profile.",
	"contract_plan_failed": "Contract content could not be generated. Select the contract again.",
	"contract_prepare_failed": "Contract preparation failed. Select the contract again.",
	"session_start_failed": "The contract could not start. Enter it again.",
	"session_complete_failed": "Contract settlement failed. Please retry.",
	"unknown_error": GENERIC_FAILURE,
}

const STATUS_MESSAGES := {
	"Tutorial complete": "Ranger basics tutorial complete",
	"New profile saved": "New profile saved",
	"Profile saved": "Profile saved",
	"Contract result saved": "Contract result saved",
	"Epilogue checkpoint saved": "Epilogue checkpoint saved",
	"Contract preparation cancelled.": "Contract preparation cancelled.",
	"No valid profile is available.": "No valid profile is available to continue.",
}

const FAILURE_PREFIXES := {
	"Forge rejected: ": "Forge",
	"Target selection failed: ": "Select Forge Target",
	"Build selection failed: ": "Switch Build",
	"Training failed: ": "Training",
	"Equipment change failed: ": "Change Equipment",
	"Salvage failed: ": "Salvage",
}

## Settlement keeps these source ids as authority/telemetry data. This table is
## the presentation boundary: no entity number or machine token reaches a player.
const ENEMY_FAILURE_SOURCE_LABELS := {
	"melee_pursuer": "Melee Pursuer",
	"charging_raider": "Charging Raider",
	"fan_ranged": "Fan-Shot Hunter",
}
const BOSS_FAILURE_SOURCE_LABELS := {
	"slam": "Threshold Colossus slam",
	"sweep": "Threshold Colossus sweep",
	"lane": "Threshold Colossus fireline",
}
const HAZARD_FAILURE_SOURCE_LABELS := {
	"exposed_ground_zone": "Exposed ground hazard",
	"moving_fireline": "Moving Fireline",
}
const UNKNOWN_FAILURE_SOURCE := "Unknown finishing source"


static func error_message(error_code: String) -> String:
	var code := error_code.strip_edges()
	if code.is_empty():
		return GENERIC_FAILURE
	return String(ERROR_MESSAGES.get(code, GENERIC_FAILURE))


static func failure(action: String, error_code: String) -> String:
	var label := action.strip_edges()
	if label.is_empty():
		return error_message(error_code)
	return "%s failed: %s" % [label, error_message(error_code)]


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
			return String(STATUS_MESSAGES[raw_status]) + suffix

	for raw_prefix: String in FAILURE_PREFIXES:
		if text.begins_with(raw_prefix):
			return failure(String(FAILURE_PREFIXES[raw_prefix]), text.trim_prefix(raw_prefix))

	if text.begins_with("SAVE FAILED:"):
		return error_message("save_failed")
	if text.begins_with("Save unavailable: "):
		return "Save unavailable: %s" % _detail_message(text.trim_prefix("Save unavailable: "))
	if text.begins_with("Save ignored: "):
		return "Invalid save ignored: %s" % _detail_message(text.trim_prefix("Save ignored: "))
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
