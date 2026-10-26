extends SceneTree

const ManualInput := preload("res://src/systems/manual_combat_input.gd")
const MainScript := preload("res://src/game/main.gd")
const Assert := preload("res://tests/helpers/assert.gd")


class FakeHud extends Control:
	var pointer_over_interface := false


	func is_pointer_over_interface() -> bool:
		return pointer_over_interface


func _initialize() -> void:
	var failures: Array[String] = []
	_test_keyboard_is_independent_of_pointer(failures)
	_test_pointer_capture_stays_with_its_origin(failures)
	_test_sources_do_not_duplicate_press_edges(failures)
	_test_attack_source_pointer(failures)
	_test_attack_source_assisted(failures)
	_test_attack_source_priority_and_release_downgrade(failures)
	_test_attack_source_hud_pause_and_resume(failures)
	_test_attack_source_reset_and_snapshot(failures)
	_test_dodge_routes_by_press_origin(failures)
	_test_advertised_keyboard_bindings(failures)
	_test_continuation_uses_real_input(failures)
	if failures.is_empty():
		print("PASS  test_manual_combat_input.gd")
		quit(0)
		return
	for failure: String in failures:
		printerr("- %s" % failure)
	quit(1)


func _test_continuation_uses_real_input(failures: Array[String]) -> void:
	var state := ManualInput.new()
	var press := _key_event(true)
	Input.parse_input_event(press.duplicate())
	Input.flush_buffered_events()
	state.observe_attack_event(press, false)
	state.observe_attack_event(_mouse_event(true), false)
	state.retain_pressed_assisted_sources()
	_expect(state.attack_source(false) == "assisted" and not state.snapshot().pointer_world_held,
		"continuation: did not retain real Space or retained mouse capture", failures)
	# The old room may ignore a key-up after victory; global Input remains truthful.
	Input.parse_input_event(_key_event(false))
	Input.flush_buffered_events()
	state.retain_pressed_assisted_sources()
	_expect(not state.attack_held(false), "continuation: stale observed source survived a real release", failures)
	Input.parse_input_event(press.duplicate())
	Input.flush_buffered_events()
	state.observe_attack_event(press, false)
	var auto_arena = MainScript.new()
	auto_arena.selected_mode = "Auto"
	auto_arena.input_adapter.manual_combat_input = state
	var before := state.snapshot()
	_expect(auto_arena.take_continuous_manual_input() == null and state.snapshot() == before,
		"continuation: Auto read or transferred manual sources", failures)
	auto_arena.free()
	state.reset()
	state.retain_pressed_assisted_sources()
	_expect(not state.attack_held(false), "continuation: reseeded a paused/reset source from global Input", failures)
	Input.parse_input_event(_key_event(false))
	Input.flush_buffered_events()


func _test_advertised_keyboard_bindings(failures: Array[String]) -> void:
	for binding in [[KEY_LEFT, "move_left"], [KEY_RIGHT, "move_right"], [KEY_UP, "move_up"], [KEY_DOWN, "move_down"], [KEY_SHIFT, "dodge"], [KEY_CTRL, "dodge"]]:
		var event := InputEventKey.new()
		event.physical_keycode = binding[0]
		event.pressed = true
		_expect(event.is_action_pressed(binding[1]), "advertised key %s does not trigger %s" % [OS.get_keycode_string(binding[0]), binding[1]], failures)
		if binding[1] != "dodge":
			_expect(not event.is_action_pressed("dodge"), "movement arrow also triggers dodge", failures)


func _test_keyboard_is_independent_of_pointer(failures: Array[String]) -> void:
	var state := ManualInput.new()
	var press := _key_event(true)
	_expect(press.is_action_pressed("attack"), "fixture: Space press is not mapped to attack", failures)
	_expect(state.observe_attack_event(press, true), "keyboard: pointer hover swallowed the press edge", failures)
	_expect(state.attack_held(true), "keyboard: pointer hover stopped the held source", failures)
	_expect(not state.observe_attack_event(_key_event(true, true), true), "keyboard: key echo emitted another press edge", failures)
	state.observe_attack_event(_key_event(false), true)
	_expect(not state.attack_held(true), "keyboard: release did not clear the held source", failures)


func _test_pointer_capture_stays_with_its_origin(failures: Array[String]) -> void:
	var state := ManualInput.new()
	_expect(not state.observe_attack_event(_mouse_event(true), true), "pointer: a HUD-origin press entered world combat", failures)
	_expect(not state.attack_held(false), "pointer: dragging a HUD-origin press into the world began firing", failures)
	state.observe_attack_event(_mouse_event(false), false)

	_expect(state.observe_attack_event(_mouse_event(true), false), "pointer: a world-origin press did not emit its edge", failures)
	_expect(state.attack_held(false), "pointer: a world-origin press was not held", failures)
	_expect(not state.attack_held(true), "pointer: held world fire continued over the HUD", failures)
	_expect(state.attack_held(false), "pointer: world fire did not resume after leaving the HUD", failures)
	state.observe_attack_event(_mouse_event(false), true)
	_expect(not state.attack_held(false), "pointer: release over the HUD left world fire stuck", failures)


func _test_sources_do_not_duplicate_press_edges(failures: Array[String]) -> void:
	var state := ManualInput.new()
	_expect(state.observe_attack_event(_key_event(true), false), "sources: first key press was lost", failures)
	_expect(not state.observe_attack_event(_key_event(true), false), "sources: repeated down state emitted another edge", failures)
	_expect(state.observe_attack_event(_mouse_event(true), false), "sources: independent pointer press was lost", failures)
	state.observe_attack_event(_key_event(false), false)
	_expect(state.attack_held(false), "sources: releasing one source cleared another", failures)
	state.reset()
	_expect(not state.attack_held(false) and (state.snapshot().non_pointer_sources as Dictionary).is_empty(), "sources: reset retained held input", failures)


func _test_attack_source_pointer(failures: Array[String]) -> void:
	var state := ManualInput.new()
	state.observe_attack_event(_mouse_event(true), false)
	_expect(state.attack_source(false) == "pointer", "source: world pointer hold was not reported as pointer", failures)
	state.observe_attack_event(_mouse_event(false), false)
	_expect(state.attack_source(false).is_empty(), "source: pointer release did not clear the source", failures)


func _test_attack_source_assisted(failures: Array[String]) -> void:
	var state := ManualInput.new()
	state.observe_attack_event(_key_event(true), true)
	_expect(state.attack_source(true) == "assisted", "source: keyboard hold over HUD was not reported as assisted", failures)
	_expect(state.attack_source(false) == "assisted", "source: assisted hold changed with pointer hover", failures)
	state.observe_attack_event(_key_event(false), false)
	_expect(state.attack_source(false).is_empty(), "source: assisted release did not clear the source", failures)


func _test_attack_source_priority_and_release_downgrade(failures: Array[String]) -> void:
	var state := ManualInput.new()
	state.observe_attack_event(_key_event(true), false)
	state.observe_attack_event(_mouse_event(true), false)
	_expect(state.attack_source(false) == "pointer", "source: assisted hold took priority over explicit pointer targeting", failures)
	state.observe_attack_event(_mouse_event(false), false)
	_expect(state.attack_source(false) == "assisted", "source: pointer release did not downgrade to the held assisted source", failures)
	state.observe_attack_event(_key_event(false), false)


func _test_attack_source_hud_pause_and_resume(failures: Array[String]) -> void:
	var state := ManualInput.new()
	state.observe_attack_event(_mouse_event(true), true)
	_expect(state.attack_source(false).is_empty(), "source: HUD-origin pointer became active after leaving HUD", failures)
	state.observe_attack_event(_mouse_event(false), false)

	state.observe_attack_event(_mouse_event(true), false)
	_expect(state.attack_source(false) == "pointer", "source: world-origin pointer did not activate", failures)
	_expect(state.attack_source(true).is_empty(), "source: world-origin pointer did not pause over HUD", failures)
	_expect(state.attack_source(false) == "pointer", "source: world-origin pointer did not resume after leaving HUD", failures)
	state.observe_attack_event(_mouse_event(false), true)
	_expect(state.attack_source(false).is_empty(), "source: pointer release over HUD did not clear the source", failures)


func _test_attack_source_reset_and_snapshot(failures: Array[String]) -> void:
	var state := ManualInput.new()
	state.observe_attack_event(_key_event(true), false)
	state.observe_attack_event(_mouse_event(true), false)
	var held_snapshot := state.snapshot()
	_expect(held_snapshot.assisted_held == true, "snapshot: assisted semantic state was missing", failures)
	_expect(held_snapshot.pointer_world_held == true, "snapshot: world pointer semantic state was missing", failures)
	_expect(held_snapshot.pointer_hud_owned_held == false, "snapshot: HUD-owned pointer semantic state was incorrect", failures)
	state.reset()
	var reset_snapshot := state.snapshot()
	_expect(state.attack_source(false).is_empty(), "source: reset retained an active attack source", failures)
	_expect(reset_snapshot.assisted_held == false and reset_snapshot.pointer_world_held == false, "snapshot: reset retained semantic held state", failures)


## Route through Main's real _unhandled_input boundary with concrete events from
## the project InputMap. This guards against cursor hover filtering an independent
## keyboard action, while retaining the HUD-origin block for the RMB binding.
func _test_dodge_routes_by_press_origin(failures: Array[String]) -> void:
	var arena = MainScript.new()
	arena.in_arena = true
	arena.selected_mode = "Manual"
	var hud := FakeHud.new()
	hud.pointer_over_interface = true
	arena.presentation.hud = hud

	var keyboard_press := _dodge_key_event(true)
	_expect(keyboard_press != null and keyboard_press.is_action_pressed("dodge"), "dodge route fixture: keyboard binding is missing", failures)
	arena._unhandled_input(keyboard_press)
	_expect(_dodge_command_count(arena.input_adapter.collect_commands(arena.gameplay_snapshot())) == 1, "dodge route: HUD hover swallowed a keyboard dodge", failures)

	var hud_mouse_press := _dodge_mouse_event(true)
	_expect(hud_mouse_press != null and hud_mouse_press.is_action_pressed("dodge"), "dodge route fixture: mouse binding is missing", failures)
	arena._unhandled_input(hud_mouse_press)
	_expect(_dodge_command_count(arena.input_adapter.collect_commands(arena.gameplay_snapshot())) == 0, "dodge route: HUD-origin RMB queued a dodge", failures)

	hud.pointer_over_interface = false
	var world_mouse_press := _dodge_mouse_event(true)
	arena._unhandled_input(world_mouse_press)
	arena._unhandled_input(world_mouse_press)
	_expect(_dodge_command_count(arena.input_adapter.collect_commands(arena.gameplay_snapshot())) == 1, "dodge route: one RMB down queued more than one dodge command", failures)
	arena.presentation.hud = null
	hud.free()
	arena.free()


func _dodge_key_event(pressed: bool) -> InputEventKey:
	for candidate: InputEvent in InputMap.action_get_events(&"dodge"):
		if candidate is InputEventKey:
			var event := candidate.duplicate() as InputEventKey
			event.pressed = pressed
			event.echo = false
			return event
	return null


func _dodge_mouse_event(pressed: bool) -> InputEventMouseButton:
	for candidate: InputEvent in InputMap.action_get_events(&"dodge"):
		if candidate is InputEventMouseButton:
			var event := candidate.duplicate() as InputEventMouseButton
			event.pressed = pressed
			return event
	return null


func _dodge_command_count(commands: Array[Dictionary]) -> int:
	var count := 0
	for command: Dictionary in commands:
		if String(command.get("kind", "")) == "dodge":
			count += 1
	return count


func _key_event(pressed: bool, echo: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_SPACE
	event.pressed = pressed
	event.echo = echo
	return event


func _mouse_event(pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	return event


func _expect(condition: bool, message: String, failures: Array[String]) -> void: Assert.expect(condition, message, failures)
