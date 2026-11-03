class_name ArenaRunNode
extends Node
## Contract shared by every node that runs an arena session: the contract run
## controller mounted as the arena screen, the combat room runtime it hosts per
## room, and the test doubles that stand in for either. Callers check
## `is ArenaRunNode` instead of probing method names.
##
## start_session() is required. The other methods are optional capabilities;
## their defaults are exactly what a caller does when an implementation does not
## offer the capability, so overriding only some of them is safe.

signal completed(result: Dictionary)
signal abandoned(result: Dictionary)


## Starts the session. Implementations must override this.
func start_session(_config: Dictionary) -> Dictionary:
	return {"ok": false, "error": "room_runtime_api_unavailable"}


func set_effects_volume(_value: float) -> void:
	pass


func release_manual_controls() -> void:
	pass


func request_abandon() -> void:
	pass


## true = nothing is holding the route for a defeat clip.
func defeat_presentation_ready() -> bool:
	return true


## Manual input carried into the next room; null when there is none.
func take_continuous_manual_input() -> RefCounted:
	return null


func resume_continuous_manual_input(_continued_input: RefCounted) -> void:
	pass
