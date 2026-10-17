extends "res://src/runtime/simulation/sim_spatial_port.gd"

## Fake spatial integration: direct movement commits plus overlap contact hits.
## Proves the kernel can drive a full tick with no geometry and no Main.

var registry: ActorRegistry = null
var movement_speed: float = 1.0
var contact_damage: int = 1

var movement_log: Array = []  # [tick, stable_key] per applied movement, in order
var tombstoned_seen_during_movement: Array[int] = []
var refreshed_ticks: Array[int] = []
var contact_hits_produced: int = 0
var view_count_at_movement: Array[int] = []


func apply_movement(ctx: SimTickContext) -> void:
	view_count_at_movement.append(ctx.view.entity_count())
	for intent in ctx.intents.intents():
		var resolved: SimOutcome = registry.resolve(intent.entity)
		if not resolved.ok:
			continue
		var record: ActorState = resolved.value
		if not record.alive:
			tombstoned_seen_during_movement.append(record.stable_key)
			continue
		var target := record.feet_position + intent.move_direction * movement_speed
		var committed: SimOutcome = registry.commit_movement(intent.entity, target, ctx.tick)
		if committed.ok:
			movement_log.append([ctx.tick, record.stable_key])


func refresh_dynamic_index(ctx: SimTickContext) -> void:
	refreshed_ticks.append(ctx.tick)


func run_continuous_queries(ctx: SimTickContext) -> void:
	var entities := ctx.view.entities
	for i in entities.size():
		for j in range(i + 1, entities.size()):
			var left: SimEntityView = entities[i]
			var right: SimEntityView = entities[j]
			var left_pos: Vector2 = left.get("feet_position")
			var right_pos: Vector2 = right.get("feet_position")
			var left_radius: float = left.get("footprint_radius")
			var right_radius: float = right.get("footprint_radius")
			if left_pos.distance_to(right_pos) < left_radius + right_radius:
				ctx.hits.append(SimHit.make(left.handle, right.handle, contact_damage, &"contact"))
				contact_hits_produced += 1
