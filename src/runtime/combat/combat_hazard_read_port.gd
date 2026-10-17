class_name CombatHazardReadPort
extends RefCounted

## Read-only hazard geometry exposed to enemy planning.
##
## The producer owns lifecycle and contact staging; AI receives only detached
## warning/active geometry and cannot mutate hazard state through this port.

func active_geometry() -> Array[Dictionary]:
	return []
