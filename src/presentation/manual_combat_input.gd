class_name ManualCombatInput
extends RefCounted

## Translates device events into the Manual combat intent that may be sampled by
## the fixed-tick authority. The emitted combat command remains the replayable
## boundary; this object only remembers which physical sources are still held.
##
## Pointer presses are captured at their origin. A press that starts over the HUD
## can never turn into world fire by being dragged away, while a world press pauses
## when the pointer crosses the HUD and resumes after it leaves.

const ATTACK_ACTION: StringName = &"attack"

var _held_non_pointer_sources: Dictionary = {}
var _held_pointer_sources: Dictionary = {}


func reset() -> void:
	_held_non_pointer_sources.clear()
	_held_pointer_sources.clear()


## Only an uninterrupted room transition may retain already-observed assisted
## sources. Input remains the device authority; reset sources are never reseeded.
func retain_pressed_assisted_sources() -> void:
	_held_pointer_sources.clear()
	for source: String in _held_non_pointer_sources.keys():
		var parts := source.split(":")
		var pressed := false
		if parts.size() == 3:
			var device := int(parts[1])
			var code := int(parts[2])
			match parts[0]:
				"key":
					pressed = Input.is_physical_key_pressed(code) or Input.is_key_pressed(code)
				"joy_button":
					pressed = Input.is_joy_button_pressed(device, code)
				"joy_axis":
					var event := InputEventJoypadMotion.new()
					event.device = device
					event.axis = code
					event.axis_value = Input.get_joy_axis(device, code)
					pressed = event.is_action_pressed(ATTACK_ACTION)
		if not pressed:
			_held_non_pointer_sources.erase(source)


## Returns true exactly once for a newly pressed source that is allowed to fire.
## Key/controller sources are independent of pointer location. Pointer presses that
## originate over the interface remain interface-owned until their release.
func observe_attack_event(event: InputEvent, pointer_over_interface: bool) -> bool:
	if event == null:
		return false
	var pressed := event.is_action_pressed(ATTACK_ACTION)
	var released := event.is_action_released(ATTACK_ACTION)
	if not pressed and not released:
		return false
	var source := _source_key(event)
	if source.is_empty():
		return false
	var pointer_event := event is InputEventMouseButton
	var sources := _held_pointer_sources if pointer_event else _held_non_pointer_sources
	if released:
		sources.erase(source)
		return false
	if sources.has(source):
		return false
	var world_owned := not pointer_event or not pointer_over_interface
	sources[source] = world_owned
	return world_owned


func attack_held(pointer_over_interface: bool) -> bool:
	return not attack_source(pointer_over_interface).is_empty()


## Returns the currently effective Manual attack source without mutating input
## state. Explicit world pointing wins over assisted targeting when both are held.
func attack_source(pointer_over_interface: bool) -> String:
	if not pointer_over_interface and _has_world_pointer_source():
		return "pointer"
	if not _held_non_pointer_sources.is_empty():
		return "assisted"
	return ""


func snapshot() -> Dictionary:
	return {
		"assisted_held": not _held_non_pointer_sources.is_empty(),
		"pointer_world_held": _has_world_pointer_source(),
		"pointer_hud_owned_held": _has_hud_owned_pointer_source(),
		"non_pointer_sources": _held_non_pointer_sources.duplicate(true),
		"pointer_sources": _held_pointer_sources.duplicate(true),
	}.duplicate(true)


func _has_world_pointer_source() -> bool:
	for world_owned: Variant in _held_pointer_sources.values():
		if bool(world_owned):
			return true
	return false


func _has_hud_owned_pointer_source() -> bool:
	for world_owned: Variant in _held_pointer_sources.values():
		if not bool(world_owned):
			return true
	return false


func _source_key(event: InputEvent) -> String:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		return "mouse:%d:%d" % [mouse_event.device, mouse_event.button_index]
	if event is InputEventKey:
		var key_event := event as InputEventKey
		var code: int = int(key_event.physical_keycode if key_event.physical_keycode != 0 else key_event.keycode)
		return "key:%d:%d" % [key_event.device, code]
	if event is InputEventJoypadButton:
		var button_event := event as InputEventJoypadButton
		return "joy_button:%d:%d" % [button_event.device, button_event.button_index]
	if event is InputEventJoypadMotion:
		var motion_event := event as InputEventJoypadMotion
		return "joy_axis:%d:%d" % [motion_event.device, motion_event.axis]
	return "%s:%d" % [event.get_class(), event.device]
