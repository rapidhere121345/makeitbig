extends SceneTree
## Headless, offscreen evidence report for the ranger motion overlay.
##
## Crops the published skin for representative poses, composites the exact
## accent plan the draw calls would paint (1 px steps, alpha over), and writes
## 1x and 4x nearest-neighbor PNGs plus side-by-side comparison strips into
## the git-ignored build/current/overlay-report/. Run:
##   source scripts/container_env.sh
##   mib_godot --headless --path . --script res://tools/art_pipeline/ranger_overlay_report.gd
## This script is not part of scripts/test.sh or tests/run_all.gd.

const RangerAnimationScript = preload("res://src/presentation/ranger_animation.gd")
const RangerMotionOverlayScript = preload("res://src/presentation/ranger_motion_overlay.gd")

const OUTPUT_DIR := "res://build/current/overlay-report"
## The poses a reviewer should compare first.
const REPORT_POSES: Array = [
	["west", "walk"], ["west", "idle"], ["west", "shoot"],
	["east", "walk"], ["north", "walk"], ["south", "walk"],
	["west", "dodge"], ["west", "death"],
]


func _initialize() -> void:
	var animation = RangerAnimationScript.new()
	if not animation.has_real_art() or not RangerMotionOverlayScript._evidence_ready():
		printerr("report: published ranger art or overlay evidence unavailable")
		quit(1)
		return
	var out_path := ProjectSettings.globalize_path(OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_path)
	var skin: Image = RangerMotionOverlayScript._evidence_image
	var written: Array[String] = []
	for pose: Array in REPORT_POSES:
		var facing := String(pose[0])
		var action := String(pose[1])
		var frame_count: int = RangerAnimationScript.ACTION_CONTRACT[action]["frames"]
		var crops: Array[Image] = []
		for frame in frame_count:
			var authored: Dictionary = animation.frame_for(RangerAnimationScript.clip_id(facing, action), frame)
			var rect := authored["rect"] as Rect2i
			var crop := skin.get_region(rect)
			_composite_plan(crop, facing, action, frame)
			crops.append(crop)
			var base := "%s/%s-%s-f%d.png" % [out_path, facing, action, frame]
			crop.save_png(base)
			var big := crop.duplicate() as Image
			big.resize(192, 192, Image.INTERPOLATE_NEAREST)
			big.save_png("%s/%s-%s-f%d-4x.png" % [out_path, facing, action, frame])
			written.append("%s-%s-f%d-4x.png" % [facing, action, frame])
		var strip := _strip(crops, 4)
		var strip_path := "%s/%s-%s-strip-4x.png" % [out_path, facing, action]
		strip.save_png(strip_path)
		written.append("%s-%s-strip-4x.png" % [facing, action])
		var plain: Array[Image] = []
		for frame in frame_count:
			var authored: Dictionary = animation.frame_for(RangerAnimationScript.clip_id(facing, action), frame)
			plain.append(skin.get_region(authored["rect"] as Rect2i))
		var top := _strip(plain, 4)
		var compare := Image.create(top.get_width(), top.get_height() * 2 + 8, false, Image.FORMAT_RGBA8)
		compare.blend_rect(top, Rect2i(Vector2i.ZERO, top.get_size()), Vector2i(0, 0))
		compare.blend_rect(strip, Rect2i(Vector2i.ZERO, strip.get_size()), Vector2i(0, top.get_height() + 8))
		var compare_path := "%s/%s-%s-compare-4x.png" % [out_path, facing, action]
		compare.save_png(compare_path)
		written.append("%s-%s-compare-4x.png" % [facing, action])
	for name: String in written:
		print("wrote ", name)
	quit(0)


## Paints exactly what draw_back/draw_front would paint, alpha over the crop.
func _composite_plan(crop: Image, facing: String, action: String, frame: int) -> void:
	for entry: Dictionary in RangerMotionOverlayScript._accent_plan(facing, action, frame, 0.35):
		var point := entry["point"] as Vector2i
		var cell := point + Vector2i(24, 44)
		if cell.x < 0 or cell.x >= 48 or cell.y < 0 or cell.y >= 48:
			continue
		var src := entry["color"] as Color
		var dst := crop.get_pixel(cell.x, cell.y)
		var blended := Color(
			src.r * src.a + dst.r * (1.0 - src.a),
			src.g * src.a + dst.g * (1.0 - src.a),
			src.b * src.a + dst.b * (1.0 - src.a),
			1.0 if dst.a > src.a else dst.a + src.a * (1.0 - dst.a)
		)
		crop.set_pixel(cell.x, cell.y, blended)


func _strip(crops: Array[Image], scale: int) -> Image:
	var gap := 8
	var width := crops.size() * 48 * scale + (crops.size() - 1) * gap
	var strip := Image.create(width, 48 * scale, false, Image.FORMAT_RGBA8)
	var offset := 0
	for crop: Image in crops:
		var scaled := crop.duplicate() as Image
		scaled.resize(48 * scale, 48 * scale, Image.INTERPOLATE_NEAREST)
		strip.blend_rect(scaled, Rect2i(Vector2i.ZERO, scaled.get_size()), Vector2i(offset, 0))
		offset += 48 * scale + gap
	return strip
