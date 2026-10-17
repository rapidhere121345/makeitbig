class_name BossPathResult
extends RefCounted

const ContactScript := preload("res://src/runtime/combat/boss_hit_contact.gd")

var tick := -1
var attack_instance_id := ""
var ok := false
var errors: Array[String] = []
var clipped := false
var blocked_by_static := false
var blocker_id := ""
var stop_toi := 1.0
var end_point := Vector2.ZERO
var hit_contacts: Array[BossHitContact] = []


func snapshot() -> Dictionary:
	var contacts: Array[Dictionary] = []
	for contact: BossHitContact in hit_contacts:
		contacts.append(contact.snapshot())
	return {
		"tick": tick,
		"attack_instance_id": attack_instance_id,
		"ok": ok,
		"errors": errors.duplicate(),
		"clipped": clipped,
		"blocked_by_static": blocked_by_static,
		"blocker_id": blocker_id,
		"stop_toi": stop_toi,
		"end_point": end_point,
		"hit_contacts": contacts,
	}


static func failure(at_tick: int, attack_id: String, error: String) -> BossPathResult:
	var result := BossPathResult.new()
	result.tick = at_tick
	result.attack_instance_id = attack_id
	result.errors.append(error)
	return result
