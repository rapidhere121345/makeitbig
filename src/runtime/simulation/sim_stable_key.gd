class_name SimStableKey
extends RefCounted

## Never-reused entity identity.
##
## The kernel assigns stable keys from a monotonically increasing counter that
## starts at 1 and never resets for the lifetime of a configured room. Keys are
## the one and only gameplay ordering source: snapshots, death settlement, and
## deterministic iteration all sort by key value.

const FIRST_VALID_KEY: int = 1

var value: int = 0


static func make(assigned_value: int) -> SimStableKey:
	var key := SimStableKey.new()
	key.value = assigned_value
	return key


func is_valid() -> bool:
	return value >= FIRST_VALID_KEY


func equals_key(other: Variant) -> bool:
	if other is SimStableKey:
		return value == other.value
	return false


func encode() -> String:
	return str(value)
