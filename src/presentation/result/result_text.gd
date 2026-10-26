class_name ResultText
extends RefCounted
## Player-facing copy for the contract settlement, extracted from ResultScreen.
## Every function is static and takes the settlement payload (and the contract
## when it reads one) explicitly, so the formatting is pure: nothing here reads
## screen state or draws a node. The label tables and metric lists the copy is
## built from live here too.

const PlayerFacingStatusScript = preload("res://src/presentation/player_facing_status.gd")
const ShellThemeScript = preload("res://src/presentation/shell_theme.gd")
const UiKit := preload("res://src/presentation/ui_kit.gd")

const EMPTY_FACTS_TEXT := "This result has no report fields; use the result, time, and room progress shown above."
const NO_REWARD_TEXT := "No loot records."

## The metric row, in reading order. Each entry is one authoritative field of the
## settlement payload; a metric the payload does not carry is hidden, never shown
## as a zero, while a metric that really is 0 is drawn as the reading it is.
const METRICS: Array = [
	{"key": "outcome", "label": "Result"},
	{"key": "elapsed", "label": "Actual Time"},
	{"key": "kills", "label": "Kills"},
	{"key": "casts", "label": "Casts"},
	{"key": "rooms", "label": "Room Progress"},
]

## The settlement's own run totals and one room's readings, in reading order: the
## metric key to read and the label the detail table prints it under. Both lists are
## built from fields the payload reports, so an entry that was never carried names
## itself unrecorded instead of appearing as a zero.
const TOTAL_FIELDS: Array = [
	{"key": "ticks", "label": "Authoritative Tick"},
	{"key": "elapsed", "label": "Actual Time"},
	{"key": "casts", "label": "Casts"},
	{"key": "kills", "label": "Kills"},
]
const ROOM_FIELDS: Array = [
	{"key": "kills", "label": "Kills"},
	{"key": "casts", "label": "Casts"},
	{"key": "ticks", "label": "Tick"},
	{"key": "elapsed", "label": "Time"},
]

const OUTCOME_LABELS := {
	"victory": "Victory",
	"final_victory": "Final Victory",
	"defeat": "Failure",
	"abandoned": "Aborted",
	"error": "Error",
}

## Reward fields this screen formats as player copy. Anything else in `rewards`
## is listed verbatim in the detail block instead of being dropped.
const REWARD_FIELD_LABELS := {
	"contract_wins_delta": "Contract Wins",
	"repeatable_attempt_number": "Repeat Side Runs",
}
const LAW_TALLY_LABELS := {
	"inscribe": "Inscribe Law Tokens",
	"rewrite": "Rewrite Law Tokens",
	"refine": "Refine Law Tokens",
}
## The timed-bonus pair is one line, and only when the run really had a bonus in
## play: the payload sets exactly one flag for a timed objective and leaves both
## false when there was nothing to lose, so a settled room never claims a loss it
## did not take.
const TIMED_BONUS_LABEL := "Timed Bonus"

const FIRST_REWARD_LABELS := {
	"starter_loadout": "Fixed starter equipment equipped",
	"hunter_mark_skill": "New skill: Hunter's Mark (Skill Slot 2)",
	"dash_skill": "New skill: Dash (Skill Slot 3)",
	"equipment_compare_unlock": "Equipment comparison unlocked",
	"breeding_split_item": "Breeding Split equipment added to storage",
	"law_forge_unlock": "Law Token Forge unlocked",
	"pack_hunt_mark_item": "Pack Hunt Mark equipment added to storage",
	"early_campaign_complete": "Early journey complete: manual combat and proxy expeditions mastered",
}
## Skill grants get their own compact cue (name, authored battle key, slot and a
## next-use hint), because the bare "N First-Clear Rewards" counter let the new skill go
## unnoticed. It renders only from the settlement's own first_reward_tags, so a
## repeat run never shows it; keys mirror the arena HUD slot keys.
const FIRST_SKILL_CUES := {
	"hunter_mark_skill": {"name": "Hunter's Mark", "key": "Q", "slot": "Skill Slot 2", "skill_id": "hunter_mark", "slot_index": 1, "hint": "Press Q in combat to mark a target"},
	"dash_skill": {"name": "Dash", "key": "E", "slot": "Skill Slot 3", "skill_id": "dash", "slot_index": 2, "hint": "Press E in combat to dash"},
}

## The fixed four white cores, in the order the proxy bay grants them.
const PROXY_CORE_LABELS := {
	"near_enemy_horizon": "Near-Enemy Sight",
	"nearest_enemy": "Perception Core",
	"perception": "Perception Core",
	"direct_gait": "Direct-Approach Legs",
	"movement": "Action Core",
	"action": "Action Core",
	"single_key_execution": "Single-Key Executor",
	"execution": "Execution Core",
	"short_trace_memory": "Short-Trace Memory",
	"memory": "Memory Core",
}
const PROXY_CORE_FALLBACK: Array[String] = ["Perception Core", "Action Core", "Execution Core", "Memory Core"]
const FIXED_CORE_IDS: Array[String] = ["near_enemy_horizon", "direct_gait", "single_key_execution", "short_trace_memory"]


static func outcome_text(outcome: String) -> String:
	var normalized := outcome.to_lower()
	if normalized.is_empty():
		return "Not Recorded"
	if OUTCOME_LABELS.has(normalized):
		return String(OUTCOME_LABELS[normalized])
	return normalized.to_upper()


static func outcome_color(outcome: String) -> Color:
	if outcome in ["victory", "final_victory"]:
		return ShellThemeScript.PROXY
	if outcome in ["defeat", "error"]:
		return ShellThemeScript.WARNING
	return ShellThemeScript.BONE


## The copy for one metric of METRICS, or empty when the source does not report
## that field at all. Nothing on this path is defaulted to zero.
static func reading_text(key: String, source: Dictionary) -> String:
	match key:
		"outcome":
			return outcome_text(String(source.get("outcome", "unknown")).to_lower())
		"elapsed":
			return elapsed_text(source)
		"kills":
			return count_text(source, ["defeated", "kills"])
		"casts":
			return count_text(source, ["casts", "shots"])
		"rooms":
			return rooms_text(source)
		"ticks":
			return count_text(source, ["ticks"])
	return ""


static func metric_color(key: String, outcome: String) -> Color:
	return outcome_color(outcome) if key == "outcome" else ShellThemeScript.BONE


## The run time in seconds, or empty when the settlement reports none.
static func elapsed_text(source: Dictionary) -> String:
	var value: Variant = reported_number(source, ["elapsed_seconds", "elapsed", "time"])
	return "%.2f s" % float(value) if value != null else ""


## One reported count as copy, or empty when the source reports none.
static func count_text(source: Dictionary, keys: Array) -> String:
	var value: Variant = reported_number(source, keys)
	return str(int(value)) if value != null else ""


## The first of the keys a source really reports as a number, or null when it
## reports none of them. A field that is present but not numeric counts as not
## reported: a reading that was never made is not rounded into a 0.
static func reported_number(source: Dictionary, keys: Array) -> Variant:
	for raw_key in keys:
		var key := String(raw_key)
		if not source.has(key):
			continue
		var value: Variant = source.get(key)
		if value is int or value is float:
			return float(value)
		if value is String and String(value).is_valid_float():
			return float(String(value))
	return null


## "Completed / Total" from the two authoritative fields, or empty when the payload does
## not carry them: no room count is claimed that was not reported.
static func rooms_text(source: Dictionary) -> String:
	var has_completed := source.has("rooms_completed")
	var has_total := source.has("room_count")
	if has_completed and has_total:
		return "%d / %d" % [coerce_int(source.get("rooms_completed", 0)), coerce_int(source.get("room_count", 0))]
	if has_completed:
		return "%d" % coerce_int(source.get("rooms_completed", 0))
	return ""


static func room_results(result: Dictionary) -> Array:
	var value: Variant = result.get("room_results", [])
	return value if value is Array else []


static func run_facts_text(result: Dictionary, contract: Dictionary) -> String:
	var lines: Array[String] = []
	var contract_id := first_text([result.get("contract_id", ""), contract.get("contract_id", "")])
	if not contract_id.is_empty():
		lines.append("Contract: %s" % contract_id)
	var mode := first_text([result.get("mode", ""), contract.get("mode", "")])
	if not mode.is_empty():
		lines.append("Mode: %s" % mode)
	var rooms := rooms_text(result)
	if not rooms.is_empty():
		lines.append("Rooms: %s Complete" % rooms)
	var outcomes: Array[String] = []
	for entry in room_results(result):
		if entry is Dictionary:
			outcomes.append(outcome_text(String((entry as Dictionary).get("outcome", "")).to_lower()))
	if not outcomes.is_empty():
		lines.append("Room Results: %s" % ", ".join(outcomes))
	var failure_reason := first_text([result.get("failure_reason", "")])
	if not failure_reason.is_empty():
		lines.append("End Reason: %s" % failure_source_text(failure_reason))
	var error_code := first_text([result.get("error", "")])
	if not error_code.is_empty():
		lines.append("Error Code: %s" % error_code)
	if lines.is_empty():
		return EMPTY_FACTS_TEXT
	return "\n".join(lines)


static func reward_lines(result: Dictionary, rewards: Dictionary, equipment_items: Array, proxy_items: Array = []) -> Array[String]:
	var lines: Array[String] = []
	if is_first_proxy_unlock(result, rewards):
		lines.append("Proxy Bay Unlocked!")
		lines.append("Four fixed Common cores obtained: %s" % ", ".join(proxy_core_names(result, rewards)))
		lines.append("Next Step: visit the Proxy Bay for Auto contracts")
	var first_reward := first_reward_text(result)
	if not first_reward.is_empty():
		lines.append(first_reward)
	if not equipment_items.is_empty():
		lines.append("Equipment Gained: %d Items" % equipment_items.size())
	if not proxy_items.is_empty():
		lines.append("Proxy component stored · Not Installed")
		lines.append("Current proxy build unchanged")
	lines.append_array(reward_field_lines(rewards))
	var drop := drop_line(result, rewards)
	if not drop.is_empty():
		lines.append(drop)
	if lines.is_empty():
		lines.append(NO_REWARD_TEXT)
	return lines


static func compact_reward_text(result: Dictionary, rewards: Dictionary, equipment_items: Array, proxy_items: Array) -> String:
	var parts: Array[String] = []
	if not equipment_items.is_empty():
		parts.append("New Equipment: %d Items" % equipment_items.size())
	if is_first_proxy_unlock(result, rewards):
		parts.append("Proxy Cores: %d" % proxy_core_names(result, rewards).size())
	if not proxy_items.is_empty():
		parts.append("Proxy Components: %d" % proxy_items.size())
	var first_rewards := first_reward_text(result).split("\n")
	if first_rewards.size() > 1:
		parts.append("First Clears: %d" % (first_rewards.size() - 1))
	var tally_delta := UiKit.as_dictionary(rewards.get("law_tallies_delta", {}))
	var tally_total := 0
	for operation in ["inscribe", "rewrite", "refine"]:
		tally_total += coerce_int(tally_delta.get(operation, 0))
	if tally_total != 0:
		parts.append("Law Tokens %+d" % tally_total)
	var drop := drop_line(result, rewards)
	if not drop.is_empty():
		parts.append(drop.split(": ")[-1].strip_edges() if drop.contains(": ") else drop)
	return " · ".join(parts) if not parts.is_empty() else NO_REWARD_TEXT


static func settlement_headline(result: Dictionary, outcome: String, equipment_count: int, proxy_component_count: int) -> String:
	var outcome_copy := outcome_text(outcome)
	var first_reward := first_reward_headline(result)
	var acquisition := ""
	if equipment_count > 0:
		acquisition = "New Equipment: %d Items" % equipment_count
	elif proxy_component_count > 0:
		acquisition = "Proxy Components: %d" % proxy_component_count
	elif is_first_proxy_unlock(result, UiKit.as_dictionary(result.get("rewards", {}))):
		acquisition = "Proxy Bay Unlocked"
	if not first_reward.is_empty():
		acquisition = first_reward if acquisition.is_empty() else "%s · %s" % [acquisition, first_reward]
	if acquisition.is_empty():
		return outcome_copy
	return "%s · %s" % [outcome_copy, acquisition]


static func next_step_text(result: Dictionary, outcome: String, equipment_count: int, proxy_component_count: int) -> String:
	if equipment_count > 0:
		return "Compare new equipment, then return to town to prepare"
	if proxy_component_count > 0:
		return "Proxy component stored; install it after returning to town"
	if is_first_proxy_unlock(result, UiKit.as_dictionary(result.get("rewards", {}))):
		return "Proxy Bay unlocked; return to town to install cores"
	if outcome in ["defeat", "error"]:
		return "Review the battle report, then return to town to adjust"
	if outcome == "final_victory":
		return "View the epilogue"
	return "Return to town or depart again"


static func first_reward_headline(result: Dictionary) -> String:
	var lines := first_reward_text(result).split("\n")
	if lines.size() <= 1:
		return ""
	if lines.size() == 2:
		var line := String(lines[1])
		return line.get_slice("(", 0)
	return "%d First-Clear Rewards" % (lines.size() - 1)


## Known reward fields written as Chinese player copy. A zero delta stays out (it is
## not a reward), and the boolean bonus pair reports a real loss as Not Obtained.
static func reward_field_lines(rewards: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var bonus_earned := bool(rewards.get("bonus_earned", false))
	var bonus_lost := bool(rewards.get("bonus_lost", false))
	if bonus_earned != bonus_lost:
		lines.append("%s: %s" % [TIMED_BONUS_LABEL, "Obtained" if bonus_earned else "Not Obtained"])
	var tally_delta := UiKit.as_dictionary(rewards.get("law_tallies_delta", {}))
	for operation in ["inscribe", "rewrite", "refine"]:
		var tally_amount := coerce_int(tally_delta.get(operation, 0))
		if tally_amount != 0:
			lines.append("%s: %d" % [String(LAW_TALLY_LABELS[operation]), tally_amount])
	for key in REWARD_FIELD_LABELS:
		var field := String(key)
		if not rewards.has(field):
			continue
		var amount := coerce_int(rewards.get(field, 0))
		if amount == 0:
			continue
		lines.append("%s: %d" % [String(REWARD_FIELD_LABELS[field]), amount])
	return lines


static func drop_line(result: Dictionary, rewards: Dictionary) -> String:
	var text_value := scalar_text(drop_value(result, rewards)).strip_edges()
	if text_value.is_empty():
		return ""
	return "Normal Drops: %s" % text_value


## The ordinary drop of this settlement: an explicit `drop` / `last_drop` field
## first, then the reward block's label or id. A compound value is not printable as
## player copy and is listed raw in Calculation Details instead of being dumped into a line.
static func drop_value(result: Dictionary, rewards: Dictionary) -> Variant:
	for key in ["drop", "last_drop"]:
		if result.has(key):
			return result.get(key)
	for key in ["drop_label", "drop_id"]:
		if rewards.has(key):
			return rewards.get(key)
	return null


static func first_reward_text(result: Dictionary) -> String:
	var value: Variant = result.get("first_reward_tags", [])
	if not (value is Array):
		return ""
	var lines: Array[String] = []
	for tag_value in (value as Array):
		var tag := String(tag_value)
		if FIRST_REWARD_LABELS.has(tag):
			lines.append(String(FIRST_REWARD_LABELS[tag]))
	return "First-Clear Rewards\n%s" % "\n".join(lines) if not lines.is_empty() else ""


static func is_first_proxy_unlock(result: Dictionary, rewards: Dictionary) -> bool:
	for source in [result, rewards]:
		if bool(source.get("first_proxy_unlock", source.get("proxy_unlocked", false))):
			return true
		for key in ["unlock", "unlocks", "proxy_unlock"]:
			var value: Variant = source.get(key, null)
			if value is Dictionary:
				var data: Dictionary = value
				if bool(data.get("proxy_unlocked", false)):
					return true
				if bool(data.get("first", data.get("first_time", false))) and bool(data.get("proxy", data.get("proxy_unlocked", data.get("unlocked", true)))):
					return true
				if String(data.get("id", data.get("type", ""))).to_lower() in ["proxy", "proxy_bay"] and bool(data.get("unlocked", true)):
					return true
			elif value is Array:
				for item in value:
					if String(item).to_lower() in ["proxy", "proxy_bay", "proxy_unlocked"]:
						return true
	return false


## The granted components as display names, in payload order. Never padded: an
## unlock block lists exactly what the settlement granted.
static func proxy_core_names(result: Dictionary, rewards: Dictionary) -> Array[String]:
	var values: Array = []
	for source in [result, rewards]:
		for key in ["proxy_cores", "cores"]:
			if source.get(key, null) is Array:
				values = source.get(key)
				break
		if values.is_empty():
			var unlock := UiKit.as_dictionary(source.get("unlock", source.get("unlocks", {})))
			var components: Variant = unlock.get("cores", unlock.get("components", null))
			values = components if components is Array else []
		if not values.is_empty():
			break
	var names: Array[String] = []
	for value in values:
		var core_id := String((value as Dictionary).get("id", "")) if value is Dictionary else String(value)
		var core_name := String((value as Dictionary).get("name", "")) if value is Dictionary else ""
		if core_name.is_empty():
			core_name = String(PROXY_CORE_LABELS.get(core_id.to_lower(), core_id))
		if not core_name.is_empty():
			names.append(core_name)
	if names.is_empty():
		names = PROXY_CORE_FALLBACK.duplicate()
	return names


static func proxy_component_entries(result: Dictionary) -> Array:
	var value: Variant = result.get("proxy_component_drops", null)
	if not value is Array:
		return []
	var entries: Array = []
	for item_value in value as Array:
		if not item_value is Dictionary:
			continue
		var item := item_value as Dictionary
		if String(item.get("id", "")).strip_edges().is_empty():
			continue
		entries.append(item.duplicate(true))
	return entries


static func proxy_slot_label(slot: String) -> String:
	return String({
		"perception": "Perception Slot",
		"movement": "Action Slot",
		"execution": "Execution Slot",
		"memory": "Memory Slot",
	}.get(slot, slot if not slot.is_empty() else "Unknown Slot"))


static func equipment_entries(result: Dictionary, rewards: Dictionary) -> Array:
	var drops_value: Variant = rewards.get("equipment_drops", result.get("equipment_drops", null))
	if not (drops_value is Array):
		return []
	var count_value: Variant = rewards.get("equipment_drop_count", result.get("equipment_drop_count", null))
	var declared_count := -1
	if count_value is int or count_value is float:
		declared_count = int(count_value)
		if declared_count <= 0:
			return []
	elif count_value is String and String(count_value).is_valid_int():
		declared_count = int(String(count_value))
		if declared_count <= 0:
			return []
	var entries: Array = []
	for item in drops_value:
		if not (item is Dictionary):
			continue
		var entry: Dictionary = item
		if not entry.has("slot") or not entry.has("base_item_id"):
			continue
		if not (entry.get("slot") is String) or not (entry.get("base_item_id") is String):
			continue
		entries.append(entry)
		if declared_count > 0 and entries.size() >= declared_count:
			break
	return entries


## The authoritative field table behind the summary: contract, mode, preset, seed,
## the run totals and one line per room. Values are printed as they stand.
static func detail_lines(result: Dictionary, contract: Dictionary, art_error: String) -> Array[String]:
	var lines: Array[String] = []
	lines.append("Contract ID: %s" % or_unrecorded(first_text([result.get("contract_id", "")])))
	lines.append("Mode: %s" % or_unrecorded(first_text([result.get("mode", ""), contract.get("mode", "")])))
	lines.append("Preset: %s" % or_unrecorded(first_text([result.get("preset_id", "")])))
	lines.append("Seed: %s" % or_unrecorded(first_text([result.get("seed", "")])))
	lines.append("Runtime Readings: %s" % run_totals_text(result))
	var rooms := rooms_text(result)
	if not rooms.is_empty():
		lines.append("Rooms: %s Complete" % rooms)
	var results := room_results(result)
	for index in results.size():
		var entry: Variant = results[index]
		if not (entry is Dictionary):
			continue
		var room: Dictionary = entry
		lines.append("Room %d: %s" % [index + 1, room_reading_text(room)])
		var room_report := first_text([room.get("report", "")])
		if not room_report.is_empty():
			lines.append("Room %d Report: %s" % [index + 1, room_report])
		var room_failure := first_text([room.get("failure_reason", "")])
		if not room_failure.is_empty():
			lines.append("Room %d End Reason: %s" % [index + 1, failure_source_text(room_failure)])
	if not art_error.is_empty():
		lines.append("Icon Resource: %s" % art_error)
	return lines


## The settlement's own run totals, assembled only from the fields it reports. A
## field that was never carried makes the line say Not Recorded instead of appearing as
## a zero; a field that really is 0 is printed as the reading it is.
static func run_totals_text(result: Dictionary) -> String:
	var totals := fields_text(result, TOTAL_FIELDS)
	return totals if not totals.is_empty() else "Not Recorded"


## One room's own readings, printed as far as that room really reported them.
static func room_reading_text(room: Dictionary) -> String:
	var outcome := "Result %s" % outcome_text(String(room.get("outcome", "")).to_lower())
	var readings := fields_text(room, ROOM_FIELDS)
	return outcome if readings.is_empty() else "%s    %s" % [outcome, readings]


## The listed readings a source really reports, as "label: value" pairs. Nothing
## is filled in for a field the source does not carry.
static func fields_text(source: Dictionary, fields: Array) -> String:
	var parts: Array[String] = []
	for field_value in fields:
		var field: Dictionary = field_value
		var reading := reading_text(String(field["key"]), source)
		if not reading.is_empty():
			parts.append("%s: %s" % [String(field["label"]), reading])
	return "    ".join(parts)


## Raw disclosure: every dropped instance at full length, its source, and any field
## outside the known table, printed as it stands. This is where metadata the screen
## does not turn into player copy is surfaced instead of being dropped.
static func detail_raw_lines(result: Dictionary, drop_field_texts: Array[String]) -> Array[String]:
	var lines: Array[String] = []
	if not drop_field_texts.is_empty():
		lines.append("Full Drop Fields (Untruncated):")
		for field_text in drop_field_texts:
			lines.append("· %s" % field_text)
	# Only in the explicit detail drawer: future fields remain inspectable
	# without inferring their units or maintaining another authority schema.
	lines.append("Full Settlement Record (Additional Fields Included, No Conversion):")
	lines.append(JSON.stringify(presentation_payload(result)))
	return lines


## The authority payload itself stays untouched in `result`. Only this copy for
## the visible disclosure replaces failure source ids, including nested rooms.
static func presentation_payload(value: Variant) -> Variant:
	if value is Dictionary:
		var displayed: Dictionary = {}
		for raw_key in (value as Dictionary):
			var key := String(raw_key)
			var raw_value: Variant = (value as Dictionary)[raw_key]
			displayed[raw_key] = failure_source_text(String(raw_value)) if key == "failure_reason" else presentation_payload(raw_value)
		return displayed
	if value is Array:
		var displayed_items: Array = []
		for item in (value as Array):
			displayed_items.append(presentation_payload(item))
		return displayed_items
	return value


## A scalar as copy, or empty when the value is not one (compounds belong to the raw
## detail block, never to a player-facing line).
static func scalar_text(value: Variant) -> String:
	if value == null:
		return ""
	if value is bool or value is int or value is float or value is String:
		return str(value)
	return ""


static func first_text(values: Array) -> String:
	for value in values:
		if value is String:
			var text_value := String(value).strip_edges()
			if not text_value.is_empty():
				return text_value
		elif value is int or value is float:
			return str(value)
	return ""


static func or_unrecorded(text_value: String) -> String:
	return text_value if not text_value.is_empty() else "Not Recorded"


static func failure_source_text(value: String) -> String:
	return PlayerFacingStatusScript.failure_source_label(value)


static func defeat_diagnosis_text(result: Dictionary) -> String:
	if String(result.get("outcome", "unknown")).to_lower() != "defeat":
		return ""
	var bottleneck_value: Variant = result.get("primary_bottleneck", null)
	if not (bottleneck_value is Dictionary):
		return ""
	var bottleneck: Dictionary = bottleneck_value
	var title := String(bottleneck.get("title", "")).strip_edges()
	var action := String(bottleneck.get("action", "")).strip_edges()
	if title.is_empty() and action.is_empty():
		return ""
	var lines: Array[String] = []
	if not title.is_empty():
		lines.append("Main Failure Cause: %s" % title)
	if not action.is_empty():
		lines.append("Suggested Action: %s" % action)
	return "\n".join(lines)


static func defeat_report_text(result: Dictionary) -> String:
	if String(result.get("outcome", "unknown")).to_lower() != "defeat":
		return ""
	var report_value: Variant = result.get("report", "")
	if not (report_value is String):
		return ""
	var report := String(report_value).strip_edges()
	if report.is_empty():
		return ""
	return "Battle Report: %s" % report


static func coerce_int(value: Variant) -> int:
	if value is int:
		return int(value)
	if value is float:
		return int(value)
	if value is bool:
		return 1 if bool(value) else 0
	if value is String and String(value).is_valid_int():
		return int(String(value))
	return 0


static func first_skill_cues(result: Dictionary) -> Array[Dictionary]:
	## Only tags the settlement itself granted this run; the payload is empty on
	## repeat completions, so the cue can never re-announce an old reward.
	var value: Variant = result.get("first_reward_tags", [])
	var cues: Array[Dictionary] = []
	if not (value is Array):
		return cues
	for tag_value in (value as Array):
		var tag := String(tag_value)
		if FIRST_SKILL_CUES.has(tag):
			cues.append(FIRST_SKILL_CUES[tag])
	return cues


## Only observed room results become nodes. Missing room records stay missing;
## a supplied room_count is a progress denominator, never permission to fabricate
## unvisited/failed rooms or projectile event branches.
static func reported_route_steps(result: Dictionary) -> Array:
	var steps: Array = []
	for index in room_results(result).size():
		var raw: Variant = room_results(result)[index]
		var room := UiKit.as_dictionary(raw)
		var outcome := String(room.get("outcome", "")).to_lower()
		var state := "unknown"
		if outcome in ["victory","final_victory"]: state = "completed"
		elif outcome in ["defeat","error"]: state = "failed"
		var title := "Room %d" % (index+1)
		var subtitle := outcome_text(outcome) if not outcome.is_empty() else "Not Recorded"
		steps.append({"title":title,"state":state,"subtitle":subtitle})
	return steps
