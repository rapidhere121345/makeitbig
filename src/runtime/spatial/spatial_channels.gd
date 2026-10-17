class_name SpatialChannels
extends RefCounted

## Explicit, independent spatial query channels.
##
## There is no generic is_blocked answer anywhere in the spatial runtime.
## Every surface and dynamic body declares the channels it contributes to, and
## every query names exactly one channel.  Contributing to one channel never
## implies contributing to another.

const MOVEMENT := &"movement"
const NAVIGATION := &"navigation"
const VISION := &"vision"
const PROJECTILE := &"projectile"
const ATTACK := &"attack"
const HURTBOX := &"hurtbox"
const OCCLUSION := &"occlusion"

const ALL: Array[StringName] = [
	MOVEMENT,
	NAVIGATION,
	VISION,
	PROJECTILE,
	ATTACK,
	HURTBOX,
	OCCLUSION,
]


static func is_valid(channel: Variant) -> bool:
	return channel is StringName and ALL.has(channel as StringName)


## Validates a channel list.  The list must be a non-empty Array of known,
## unique channel names.  Errors are stable strings for load-time reporting.
static func validate_list(value: Variant, field_prefix: String = "channels") -> Array[String]:
	var errors: Array[String] = []
	if not value is Array:
		errors.append("%s:invalid_type" % field_prefix)
		return errors
	var list: Array = value
	if list.is_empty():
		errors.append("%s:empty" % field_prefix)
		return errors
	var seen: Dictionary = {}
	for entry: Variant in list:
		var channel := StringName(str(entry)) if entry is String or entry is StringName else &""
		if not is_valid(channel):
			errors.append("%s:unknown_channel:%s" % [field_prefix, str(entry)])
			continue
		if seen.has(channel):
			errors.append("%s:duplicate_channel:%s" % [field_prefix, String(channel)])
			continue
		seen[channel] = true
	return errors


## Canonical sorted copy used by every snapshot so ordering never depends on
## authored or registration order.
static func sorted_copy(value: Variant) -> Array[StringName]:
	var result: Array[StringName] = []
	if not value is Array:
		return result
	for entry: Variant in value:
		var channel := StringName(str(entry))
		if is_valid(channel) and not result.has(channel):
			result.append(channel)
	result.sort()
	return result
