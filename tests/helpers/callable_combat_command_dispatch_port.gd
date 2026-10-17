class_name CallableCombatCommandDispatchPort
extends "res://src/systems/combat_command_dispatch_port.gd"

## Tests-only adapter. Production router users implement the typed methods
## directly; this helper keeps callback assertions out of src/.

var rejected: Callable
var receipt: Callable
var dodge: Callable
var cast: Callable


func on_rejected(command: Dictionary, reason: String) -> void:
	if rejected.is_valid():
		rejected.call(command, reason)


func on_receipt(command: Dictionary, status: String, reason: String) -> void:
	if receipt.is_valid():
		receipt.call(command, status, reason)


func on_dodge(command: Dictionary, direction: Vector2) -> Dictionary:
	if dodge.is_valid():
		var result: Variant = dodge.call(command, direction)
		return result if result is Dictionary else {"accepted": false, "reason": "invalid_dodge_result"}
	return {"accepted": false, "reason": "dispatch_port_unimplemented"}


func on_cast(command: Dictionary) -> void:
	if cast.is_valid():
		cast.call(command)
