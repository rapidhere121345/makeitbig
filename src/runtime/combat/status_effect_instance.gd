class_name StatusEffectInstance
extends RefCounted

var instance_id := ""
var target_key := ""
var source_key := ""
var effect_id := ""
var started_tick := -1
var expires_tick := -1
var next_tick := -1
var period_ticks := 0
var magnitude := 0.0
var damage_type := "physical"
var sequence := 0


func active_at(tick: int) -> bool:
	return tick >= started_tick and tick < expires_tick


func snapshot() -> Dictionary:
	return {
		"instance_id": instance_id,
		"target_key": target_key,
		"source_key": source_key,
		"effect_id": effect_id,
		"started_tick": started_tick,
		"expires_tick": expires_tick,
		"next_tick": next_tick,
		"period_ticks": period_ticks,
		"magnitude": magnitude,
		"damage_type": damage_type,
		"sequence": sequence,
	}
