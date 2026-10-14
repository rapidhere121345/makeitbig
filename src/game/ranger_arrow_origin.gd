class_name RangerArrowOrigin
extends RefCounted

## Shared bow socket values. Gameplay freezes the release offset using this
## spatial contract; views may project the same sockets at any display scale.
## No atlas, renderer, camera, node or presentation clock determines a launch.
const Rules := preload("res://src/systems/ranger_skill_rules.gd")
const FOOT_ANCHOR := Vector2i(24, 44)
const NATIVE_UNITS_PER_GAMEPLAY := 0.72
const SHOOT_FRAMES := 4
const SHOOT_FPS := 12
const SOCKETS := {
	"south": [Vector2i(30, 27), Vector2i(27, 25), Vector2i(27, 25), Vector2i(31, 29)],
	"north": [Vector2i(24, 17), Vector2i(24, 15), Vector2i(24, 15), Vector2i(24, 20)],
	"east": [Vector2i(34, 23), Vector2i(34, 24), Vector2i(36, 24), Vector2i(34, 29)],
	"west": [Vector2i(14, 23), Vector2i(14, 24), Vector2i(12, 24), Vector2i(14, 29)],
}


static func release_offset(facing: Vector2) -> Vector2:
	return attachment_offset(facing, shoot_frame_at_tick(Rules.PIERCING_ARROW_WINDUP_TICKS), NATIVE_UNITS_PER_GAMEPLAY)


static func shoot_frame_at_tick(ticks: int) -> int:
	var seconds := float(maxi(0, ticks)) / float(Rules.TICKS_PER_SECOND)
	return mini(int(floor(seconds * float(SHOOT_FPS))), SHOOT_FRAMES - 1)


static func attachment_local(facing: Variant, frame: int) -> Vector2i:
	var sockets: Array = SOCKETS[facing_key(facing)]
	return sockets[clampi(frame, 0, sockets.size() - 1)] as Vector2i


static func attachment_offset(facing: Variant, frame: int, native_units_per_gameplay: float) -> Vector2:
	if not is_finite(native_units_per_gameplay) or native_units_per_gameplay <= 0.0:
		return Vector2.ZERO
	return Vector2(attachment_local(facing, frame) - FOOT_ANCHOR) / native_units_per_gameplay


static func facing_key(facing: Variant) -> String:
	if facing is String:
		var key := String(facing).to_lower()
		return key if SOCKETS.has(key) else "south"
	if not facing is Vector2:
		return "south"
	var direction := facing as Vector2
	if direction.length_squared() <= 0.0001:
		return "south"
	if absf(direction.x) >= absf(direction.y):
		return "east" if direction.x > 0.0 else "west"
	return "north" if direction.y < 0.0 else "south"
