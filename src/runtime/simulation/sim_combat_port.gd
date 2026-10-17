class_name SimCombatPort
extends RefCounted

## Narrow integration port for damage and status resolution.
##
## The kernel never knows damage formulas. This port consumes the tick's
## SimHit/SimStatusApplication buffers, applies effects to typed records, and
## may set records dead; the kernel owns what death means structurally.


## DAMAGE_STATUS phase: resolve hits and status applications onto records.
func resolve(_ctx: SimTickContext) -> void:
	pass


## Optional death-domain hook. A typed notification tells the kernel that
## DeathSettlement already produced the encounter fact; the kernel still owns
## tombstoning and structural reclamation.
func on_death(_entity_view: SimEntityView, _ctx: SimTickContext) -> Variant:
	return null
