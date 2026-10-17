class_name BossDamageValue
extends RefCounted

## Explicit Boss damage transport.
##
## Ordinary damage crosses the room boundary as integer milli-damage.  Large
## damage crosses it as a BigValue.  The two representations are deliberately
## exclusive so a caller cannot accidentally apply the same payload twice.

const BigValueScript := preload("res://src/core/big_value.gd")

const KIND_MILLI := &"milli"
const KIND_BIG := &"big"

var kind: StringName = &""
var milli: int = 0
var big: BigValue = null


static func from_milli(amount: int) -> BossDamageValue:
	if amount < 0:
		return null
	var result := BossDamageValue.new()
	result.kind = KIND_MILLI
	result.milli = amount
	return result


static func from_big(amount: BigValue) -> BossDamageValue:
	if not _valid_big(amount):
		return null
	var result := BossDamageValue.new()
	result.kind = KIND_BIG
	result.big = amount.duplicate_value()
	return result


func validate() -> String:
	if kind == KIND_MILLI:
		if milli < 0 or big != null:
			return "invalid_boss_milli_damage"
		return ""
	if kind == KIND_BIG:
		if not _valid_big(big) or milli != 0:
			return "invalid_boss_big_damage"
		return ""
	return "invalid_boss_damage_kind"


func to_big_value() -> BigValue:
	if not validate().is_empty():
		return null
	if kind == KIND_MILLI:
		return BigValueScript.from_float(float(milli) / 1000.0)
	return big.duplicate_value()


func duplicate_value() -> BossDamageValue:
	if kind == KIND_MILLI:
		return from_milli(milli)
	return from_big(big)


func snapshot() -> Dictionary:
	return {
		"kind": String(kind),
		"milli": milli,
		"big": {
			"layer": int(big.layer),
			"magnitude": float(big.magnitude),
		} if kind == KIND_BIG and big != null else {},
	}


static func _valid_big(value: Variant) -> bool:
	if not value is BigValueScript:
		return false
	var typed: BigValue = value
	if typed.layer < 0 or not is_finite(typed.magnitude):
		return false
	return typed.layer > 0 or typed.magnitude >= 0.0
