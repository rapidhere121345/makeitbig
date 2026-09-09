class_name DeterministicRng
extends RefCounted

## Small deterministic PRNG for gameplay streams.
##
## The algorithm and seed derivation are deliberately owned by the project:
## no engine RNG, engine hash, wall clock, or platform-sized arithmetic is used.
## All state transitions are explicitly reduced to 32 bits.

const STATE_VERSION: int = 1
const ALGORITHM: String = "xorshift32-fnv1a-v1"
const UINT32_MASK: int = 0xffffffff
const UINT32_RANGE: int = 0x100000000
const FNV_OFFSET: int = 2166136261
const FNV_PRIME: int = 16777619
const ZERO_STATE_REPLACEMENT: int = 0x6d2b79f5
const SEED_DOMAIN: String = "makeitbig-rng-v1"

var _state: int = ZERO_STATE_REPLACEMENT


func _init(root_seed: int = 0, stream_name: String = "default") -> void:
	_state = _derive_state(root_seed, stream_name)


static func create(root_seed: int, stream_name: String) -> DeterministicRng:
	return DeterministicRng.new(root_seed, stream_name)


func next_u32() -> int:
	var value: int = _state
	value = (value ^ ((value << 13) & UINT32_MASK)) & UINT32_MASK
	value = (value ^ (value >> 17)) & UINT32_MASK
	value = (value ^ ((value << 5) & UINT32_MASK)) & UINT32_MASK
	_state = value
	return value


func next_int(bound_exclusive: int) -> int:
	if bound_exclusive <= 0 or bound_exclusive > UINT32_RANGE:
		return -1
	# Rejection sampling avoids modulo bias while retaining a fixed algorithm.
	var acceptance_limit: int = UINT32_RANGE - (UINT32_RANGE % bound_exclusive)
	while true:
		var candidate: int = next_u32()
		if candidate < acceptance_limit:
			return candidate % bound_exclusive
	return -1


func next_float() -> float:
	return float(next_u32()) / float(UINT32_RANGE)


func export_state() -> Dictionary:
	return {
		"algorithm": ALGORITHM,
		"state": _state,
		"version": STATE_VERSION,
	}


func restore_state(snapshot: Dictionary) -> bool:
	if int(snapshot.get("version", -1)) != STATE_VERSION:
		return false
	if str(snapshot.get("algorithm", "")) != ALGORITHM:
		return false
	var raw_state: Variant = snapshot.get("state")
	if typeof(raw_state) != TYPE_INT and typeof(raw_state) != TYPE_FLOAT:
		return false
	var restored: int = int(raw_state)
	if float(restored) != float(raw_state) or restored <= 0 or restored > UINT32_MASK:
		return false
	_state = restored
	return true


static func _derive_state(root_seed: int, stream_name: String) -> int:
	var hash_value: int = FNV_OFFSET
	hash_value = _fnv1a_bytes(hash_value, SEED_DOMAIN.to_utf8_buffer())
	hash_value = _fnv1a_byte(hash_value, 0)
	hash_value = _fnv1a_bytes(hash_value, str(root_seed).to_utf8_buffer())
	hash_value = _fnv1a_byte(hash_value, 0)
	hash_value = _fnv1a_bytes(hash_value, stream_name.to_utf8_buffer())
	return ZERO_STATE_REPLACEMENT if hash_value == 0 else hash_value


static func _fnv1a_bytes(initial: int, bytes: PackedByteArray) -> int:
	var hash_value: int = initial
	for byte in bytes:
		hash_value = _fnv1a_byte(hash_value, byte)
	return hash_value


static func _fnv1a_byte(hash_value: int, byte: int) -> int:
	return ((hash_value ^ byte) * FNV_PRIME) & UINT32_MASK
