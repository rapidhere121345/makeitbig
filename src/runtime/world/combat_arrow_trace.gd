class_name CombatArrowTrace
extends RefCounted

## Presentation trace emitted by an authoritative projectile impact.
## It carries no gameplay authority and expires independently of the arrow.

var from: Vector2
var to: Vector2
var remaining: float = 0.18


func _init(start: Vector2, finish: Vector2) -> void:
	from = start
	to = finish
