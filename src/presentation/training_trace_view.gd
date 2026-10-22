class_name TrainingTraceView
extends Control

## Discrete generational trace of one verified training report.
##
## The view draws exactly the points it is handed and derives nothing: one node
## per generation of the growth_curve that belongs to the current build
## fingerprint, its own display string, and, only when every point carries a
## finite positive number, a value axis. The axis is log10 and says so; when a
## report's numbers are not comparable decimal readings, the view drops the value
## axis entirely and draws the generation order only, which is what the data
## actually supports.
##
## It never draws a previous report as the current one, never invents an
## intermediate generation, never normalises a "power" bar, and never labels a
## point the report does not contain. The page decides which report is the
## matching one and only calls present() with its points.
const ShellThemeScript = preload("res://src/presentation/shell_theme.gd")

const MODE_LOG := "log10"
const MODE_ORDER := "order"
## 18px floor of the formal shell: the drawn values and generation labels use the
## same step as every Label on the page.
const LABEL_FONT_SIZE := 18
const NODE_RADIUS := 6.0
const LAST_RING_RADIUS := 10.0
const RING_WIDTH := 2.0
const LINE_WIDTH := 2.0
const TICK_LENGTH := 5.0
const PAD_LEFT := 18.0
const PAD_RIGHT := 18.0
## Room for the value labels above the highest node and the G labels under the
## baseline, so no drawn number is clipped by the control's own rect.
const PAD_TOP := 32.0
const PAD_BOTTOM := 46.0
const MIN_HEIGHT := 156.0
const LABEL_GAP := 6.0
const ARROW_LENGTH := 8.0
const ARROW_ANGLE := 0.4

var _points: Array[Dictionary] = []
var _mode := MODE_ORDER
var _label_stride := 1
var _flat_magnitude := NAN


## Hands over the already-filtered points of the matching report, oldest
## generation first. Every entry must carry an exact-int generation and a
## non-empty events_display; magnitude is used for the value axis and may be NAN
## when the report has no comparable number for that point.
func present(points: Array) -> void:
	_points = []
	for raw: Variant in points:
		if not raw is Dictionary:
			continue
		var point: Dictionary = raw
		var generation: Variant = point.get("generation", null)
		if typeof(generation) != TYPE_INT:
			continue
		var display := String(point.get("events_display", "")).strip_edges()
		if display.is_empty():
			continue
		var magnitude := NAN
		var raw_magnitude: Variant = point.get("magnitude", null)
		if _is_finite_number(raw_magnitude):
			magnitude = float(raw_magnitude)
		_points.append({
			"generation": int(generation),
			"events_display": display,
			"magnitude": magnitude,
		})
	_points.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("generation", 0)) < int(right.get("generation", 0))
	)
	_mode = MODE_LOG if _axis_is_available() else MODE_ORDER
	# The page reads the caption before the first draw; never leave the preceding
	# report's equal-value axis explanation attached to the new report.
	_flat_magnitude = NAN
	if _mode == MODE_LOG:
		var range_decades := _decades()
		if is_equal_approx(range_decades.x, range_decades.y):
			_flat_magnitude = range_decades.x
	custom_minimum_size = Vector2(0.0, MIN_HEIGHT)
	queue_redraw()


## True while a real trace is on the control: at least one published point and a
## layout to draw it in. False leaves the page with its text only.
func is_drawing() -> bool:
	return not _points.is_empty()


## The value axis the trace actually used, in one line of page copy. A log axis is
## always named here; MODE_ORDER states that no value axis was drawn instead of
## implying one.
func axis_caption() -> String:
	if _points.is_empty():
		return "Generation trace: no drawable generation samples match the current fingerprint."
	if _mode == MODE_LOG:
		if is_finite(_flat_magnitude):
			return "Numeric Y-axis: log10 event count (log scale) · All generations have the same event count (log10 = %s); points share the same height." % _format_decade(_flat_magnitude)
		return "Generation samples · Y-axis: event count (log10 scale)"
	return "Numeric Y-axis: not used · Generation order only, not magnitude"


## Everything a test or the art pass may quote about the trace. Read-only.
func trace_report() -> Dictionary:
	var generations: Array[int] = []
	var displays: Array[String] = []
	var magnitudes: Array = []
	for point in _points:
		generations.append(int(point.get("generation", 0)))
		displays.append(String(point.get("events_display", "")))
		var magnitude: float = point.get("magnitude", NAN)
		magnitudes.append(magnitude if is_finite(magnitude) else null)
	return {
		"mode": _mode,
		"drawing": is_drawing(),
		"point_count": _points.size(),
		"generations": generations,
		"events_display": displays,
		"magnitudes": magnitudes,
		"label_stride": _label_stride,
		"flat_decade": _flat_magnitude if is_finite(_flat_magnitude) else null,
		"axis_caption": axis_caption(),
		"min_height": MIN_HEIGHT,
	}


func _axis_is_available() -> bool:
	if _points.size() < 2:
		return false
	for point in _points:
		var magnitude: float = point.get("magnitude", NAN)
		if not is_finite(magnitude) or magnitude <= 0.0:
			return false
	return true


func _decades() -> Vector2:
	var low := INF
	var high := -INF
	for point in _points:
		var decade := log(float(point.get("magnitude", 1.0))) / log(10.0)
		low = minf(low, decade)
		high = maxf(high, decade)
	return Vector2(low, high)


func _font() -> Font:
	var themed := get_theme_default_font()
	return themed if themed != null else ThemeDB.fallback_font


func _draw() -> void:
	if _points.is_empty():
		return
	var font := _font()
	if font == null:
		return
	var baseline := size.y - PAD_BOTTOM
	var ceiling := PAD_TOP
	if baseline <= ceiling:
		baseline = size.y - 1.0
		ceiling = 1.0
	var right := maxf(PAD_LEFT + 1.0, size.x - PAD_RIGHT)
	var positions: Array[Vector2] = []
	var amplitude := _decades() if _mode == MODE_LOG else Vector2.ZERO
	var flat := is_finite(amplitude.x) and is_equal_approx(amplitude.x, amplitude.y)
	_flat_magnitude = amplitude.x if (_mode == MODE_LOG and flat) else NAN
	for index in _points.size():
		var ratio := 0.0 if _points.size() < 2 else float(index) / float(_points.size() - 1)
		var x := lerpf(PAD_LEFT, right, ratio)
		var y := baseline
		if _mode == MODE_LOG:
			if flat:
				y = (ceiling + baseline) * 0.5
			else:
				var decade := log(float(_points[index].get("magnitude", 1.0))) / log(10.0)
				var t := (decade - amplitude.x) / (amplitude.y - amplitude.x)
				y = lerpf(baseline, ceiling, clampf(t, 0.0, 1.0))
		positions.append(Vector2(x, y))
	# The axis itself: a baseline always, a top reference line only when a value
	# axis is really in use. Both are drawn before the nodes so the trace reads on
	# top of its own frame.
	draw_line(Vector2(PAD_LEFT - 6.0, baseline), Vector2(right + 6.0, baseline), ShellThemeScript.GROUND, 1.0)
	if _mode == MODE_LOG:
		draw_line(Vector2(PAD_LEFT - 6.0, ceiling), Vector2(right + 6.0, ceiling), ShellThemeScript.GROUND, 1.0)
	if _mode == MODE_LOG and positions.size() >= 2:
		draw_polyline(positions, ShellThemeScript.COPPER_DULL, LINE_WIDTH, true)
	elif _mode == MODE_ORDER:
		for index in range(0, positions.size() - 1):
			_draw_arrow(positions[index], positions[index + 1], ShellThemeScript.NEUTRAL)
	var stride := _label_stride_for(font, positions)
	_label_stride = stride
	for index in positions.size():
		var position: Vector2 = positions[index]
		var last := index == positions.size() - 1
		var labelled := index % stride == 0 or last
		if _mode == MODE_LOG:
			draw_line(
				Vector2(position.x, baseline),
				Vector2(position.x, baseline + TICK_LENGTH),
				ShellThemeScript.GROUND, 1.0
			)
		draw_circle(position, NODE_RADIUS, ShellThemeScript.BONE)
		if last:
			draw_arc(position, LAST_RING_RADIUS, 0.0, TAU, 28, ShellThemeScript.AMBER, RING_WIDTH)
		if not labelled:
			continue
		_draw_centered_text(
			font,
			String(_points[index].get("events_display", "")),
			Vector2(position.x, position.y - NODE_RADIUS - LABEL_GAP),
			ShellThemeScript.BONE
		)
		_draw_centered_text(
			font,
			"G%d" % int(_points[index].get("generation", 0)),
			Vector2(position.x, baseline + TICK_LENGTH + LABEL_GAP + float(LABEL_FONT_SIZE)),
			ShellThemeScript.NEUTRAL
		)


## One label per point while they fit; otherwise every stride-th point plus the
## last one, so the drawn text never overlaps and the newest generation is always
## readable. The full value list stays in the page's own text line either way.
func _label_stride_for(font: Font, positions: Array[Vector2]) -> int:
	if positions.size() < 3:
		return 1
	var widest := 0.0
	for point in _points:
		widest = maxf(widest, font.get_string_size(
			String(point.get("events_display", "")),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_FONT_SIZE
		).x)
	var spacing := positions[1].x - positions[0].x
	if spacing <= 1.0:
		return maxi(1, positions.size())
	return maxi(1, int(ceil((widest + 10.0) / spacing)))


func _draw_centered_text(font: Font, text: String, center: Vector2, color: Color) -> void:
	if text.is_empty():
		return
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_FONT_SIZE).x
	var x := clampf(center.x - width * 0.5, 0.0, maxf(0.0, size.x - width))
	draw_string(
		font,
		Vector2(x, center.y),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		LABEL_FONT_SIZE,
		color
	)


func _draw_arrow(from: Vector2, to: Vector2, color: Color) -> void:
	var direction := (to - from)
	if direction.length() <= 1.0:
		return
	direction = direction.normalized()
	var start := from + direction * (NODE_RADIUS + 2.0)
	var end := to - direction * (NODE_RADIUS + 2.0)
	if start.distance_to(end) <= 1.0:
		return
	draw_line(start, end, color, LINE_WIDTH)
	draw_line(end, end - direction.rotated(ARROW_ANGLE) * ARROW_LENGTH, color, LINE_WIDTH)
	draw_line(end, end - direction.rotated(-ARROW_ANGLE) * ARROW_LENGTH, color, LINE_WIDTH)


func _format_decade(decade: float) -> String:
	return String.num(decade, 3)


func _is_finite_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) == TYPE_FLOAT:
		return is_finite(float(value))
	return false
