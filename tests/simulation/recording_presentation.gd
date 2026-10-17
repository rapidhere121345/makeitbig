extends "res://src/runtime/simulation/sim_presentation_port.gd"

## Presentation double: records every authoritative snapshot in arrival order.

var snapshots: Array[SimSnapshot] = []


func on_snapshot(snapshot: SimSnapshot) -> void:
	snapshots.append(snapshot)
