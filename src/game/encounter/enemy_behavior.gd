class_name EnemyBehavior
extends RefCounted

## Execution half of one enemy archetype (docs/rebuild/ROOM_SESSION_DESIGN.md,
## migration item 9). EncounterDirector keeps the encounter lifecycle, the tick
## order (entity-id order, recovery sweep, one batch plan, then one update per
## enemy) and the shared action helpers; a behavior only decides what its own
## kind does with the planner's intent on its tick. Planning stays in
## EnemyTactics, behind its snapshot contract.
##
## Behaviors are stateless and shared by every enemy of their kind: all state
## lives on CombatEnemyState, so the state hash sees it. They receive the
## director and call only its public helpers. Hash-visible strings (tactic
## reasons and states, action ids) belong to the behavior that writes them and
## must not be renamed.


## Content kind id this behavior drives ("melee_pursuer", "charging_raider",
## "fan_ranged", "threshold_colossus").
func kind_id() -> String:
	return ""


## Planner `request_action` ids this behavior starts (for example
## "melee_attack"). EncounterDirector routes a requested action to the behavior
## that declares it.
func action_ids() -> Array[String]:
	return []


## Advances one living enemy of this kind by one fixed tick, given the batch
## plan's intent for it (empty when the planner produced none).
func update_tick(_director: EncounterDirector, _enemy: CombatEnemyState, _intent: Dictionary) -> void:
	pass


## Starts the requested `action` (one of action_ids()) from a normal intent.
## Owns the action's own validation and the tactic reason it writes when the
## request is unusable.
func start_requested_action(_director: EncounterDirector, _enemy: CombatEnemyState, _action: String, _intent: Dictionary) -> void:
	pass
