class_name CombatCommandRouter
extends RefCounted

## Routes one fixed-tick command batch after CombatCommandProtocol arbitration.
##
## The protocol decides validity, ordering and conflicts. This object decides
## how the accepted command kinds reach the room's gameplay callbacks. It owns
## no player state and never calls Input; the room supplies callbacks for the
## actual movement and ability rules.

const CombatCommandProtocolScript := preload("res://src/systems/combat_command_protocol.gd")


func dispatch(commands: Array[Dictionary], current_tick: int, equipped_abilities: Array[String], callbacks: Dictionary, allow_dodge: bool = true) -> Dictionary:
	var arbitration: Dictionary = CombatCommandProtocolScript.arbitrate(commands, current_tick, equipped_abilities, allow_dodge)
	var receipts: Array = arbitration.get("receipts", [])
	for receipt: Dictionary in receipts:
		if String(receipt.get("status", "")) != CombatCommandProtocolScript.STATUS_REJECTED:
			continue
		var rejected_command: Dictionary = receipt.get("command", {})
		_invoke(callbacks, "rejected", [rejected_command, String(receipt.get("reason", "invalid_command"))])

	var movement := Vector2.ZERO
	var speed_scale := 1.0
	for command: Dictionary in arbitration.get("commands", []):
		match String(command.get("kind", "")):
			CombatCommandProtocolScript.KIND_MOVE:
				movement = direction_from_command(command)
				speed_scale = float(command.get("speed_milli", 1000)) / 1000.0
				_invoke(callbacks, "receipt", [command, "accepted", "ok"])
			CombatCommandProtocolScript.KIND_STOP_MOVE:
				movement = Vector2.ZERO
				speed_scale = 0.0
				_invoke(callbacks, "receipt", [command, "accepted", "ok"])
			CombatCommandProtocolScript.KIND_DODGE:
				# Pass the accepted command through unchanged. The room may buffer a
				# mobility request when the current dodge/dash is ending; rebuilding it
				# there would allocate a new sequence and silently change replay input.
				var dodge_result: Variant = _invoke(callbacks, "dodge", [command, direction_from_command(command)])
				var dodge_ok := false
				var dodge_reason := "invalid_dodge"
				if dodge_result is Dictionary:
					dodge_ok = bool((dodge_result as Dictionary).get("accepted", false))
					dodge_reason = String((dodge_result as Dictionary).get("reason", dodge_reason))
				_invoke(callbacks, "receipt", [command, "accepted" if dodge_ok else ("buffered" if dodge_reason == "mobility_buffered" else "rejected"), dodge_reason])
			CombatCommandProtocolScript.KIND_CAST:
				_invoke(callbacks, "cast", [command])
	return {
		"commands": arbitration.get("commands", []).duplicate(true),
		"receipts": receipts.duplicate(true),
		"movement": movement,
		"speed_scale": speed_scale,
	}


static func direction_from_command(command: Dictionary) -> Vector2:
	var direction := Vector2(float(command.get("direction_x_milli", 0)), float(command.get("direction_y_milli", 0))) / 1000.0
	return direction.normalized() if direction != Vector2.ZERO else Vector2.ZERO


func _invoke(callbacks: Dictionary, name: String, arguments: Array) -> Variant:
	var callback_value: Variant = callbacks.get(name, Callable())
	if callback_value is Callable and (callback_value as Callable).is_valid():
		return (callback_value as Callable).callv(arguments)
	return null
