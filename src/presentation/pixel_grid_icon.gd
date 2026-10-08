class_name PixelGridIcon
extends TextureRect
## A 32px atlas cell displayed at 2x must keep its actual origin on the 2px
## logical grid, including when a ScrollContainer moves an ancestor. Local rect
## notifications alone do not cover that case at the 1.5x UI/window scale.
var _snap_pending := false
var _local_correction := Vector2.ZERO
var _last_snapped_position := Vector2.ZERO
var _has_snapped := false
const Shell = preload("res://src/presentation/shell_theme.gd")

func _ready() -> void:
	# A physical cloth/copper well behind the unchanged equipment silhouette.
	# This child draws behind TextureRect and cannot consume input or affect a
	# Container minimum. Framed skill/law atlases simply cover the same backing.
	var backing := TextureRect.new()
	backing.name = "HearthsideIconWell"
	backing.texture = Shell.material_texture("icon_well")
	backing.show_behind_parent = true
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backing.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	backing.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backing.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(backing)
	backing.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_notify_transform(true)
	item_rect_changed.connect(_queue_snap)
	_queue_snap()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_queue_snap()

func _queue_snap() -> void:
	if not is_inside_tree() or _snap_pending:
		return
	_snap_pending = true
	_snap_origin.call_deferred()

func _snap_origin() -> void:
	_snap_pending = false
	if not is_inside_tree():
		return
	# Parent scrolling leaves local position unchanged. A Container relayout does
	# not: in that case its new assigned position is the new unsnapped baseline.
	if _has_snapped and not position.is_equal_approx(_last_snapped_position):
		_local_correction = Vector2.ZERO
	var raw_local := position - _local_correction
	var parent_transform: Transform2D = get_global_transform() * get_transform().affine_inverse()
	var raw_global := parent_transform * raw_local
	var desired := parent_transform.affine_inverse() * raw_global.snapped(Vector2(2, 2))
	_local_correction = desired - raw_local
	_last_snapped_position = desired
	_has_snapped = true
	if not position.is_equal_approx(desired):
		position = desired
