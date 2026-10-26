extends SceneTree
## Window-size policy gate (src/presentation/display_policy.gd).
##   godot --headless --path . --script res://tests/unit/test_display_policy.gd

const Policy = preload("res://src/presentation/display_policy.gd")
const Stage = preload("res://src/presentation/pixel_stage.gd")
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	_fit_window()
	_parse_saved()
	_menu_options()
	_hints()
	_presets_present_without_surprises()
	for message in failures:
		printerr(message)
	print("DISPLAY_POLICY ", "pass" if failures.is_empty() else "fail", " checks=", checks)
	quit(0 if failures.is_empty() else 1)


func _fit_window() -> void:
	var screen := Vector2i(1920, 1080)
	_expect(Policy.fit_window(Vector2i(3840, 2160), screen) == screen, "oversized request clamps to the screen")
	_expect(Policy.fit_window(Vector2i(3440, 1440), screen) == Vector2i(1920, 1080), "each axis clamps independently")
	_expect(Policy.fit_window(Vector2i(1600, 900), screen) == Vector2i(1600, 900), "a fitting size is untouched")
	_expect(Policy.fit_window(Vector2i(320, 200), screen) == Vector2i(1024, 576), "below minimum is raised to 1024x576")
	_expect(Policy.fit_window(Vector2i(3840, 2160), Vector2i.ZERO) == Vector2i(3840, 2160), "unknown screen applies no upper bound")
	_expect(Policy.fit_window(Vector2i(2000, 1200), Vector2i(800, 480)) == Vector2i(1024, 576), "the minimum wins over a tiny screen")


func _parse_saved() -> void:
	var fallback := Vector2i(1366, 768)
	var screen := Vector2i(2560, 1440)
	_expect(Policy.parse_saved(Vector2i(1920, 1080), screen, fallback) == Vector2i(1920, 1080), "valid saved size is kept")
	_expect(Policy.parse_saved(Vector2i(3440, 1440), Vector2i(1920, 1080), fallback) == Vector2i(1920, 1080), "saved size larger than this screen is clamped, not replaced")
	_expect(Policy.parse_saved(Vector2i(1500, 800), screen, fallback) == Vector2i(1500, 800), "a non-preset saved size is preserved")
	for bad in [null, "1920x1080", Vector2(1920, 1080), [1920, 1080], 1920, Vector2i(0, 900), Vector2i(-1, -1), Vector2i(1920, 0), Vector2i(99999, 900), {}]:
		_expect(Policy.parse_saved(bad, screen, fallback) == fallback, "bad saved value %s falls back explicitly" % str(bad))


func _menu_options() -> void:
	var on_1080 := Policy.menu_options(Vector2i(1920, 1080), Vector2i(1600, 900))
	_expect(Vector2i(1920, 1080) in on_1080 and Vector2i(2560, 1440) not in on_1080 and Vector2i(3840, 2160) not in on_1080, "presets above the screen are not offered")
	var on_ultrawide := Policy.menu_options(Vector2i(3440, 1440), Vector2i(1600, 900))
	_expect(Vector2i(2560, 1440) in on_ultrawide and Vector2i(3440, 1440) in on_ultrawide and Vector2i(3840, 2160) not in on_ultrawide, "ultrawide screen offers 1440p and 3440x1440 but not 4K")
	var odd := Policy.menu_options(Vector2i(1920, 1080), Vector2i(1500, 800))
	_expect(Vector2i(1500, 800) in odd, "the current non-preset size is listed")
	_expect(_sorted(odd), "options are sorted by width then height")
	var tiny := Policy.menu_options(Vector2i(800, 480), Vector2i(1024, 576))
	_expect(tiny == [Vector2i(1024, 576)], "when nothing fits, only the current size remains, got %s" % str(tiny))
	var no_dupes := Policy.menu_options(Vector2i.ZERO, Vector2i(1920, 1080))
	_expect(no_dupes.count(Vector2i(1920, 1080)) == 1 and no_dupes.size() == Policy.PRESETS.size(), "current preset is not duplicated and unknown screens offer all presets")


func _hints() -> void:
	_expect(Policy.hint(Vector2i(3440, 1440), false) == "16:9 view; borders on ultrawide", "ultrawide hint")
	_expect(Policy.hint(Vector2i(1600, 1000), false) == "16:9 view; borders above and below", "16:10 hint")
	for size in [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1920, 1080), Vector2i(3840, 2160)]:
		_expect(Policy.hint(size, false).is_empty(), "%s is 16:9 and needs no hint" % str(size))
	_expect(Policy.hint(Vector2i(3440, 1440), true) == "Desktop resolution in fullscreen", "fullscreen hint wins")


func _presets_present_without_surprises() -> void:
	for size in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3440, 1440), Vector2i(3840, 2160)]:
		_expect(size in Policy.PRESETS, "%s must be offered" % str(size))
	for preset in Policy.PRESETS:
		_expect(preset.x >= Policy.MIN_WINDOW.x and preset.y >= Policy.MIN_WINDOW.y, "%s respects the minimum" % str(preset))
		var layout := Stage.layout_for_window(preset)
		var stage_size: Vector2i = layout.stage_size
		var border_pixels := preset.x - stage_size.x + preset.y - stage_size.y
		var has_hint := not Policy.hint(preset, false).is_empty()
		_expect(has_hint == (border_pixels * 100 > preset.x + preset.y), "%s: hint must agree with the stage's real borders (%s)" % [str(preset), str(layout.stage_size)])


func _sorted(options: Array[Vector2i]) -> bool:
	for i in range(1, options.size()):
		if options[i - 1].x > options[i].x or (options[i - 1].x == options[i].x and options[i - 1].y > options[i].y):
			return false
	return true


func _expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
