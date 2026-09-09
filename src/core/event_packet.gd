class_name EventPacket
extends RefCounted

const BigValueType = preload("res://src/core/big_value.gd")

## A linear event plus the proof of the path it has already followed.
## remaining_lifetime is measured in caller-defined ticks; -1 means unlimited
## and 0 means expired.  A packet never accepts the same rule twice.

var quantity: BigValueType
var payload: Dictionary
var tags: Array[String]
var lineage: String
var visited_rules: Array[String]
var target_history: Array[String]
var remaining_lifetime: int


func _init(
	p_quantity: BigValueType = null,
	p_payload: Dictionary = {},
	p_tags: Array[String] = [],
	p_lineage: String = "",
	p_remaining_lifetime: int = -1
) -> void:
	quantity = p_quantity.duplicate_value() if p_quantity != null else BigValueType.from_float(0.0)
	payload = p_payload.duplicate(true)
	tags = _normalized_strings(p_tags)
	# Anonymous packets receive distinct roots, so they cannot accidentally be
	# merged as if they shared provenance.
	lineage = p_lineage if not p_lineage.is_empty() else "packet:%d" % get_instance_id()
	visited_rules = []
	target_history = []
	remaining_lifetime = maxi(-1, p_remaining_lifetime)


func is_expired() -> bool:
	return remaining_lifetime == 0


func consume_lifetime(ticks: int = 1) -> bool:
	if ticks < 0:
		return false
	if remaining_lifetime >= 0:
		remaining_lifetime = maxi(0, remaining_lifetime - ticks)
	return not is_expired()


func has_visited_rule(rule_id: String) -> bool:
	return visited_rules.has(rule_id)


func try_visit_rule(rule_id: String) -> bool:
	if rule_id.is_empty() or is_expired() or visited_rules.has(rule_id):
		return false
	visited_rules.append(rule_id)
	return true


func record_target(target_id: String) -> bool:
	if target_id.is_empty() or is_expired():
		return false
	target_history.append(target_id)
	return true


func duplicate_packet() -> EventPacket:
	var copy := EventPacket.new(quantity, payload, tags, lineage, remaining_lifetime)
	copy.visited_rules = visited_rules.duplicate()
	copy.target_history = target_history.duplicate()
	return copy


func can_merge_with(other: EventPacket) -> bool:
	if other == null or is_expired() or other.is_expired():
		return false
	# Equal proof state is the boundary for a linear merge.  In particular,
	# packets from different lineages or branches must remain separate.
	return (
		lineage == other.lineage
		and payload == other.payload
		and tags == other.tags
		and visited_rules == other.visited_rules
		and target_history == other.target_history
		and remaining_lifetime == other.remaining_lifetime
	)


func merge_with(other: EventPacket) -> EventPacket:
	if not can_merge_with(other):
		return null
	var merged := EventPacket.new(
		quantity.add(other.quantity), payload, tags, lineage,
		_merged_lifetime(remaining_lifetime, other.remaining_lifetime)
	)
	merged.visited_rules = visited_rules.duplicate()
	merged.target_history = target_history.duplicate()
	return merged


func merge_in_place(other: EventPacket) -> bool:
	if not can_merge_with(other):
		return false
	quantity = quantity.add(other.quantity)
	remaining_lifetime = _merged_lifetime(remaining_lifetime, other.remaining_lifetime)
	return true


func proof_chain_summary() -> String:
	var rule_part: String = _join_strings(visited_rules) if not visited_rules.is_empty() else "(none)"
	var target_part: String = _join_strings(target_history) if not target_history.is_empty() else "(none)"
	var life_part: String = "unlimited" if remaining_lifetime < 0 else str(remaining_lifetime)
	return "lineage=%s | rules=%s | targets=%s | ttl=%s | quantity=%s" % [
		lineage if not lineage.is_empty() else "(anonymous)",
		rule_part,
		target_part,
		life_part,
		quantity.to_short_string(),
	]


static func _merged_lifetime(left: int, right: int) -> int:
	if left < 0:
		return right
	if right < 0:
		return left
	return mini(left, right)


static func _normalized_strings(values: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		if not value.is_empty() and not result.has(value):
			result.append(value)
	result.sort()
	return result


static func _join_strings(values: Array[String]) -> String:
	var result := ""
	for index in values.size():
		if index > 0:
			result += " -> "
		result += values[index]
	return result
