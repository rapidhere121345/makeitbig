class_name SimOutcome
extends RefCounted

## Typed result envelope for kernel API boundaries.
##
## Gameplay data never lives in this object; it only carries success state, a
## fail-closed error code, and at most one typed payload slot. Callers must
## check "ok" before reading any payload field.

var ok: bool = false
var error: StringName = &""
var handle: SimEntityHandle = null
var stable_key: int = 0
var value: Variant = null


static func success() -> SimOutcome:
	var outcome := SimOutcome.new()
	outcome.ok = true
	return outcome


static func failure(error_code: StringName) -> SimOutcome:
	var outcome := SimOutcome.new()
	outcome.ok = false
	outcome.error = error_code
	return outcome


func with_handle(assigned_handle: SimEntityHandle) -> SimOutcome:
	handle = assigned_handle
	return self


func with_key(assigned_key: int) -> SimOutcome:
	stable_key = assigned_key
	return self


func with_value(assigned_value: Variant) -> SimOutcome:
	value = assigned_value
	return self
