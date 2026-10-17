class_name SimSnapshot
extends RefCounted

## Authoritative per-tick snapshot.
##
## Rows are plain arrays sorted by stable entity key, so byte equality of two
## snapshots proves equal simulation state regardless of insertion or storage
## order. Serialization uses var_to_bytes over arrays of primitives only; no
## Dictionary participates in the serialized form.

const SCHEMA_VERSION: int = 1

var tick: int = 0
var tick_rate: int = 0
var room_instance_id: String = ""
var world_revision: int = -1
var next_stable_key: int = SimStableKey.FIRST_VALID_KEY
var rows: Array = []
var phase_trace: Array[StringName] = []


func entity_count() -> int:
	return rows.size()


## Serializable form: fixed field order, rows already sorted by stable key.
func serialize() -> Array:
	return [
		SCHEMA_VERSION,
		tick,
		tick_rate,
		room_instance_id,
		world_revision,
		next_stable_key,
		rows,
	]


func to_bytes() -> PackedByteArray:
	return var_to_bytes(serialize())


func sha256_hex() -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(to_bytes())
	return context.finish().hex_encode()


func stable_keys() -> Array[int]:
	var keys: Array[int] = []
	for row in rows:
		keys.append(int(row[0]))
	return keys
