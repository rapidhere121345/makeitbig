extends "res://src/runtime/simulation/sim_combat_port.gd"

## Fake combat integration: applies hit amounts and scheduled damage to actor
## records. No formulas live in the kernel; this file is test-only behavior.

var registry: ActorRegistry = null
var scheduled_damage: Dictionary = {}  # stable_key -> amount (lookup only)

var damage_applied_total: int = 0
var hits_resolved: int = 0
var status_log: Array = []  # [target stable_key, status_id] in resolution order


func resolve(ctx: SimTickContext) -> void:
	for hit in ctx.hits.hits():
		var resolved: SimOutcome = registry.resolve(hit.target)
		if not resolved.ok:
			continue
		var record: ActorState = resolved.value
		record.apply_damage(hit.amount)
		damage_applied_total += hit.amount
		hits_resolved += 1
	for application in ctx.statuses.applications():
		var resolved: SimOutcome = registry.resolve(application.target)
		if not resolved.ok:
			continue
		status_log.append([resolved.stable_key, String(application.status_id)])
	for target_key in scheduled_damage:
		var entity := registry.actors_sorted_by_key()
		for record in entity:
			if record.stable_key == target_key:
				record.apply_damage(int(scheduled_damage[target_key]))
				damage_applied_total += int(scheduled_damage[target_key])
