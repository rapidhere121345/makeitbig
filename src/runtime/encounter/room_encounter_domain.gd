class_name RoomEncounterDomain
extends RefCounted

## Minimal contract a room encounter domain offers to RoomEncounterPort and
## SceneRuntime: a per-tick step and a death notification. RoomEncounter is
## the production domain; test doubles extend this base directly.


## Advances the domain for one committed tick. Returns an EncounterStepResult
## or null; the port rejects anything else.
func step(_tick: int) -> Variant:
	return null


## Receives one settled death. The port tolerates any return value.
func notify_death(_entity_key: String, _tick: int) -> Variant:
	return null
