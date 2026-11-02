class_name ClassProgression
extends RefCounted

## The progression half of a player class (docs/rebuild/ROOM_SESSION_DESIGN.md,
## "ClassKit"): how the class turns equipment, runes, laws and talents into a
## resolved build and a growth model, outside any combat room. The room half is
## ClassKit (src/game/classes/class_kit.gd).
##
## BuildResolver and TalentBuild stay generic and ask the class for every
## class-specific rule below. Implementations are pure and deterministic: they
## read only their arguments, so resolved-build fingerprints stay stable.
## A class owns its skill ids, its talent capability vocabulary and its growth
## model; a melee or summoner class does not have to speak the Ranger's arrow
## parameters.
##
## The save format is not per-class yet: the profile keeps one talents section
## and `initial_class`. Per-class save sections are a schema change decided when
## the second class is built.


## Stable class id ("ranger"), matching profile `initial_class` and the
## talent tree `class_id`.
func class_id() -> String:
	return ""


## Skill a build resolves against when the caller names none.
func default_skill_id() -> String:
	return ""


## Skills this class can resolve a build for. BuildResolver rejects others.
func supported_skill_ids() -> Array[String]:
	return []


## Numeric talent capabilities that stack by addition across nodes; every other
## capability takes the last allocated node's value.
func stacking_capability_ids() -> Array[String]:
	return []


## True when the allocated talents unlock the class's stance choice.
func stance_available(_allocated_talent_ids: Array) -> bool:
	return false


## Class rules applied after equipment and talent modifiers (for the Ranger:
## the p cap and its overflow damage). Every change must be recorded through
## `record_source(parameter, kind, source_id, operation, value, before, after)`.
func apply_parameter_rules(_parameters: Dictionary, _talent_capabilities: Dictionary, _record_source: Callable) -> void:
	pass


## Interface graph of a skill with its runes and laws: {"connected": Array[String],
## "missing": Array[String]}, both sorted and unique. `runes` and `laws` are the
## registry dictionaries keyed by id.
func resolve_interfaces(_skill_id: String, _rune_ids: Array[String], _law_ids: Array[String], _runes: Dictionary, _laws: Dictionary) -> Dictionary:
	return {"connected": [], "missing": []}


## Growth model of the final parameters and connected interfaces: at least
## R, g, generation_time, state (growth classification), total_events (BigValue)
## and total_events_float.
func growth_model(_parameters: Dictionary, _connected_interfaces: Array) -> Dictionary:
	return {}
