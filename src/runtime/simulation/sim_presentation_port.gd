class_name SimPresentationPort
extends RefCounted

## Narrow integration port for presentation consumption.


## AUTHORITATIVE_SNAPSHOT phase: receives the immutable per-tick snapshot after
## all structural changes settled. The snapshot is detached; presentation can
## never mutate simulation state through it.
func on_snapshot(_snapshot: SimSnapshot) -> void:
	pass
