class_name CombatCommandDispatchPort
extends RefCounted

## Typed sink for commands accepted by CombatCommandRouter.
##
## The router owns arbitration only.  The room supplies one typed sink for
## receipts and gameplay effects; production code never passes a callback bag.

func on_rejected(_command: Dictionary, _reason: String) -> void:
	pass


func on_receipt(_command: Dictionary, _status: String, _reason: String) -> void:
	pass


func on_dodge(_command: Dictionary, _direction: Vector2) -> Dictionary:
	return {"accepted": false, "reason": "dispatch_port_unimplemented"}


func on_cast(_command: Dictionary) -> void:
	pass
