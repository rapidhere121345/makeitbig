class_name SimHit
extends RefCounted

## Typed damage contact record.
##
## Producers (combat resolution, continuous spatial queries) describe contact
## facts only: who hit whom, how much, and a contact kind. The kernel never
## interprets amounts; the damage/status phase forwards them to the combat port.

var source: SimEntityHandle = null
## Detached source identity for domain-owned contacts without an actor handle.
var source_key: String = ""
var target: SimEntityHandle = null
var amount: int = 0
var contact_kind: StringName = &""

## Optional combat facts carried by a spatial contact.  The spatial resolver
## writes facts; RoomCombatPort translates them into CombatHitRecord.  Keeping
## these fields on the typed contact avoids a dictionary event bus while still
## allowing the simple contact fixtures to use only amount/contact_kind.
var attack_instance_id: String = ""
var part_id: String = "body"
var damage_group_id: String = "body"
var damage_type: String = "physical"
var toi: float = 0.0
var priority: int = 0
var penetration_index: int = 0
var allow_repeat_target: bool = false
var contact_point := Vector2.ZERO


static func make(from_entity: SimEntityHandle, to_entity: SimEntityHandle, hit_amount: int, kind: StringName) -> SimHit:
	var hit := SimHit.new()
	hit.source = from_entity
	hit.target = to_entity
	hit.amount = hit_amount
	hit.contact_kind = kind
	return hit


func snapshot() -> Dictionary:
	return {
		"source": source,
		"source_key": source_key,
		"target": target,
		"amount": amount,
		"contact_kind": contact_kind,
		"attack_instance_id": attack_instance_id,
		"part_id": part_id,
		"damage_group_id": damage_group_id,
		"damage_type": damage_type,
		"toi": toi,
		"priority": priority,
		"penetration_index": penetration_index,
		"allow_repeat_target": allow_repeat_target,
		"contact_point": contact_point,
	}
