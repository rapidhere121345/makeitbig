class_name DisplayPolicy
extends RefCounted
## Pure window-size policy for the settings menu and the host. It reads no node and
## no OS state; the host passes in the usable screen size. How a window is presented
## (uniform nearest fit of the 1280x720 canvas) stays PixelStage's decision.

const MIN_WINDOW := Vector2i(1024, 576)
const DEFAULT_WINDOW := Vector2i(1600, 900)
const MAX_SAVED_DIMENSION := 16384
const PRESETS: Array[Vector2i] = [
	Vector2i(1024, 576), Vector2i(1280, 720), Vector2i(1280, 800),
	Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(1920, 1200),
	Vector2i(2560, 1080), Vector2i(2560, 1440), Vector2i(2560, 1600),
	Vector2i(3440, 1440), Vector2i(3840, 1600), Vector2i(3840, 2160),
	Vector2i(5120, 1440), Vector2i(5120, 2880),
]
const HINT_FULLSCREEN := "Desktop resolution in fullscreen"
const HINT_ULTRAWIDE := "16:9 view; borders on ultrawide"
const HINT_TALL := "16:9 view; borders above and below"


## Fits a requested window size to the screen. A usable size with a non-positive axis
## means "unknown" (headless) and applies no upper bound. The minimum always wins.
static func fit_window(requested: Vector2i, usable: Vector2i) -> Vector2i:
	var fitted := requested
	if usable.x > 0:
		fitted.x = mini(fitted.x, usable.x)
	if usable.y > 0:
		fitted.y = mini(fitted.y, usable.y)
	return Vector2i(maxi(fitted.x, MIN_WINDOW.x), maxi(fitted.y, MIN_WINDOW.y))


## Reads a persisted value. Only a sane Vector2i is honoured (then clamped to the
## screen); anything else yields `fallback` itself, never a silently substituted size.
static func parse_saved(value: Variant, usable: Vector2i, fallback: Vector2i) -> Vector2i:
	if not value is Vector2i:
		return fallback
	var size: Vector2i = value
	if size.x <= 0 or size.y <= 0 or size.x > MAX_SAVED_DIMENSION or size.y > MAX_SAVED_DIMENSION:
		return fallback
	return fit_window(size, usable)


## Menu entries: presets that fit the screen, plus `current` when it is not one of them,
## ordered by width then height.
static func menu_options(usable: Vector2i, current: Vector2i) -> Array[Vector2i]:
	var options: Array[Vector2i] = []
	for preset in PRESETS:
		if (usable.x <= 0 or preset.x <= usable.x) and (usable.y <= 0 or preset.y <= usable.y):
			options.append(preset)
	return with_entry(options, current)


static func with_entry(options: Array[Vector2i], entry: Vector2i) -> Array[Vector2i]:
	var result := options.duplicate()
	if entry not in result:
		result.append(entry)
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	return result


## Player-facing note for the chosen size. The view is always 16:9, so only a window
## with a different aspect gets borders.
static func hint(resolution: Vector2i, fullscreen: bool) -> String:
	if fullscreen:
		return HINT_FULLSCREEN
	var wide := resolution.x * 9 - resolution.y * 16
	if absi(wide) * 100 < resolution.y * 16:
		return ""
	if wide > 0:
		return HINT_ULTRAWIDE
	return HINT_TALL if wide < 0 else ""


## Unknown, non-finite and hand-edited settings fall back to the standard size.
static func parse_menu_scale(value: Variant) -> float:
	if not (value is float or value is int) or not is_finite(float(value)):
		return 1.0
	for scale: float in [1.0, 1.15, 1.25]:
		if is_equal_approx(float(value), scale):
			return scale
	return 1.0
