extends SceneTree

const RouterScript := preload("res://src/systems/combat_command_router.gd")
const ProtocolScript := preload("res://src/systems/combat_command_protocol.gd")
const DispatchPortScript := preload("res://tests/helpers/callable_combat_command_dispatch_port.gd")
const Assert := preload("res://tests/helpers/assert.gd")

const TICK := 17
const ACTOR := "ranger"
const EQUIPPED: Array[String] = ["piercing_arrow", "hunter_mark", "dash"]

var failures: Array[String] = []
var rejected_commands: Array[Dictionary] = []
var receipts: Array[Dictionary] = []
var dodge_commands: Array[Dictionary] = []
var cast_commands: Array[Dictionary] = []


func _initialize() -> void:
	var router = RouterScript.new()
	var dispatch_port = DispatchPortScript.new()
	dispatch_port.rejected = Callable(self, "_on_rejected")
	dispatch_port.receipt = Callable(self, "_on_receipt")
	dispatch_port.dodge = Callable(self, "_on_dodge")
	dispatch_port.cast = Callable(self, "_on_cast")

	var move := ProtocolScript.move(TICK, ACTOR, 3, 1000, 0, 750)
	var move_result: Dictionary = router.dispatch([move], TICK, EQUIPPED, dispatch_port)
	_expect(move_result.movement == Vector2.RIGHT, "router: accepted move did not reach movement output")
	_expect(is_equal_approx(float(move_result.speed_scale), 0.75), "router: move speed scale changed")
	_expect(receipts.size() == 1 and receipts[0].status == "accepted", "router: accepted move receipt was not emitted")

	var original_dodge := ProtocolScript.dodge(TICK, ACTOR, 41, 0, -1000)
	var dodge_result: Dictionary = router.dispatch([original_dodge], TICK, EQUIPPED, dispatch_port)
	_expect(dodge_commands.size() == 1, "router: dodge callback was not called once")
	_expect(dodge_commands[0] == original_dodge, "router: dodge callback rebuilt the accepted command")
	_expect(dodge_result.receipts.size() == 1 and dodge_result.receipts[0].status == "accepted", "router: dodge protocol receipt changed")
	_expect(receipts[-1].status == "buffered" and receipts[-1].reason == "mobility_buffered", "router: dodge callback result was not projected as buffered")

	var cast := ProtocolScript.cast(TICK, ACTOR, 52, "hunter_mark", 8)
	router.dispatch([cast], TICK, EQUIPPED, dispatch_port)
	_expect(cast_commands.size() == 1 and cast_commands[0] == cast, "router: cast callback did not receive the accepted command")

	var rejected := ProtocolScript.cast(TICK, ACTOR, 63, "unknown", 8)
	router.dispatch([rejected], TICK, EQUIPPED, dispatch_port)
	_expect(rejected_commands.size() == 1 and rejected_commands[0] == rejected, "router: rejected command was not surfaced unchanged")

	if failures.is_empty():
		print("PASS test_combat_command_router.gd")
		quit(0)
		return
	for failure: String in failures:
		printerr("- %s" % failure)
	quit(1)


func _on_rejected(command: Dictionary, _reason: String) -> void:
	rejected_commands.append(command.duplicate(true))


func _on_receipt(command: Dictionary, status: String, reason: String) -> void:
	receipts.append({"command": command.duplicate(true), "status": status, "reason": reason})


func _on_dodge(command: Dictionary, _direction: Vector2) -> Dictionary:
	dodge_commands.append(command.duplicate(true))
	return {"accepted": false, "reason": "mobility_buffered"}


func _on_cast(command: Dictionary) -> void:
	cast_commands.append(command.duplicate(true))


func _expect(condition: bool, message: String) -> void: Assert.expect(condition, message, failures)
