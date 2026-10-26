class_name ArenaHudText
extends RefCounted
## Combat HUD copy helpers, extracted from ArenaHud. Every function is static
## and pure: it compresses or labels authoritative snapshot text for the HUD
## faces and never reads or draws HUD state.


static func compact_cell_state(node_name: String, text: String) -> String:
	if not text.contains("\n"):
		return short_cell_phrase(text)
	var lines := text.split("\n", false, 1)
	var first := String(lines[0]).strip_edges()
	var second := String(lines[1]).strip_edges() if lines.size() > 1 else ""
	match second:
		"Hold to Repeat":
			return "Repeating"
		"Next Shot Buffered", "Target Lock Buffered":
			return "Buffered"
		"Pointer Lock":
			return "Locked"
		"Proxy Cast":
			return "Proxy"
	if second.begins_with("Remaining "):
		return "Mark %s" % second.trim_prefix("Remaining ")
	if node_name == "Skill3Button" and second.begins_with("Cooldown "):
		return "Dash %s" % second.trim_prefix("Cooldown ")
	return first


## The combat face uses short established phrases and a separate numeric line.
## This is copy compression only; the complete authoritative state remains in the
## public skill_cell_detail value and the cell tooltip.
static func short_cell_phrase(value: String) -> String:
	if value.begins_with("Cooldown "):
		var suffix := value.trim_prefix("Cooldown ")
		if suffix.begins_with("<"):
			return "CD <0.1s"
		return "CD %s" % suffix
	return String({
		"Ready": "Ready",
		"No Target": "No Target",
		"Out of Range": "Too Far",
		"Unequipped": "Empty",
		"Combat Ended": "Ended",
		"Proxy Control": "Proxy",
		"AUTO Locked": "AUTO",
		"No Locked Target": "No Lock",
		"Locked Target Out of Range": "Too Far",
		"Target Lock Expired": "Lost Lock",
		"Pointer Lock": "Locked",
		"Next Shot Buffered": "Buffered",
		"Target Lock Buffered": "Buffered",
	}.get(value, value))


static func elite_mechanic_text(raw: String) -> String:
	var parts: Array[String] = []
	for entry in raw.split(","):
		match entry.strip_edges():
			"periodic_barrier:active": parts.append("Barrier Active · Circle Around and Wait for an Opening")
			"periodic_barrier:open": parts.append("Barrier Down · Focus Your Attacks")
			"summon_reinforcements:ready": parts.append("Reinforcements Pending · Elite Calls at Half Health")
			"summon_reinforcements:used": parts.append("Reinforcements Arrived · Watch for New Enemies")
	return "\n".join(parts)


static func encounter_status_text(raw: String) -> String:
	var names := {"moving_fireline":"Moving Fireline", "exposed_ground_zone":"Hazard Zone", "ground-zone":"Hazard Zone", "periodic_barrier":"Periodic Barrier", "summon_reinforcements":"Call Reinforcements"}
	var phases := {"warning":"Telegraphing", "windup":"Telegraphing", "active":"Active", "inactive":"Inactive", "cooldown":"Intermittent", "idle":"Intermittent", "open":"Vulnerable", "used":"Called", "ready":"Pending"}
	if raw in ["", "None"]: return "None"
	var parts: Array[String] = []
	for entry in raw.split(","):
		var pair := entry.strip_edges().split(":")
		var title := String(names.get(pair[0], "Special Effects"))
		parts.append(title + (" · " + String(phases.get(pair[1], "")) if pair.size() > 1 and phases.has(pair[1]) else ""))
	return ", ".join(parts)


## The strip keeps the meaning of the line and drops the two cumulative totals that the
## summary already carries: the running boss damage and the defeated counter. Only those
## two known keys are removed. A warning, a refusal reason or any other sentence the
## authority sends is passed through whole, so nothing is hidden behind a short label.
static func compact_feedback(value: String) -> String:
	var kept: Array[String] = []
	for part in value.split(" · "):
		var segment := part.strip_edges()
		if segment.is_empty() or segment.begins_with("Boss Damage") or segment.begins_with("Defeated"):
			continue
		kept.append(segment)
	return value.strip_edges() if kept.is_empty() else " · ".join(kept)


static func action_state(is_auto: bool, battle_over: bool, cooldown: float, has_target: bool, in_range: bool) -> String:
	if is_auto:
		return "Proxy Control"
	if battle_over:
		return "Combat Ended"
	if cooldown > 0.0:
		return cooldown_text(cooldown)
	if not has_target:
		return "No Target"
	if not in_range:
		return "Out of Range"
	return "Ready"


static func pointer_target_state(status: String, has_target: bool, in_range: bool) -> String:
	match status:
		"locked":
			return "Pointer Lock"
		"out_of_range":
			return "Locked Target Out of Range"
		"lost":
			return "Target Lock Expired"
		"no_pointer_target":
			return "No Locked Target"
	if not has_target:
		return "No Locked Target"
	if not in_range:
		return "Locked Target Out of Range"
	return "Pointer Lock"


## One simulated tick is 33ms, so a single remaining tick must not be printed as
## the ambiguous "0.0s"; the cell either shows the real seconds or is explicit
## that less than a tenth of a second remains.
static func cooldown_text(seconds: float) -> String:
	return "Cooldown <0.1s" if seconds < 0.05 else "Cooldown %.1fs" % seconds


static func proxy_failure_text(value: Variant) -> String:
	if not value is Dictionary or (value as Dictionary).is_empty():
		return "None"
	var failure := value as Dictionary
	var category := String(failure.get("category", "unknown"))
	var reason := String(failure.get("reason", "unknown"))
	var localized_category: String = String({
		"cooldown": "Cooldown",
		"timing": "Timing",
		"range": "Range",
		"target": "Target",
	}.get(category, category))
	var localized_reason := "Skill Not Ready" if reason in ["skill is not ready", "skill not ready"] else reason
	return "[%s] %s" % [localized_category, localized_reason]


static func growth_label(value: String) -> String:
	return {
		"convergent": "CONVERGENT",
		"critical": "CRITICAL",
		"exponential": "EXPONENTIAL",
	}.get(value.to_lower(), value.to_upper())


static func plain_number(value: float) -> String:
	return String.num(value, 0) if is_equal_approx(value, roundf(value)) else String.num(value, 1)
