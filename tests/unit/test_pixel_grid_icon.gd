extends SceneTree
const Icon = preload("res://src/presentation/pixel_grid_icon.gd")
var errors: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var ancestor := Control.new()
	root.add_child(ancestor)
	var parent := Control.new()
	ancestor.add_child(parent)
	var icon := Icon.new()
	icon.size = Vector2(64, 64)
	icon.position = Vector2(11, 21)
	parent.add_child(icon)
	await _settle()
	_check(icon, "initial")
	for offset in range(32):
		parent.position.y = -offset
		await _settle()
		_check(icon, "consecutive scroll %d" % offset)
		var expected := (Vector2(11, 21) + parent.position).snapped(Vector2(2, 2))
		if not icon.global_position.is_equal_approx(expected):
			errors.append("cumulative drift at %d: %s vs %s" % [offset, icon.global_position, expected])
	parent.position = Vector2.ZERO
	await _settle()
	if icon.global_position != Vector2(12,22): errors.append("return to top drifts")
	for offset in [1, 2, 3, 12, 13, 36, 37, 0]:
		parent.position = Vector2(0, -offset)
		await _settle()
		_check(icon, "parent scroll %d" % offset)
		if parent.position.y != -offset: errors.append("snapping changed scroll offset")
		ancestor.position = Vector2(offset, 1)
		await _settle()
		_check(icon, "grandparent scroll %d" % offset)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	ancestor.reparent(viewport)
	await _settle()
	_check(icon, "nested presentation viewport")
	# Deferred notifications must tolerate a screen rebuild freeing its icons.
	parent.position.y -= 1
	viewport.queue_free()
	await _settle()
	print("PIXEL_GRID_ICON ", "pass" if errors.is_empty() else "fail", " ", errors)
	quit(0 if errors.is_empty() else 1)

func _check(icon: TextureRect, context: String) -> void:
	if not icon.global_position.is_equal_approx(icon.global_position.snapped(Vector2(2, 2))):
		errors.append(context + " off grid: " + str(icon.global_position))
	if icon.size != Vector2(64, 64): errors.append(context + " changed display size")

func _settle() -> void:
	for frame in range(8): await process_frame
