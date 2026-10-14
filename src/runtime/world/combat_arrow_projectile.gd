class_name CombatArrowProjectile
extends RefCounted

## Authoritative piercing arrow entity. Every field that can affect travel or
## damage is frozen on release; presentation reads positions directly and
## never owns a second flight clock.

var action_instance_id: int
var target_entity_id: int
var spawned_tick: int
var origin: Vector2
var direction: Vector2
var position: Vector2
var previous_position: Vector2
var maximum_range: float
var speed: float
var distance_travelled: float = 0.0
var aggregate_damage: BigValue
var ordinary_damage: float
var event_count: BigValue
var payload: float


func _init(
	action_id: int,
	target_id: int,
	release_tick: int,
	start: Vector2,
	aim: Vector2,
	range_limit: float,
	flight_speed: float,
	damage: BigValue,
	frozen_ordinary_damage: float,
	events: BigValue,
	frozen_payload: float
) -> void:
	action_instance_id = action_id
	target_entity_id = target_id
	spawned_tick = release_tick
	origin = start
	direction = aim
	position = start
	previous_position = start
	maximum_range = range_limit
	speed = flight_speed
	aggregate_damage = damage
	ordinary_damage = frozen_ordinary_damage
	event_count = events
	payload = frozen_payload
